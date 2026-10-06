"""The coach subcommands. Each returns a process exit code and prints for a human."""
from __future__ import annotations

import hashlib
import json
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from . import device, reviewer, stats as stats_mod
from .util import (CoachError, coach_home, format_time, new_review_folder, read_json, resolve_review,
                   review_folders, write_json)
from .validate import validate

PROFILE_TEMPLATE = """\
# Lifter profile

The coach reads this at the start of every review. Edit it freely; the coach
never rewrites what you wrote. A line you leave blank is simply not used.

## Goals

- Main goal: muscle size and appearance, strength second
- What you would call a good result in 6 months:

## Priority muscles

Priority muscles:

(Comma separated, most important first. This exact line is read by the stats.)

## Injuries and pain history

- Anything that has hurt, which side, when it started, what aggravates it:

## Equipment

- Gym or home, and anything missing (no cables, no hack squat, dumbbells up to 40 kg):

## Days available

Days available:

"""


def _say(text: str = "") -> None:
    print(text)


# --- init -------------------------------------------------------------------

def init(home: Path | None = None) -> int:
    home = home or coach_home()
    (home / "reviews").mkdir(parents=True, exist_ok=True)
    profile = home / "profile.md"
    if profile.exists():
        _say(f"{profile} already exists; left as it is.")
    else:
        profile.write_text(PROFILE_TEMPLATE, encoding="utf-8")
        _say(f"Wrote {profile}. Fill it in before the first review.")
    return 0


# --- pull -------------------------------------------------------------------

def _check_snapshot(path: Path) -> None:
    data = read_json(path)
    if not (isinstance(data, dict) and isinstance(data.get("plans"), list) and isinstance(data.get("sessions"), list)):
        raise CoachError(f"{path} is not a GymTrack backup (no plans and sessions)")
    if data.get("version") != 2:
        raise CoachError(f"{path} has version {data.get('version')!r}; this tool reads version 2")
    plan = stats_mod.active_plan(data)
    if plan is not None and not plan.get("id"):
        _say("Note: this export carries no plan ids, so no proposal can target it. Install a build that writes "
             "them and export again.")


def pull(file: str | None = None, home: Path | None = None) -> int:
    home = home or coach_home()
    with tempfile.TemporaryDirectory(prefix="coach-pull-") as scratch:
        scratch = Path(scratch)
        decisions_note = None
        if file:
            source = Path(file).expanduser()
            if not source.is_file():
                raise CoachError(f"{source} does not exist")
            shutil.copyfile(source, scratch / "snapshot.json")
        else:
            phone = device.require_phone()
            problem = device.copy_from(phone, device.SNAPSHOT_PATH, scratch / "snapshot.json")
            if problem:
                raise CoachError("Could not copy the snapshot off the phone: " + problem +
                                 "\nThe app writes it when a workout finishes or a plan is saved; finish or save "
                                 "something and try again, or use `coach pull --file PATH`.")
            if device.copy_from(phone, device.DECISIONS_PATH, scratch / "decisions.json"):
                decisions_note = "No decisions.json on the phone yet (nothing has been proposed and decided)."
        _check_snapshot(scratch / "snapshot.json")
        folder = new_review_folder(home)
        for name in ("snapshot.json", "decisions.json"):
            if (scratch / name).exists():
                shutil.copyfile(scratch / name, folder / name)
    if decisions_note:
        _say(decisions_note)
    _say(str(folder))
    return 0


# --- stats ------------------------------------------------------------------

def _previous_review(folder: Path, home: Path) -> Path | None:
    folders = review_folders(home)
    resolved = folder.resolve()
    if resolved not in [other.resolve() for other in folders]:
        return None
    earlier = []
    for other in folders:
        if other.resolve() == resolved:
            break
        if (other / "snapshot.json").exists():
            earlier.append(other)
    return earlier[-1] if earlier else None


def _proposal_index(home: Path) -> dict:
    index = {}
    for folder in review_folders(home):
        path = folder / "proposal.json"
        if path.exists():
            try:
                proposal = read_json(path)
            except CoachError:
                continue
            if isinstance(proposal, dict) and proposal.get("id"):
                index[str(proposal["id"]).lower()] = proposal
    return index


def compute_stats(folder: Path, home: Path) -> dict:
    snapshot = read_json(folder / "snapshot.json")
    decisions = read_json(folder / "decisions.json") if (folder / "decisions.json").exists() else None
    previous_folder = _previous_review(folder, home)
    previous = read_json(previous_folder / "snapshot.json") if previous_folder else None
    profile_path = home / "profile.md"
    profile = profile_path.read_text(encoding="utf-8") if profile_path.exists() else None
    return stats_mod.compute(
        snapshot, decisions=decisions, previous=previous, proposals=_proposal_index(home), profile_text=profile,
        previous_exported_at=(previous or {}).get("exportedAt"))


def stats(arg: str | None = None, home: Path | None = None) -> int:
    home = home or coach_home()
    folder = resolve_review(arg, home)
    result = compute_stats(folder, home)
    write_json(folder / "stats.json", result)
    (folder / "stats.md").write_text(stats_mod.render_markdown(result), encoding="utf-8")
    _say(f"{folder / 'stats.md'}")
    _say(result["review"]["summary"])
    return 0


# --- proposal rounds --------------------------------------------------------

def fingerprint(change: dict) -> str:
    """What the reviewer saw of a change, so editing it afterwards is detectable."""
    body = {k: v for k, v in change.items() if k not in ("review", "reply")}
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":")).encode()).hexdigest()[:16]


def _load_review_inputs(folder: Path, home: Path):
    snapshot = read_json(folder / "snapshot.json")
    stats_json = read_json(folder / "stats.json") if (folder / "stats.json").exists() else None
    if stats_json is None:
        raise CoachError(f"no stats.json in {folder}; run `coach stats` first")
    stats_md = (folder / "stats.md").read_text(encoding="utf-8") if (folder / "stats.md").exists() else ""
    profile_path = home / "profile.md"
    profile = profile_path.read_text(encoding="utf-8") if profile_path.exists() else ""
    return snapshot, stats_json, stats_md, profile


def _print_problems(problems: list[str]) -> int:
    print(f"The proposal has {len(problems)} problem(s):")
    for problem in problems:
        print(f"  - {problem}")
    print("Fix proposal.json and run the command again. Nothing was sent.")
    return 1


def _print_notes(round_number: int, review: dict, changes: list[dict]) -> None:
    _say(f"Notes from an independent reviewer, round {round_number}:")
    for row in review["changes"]:
        _say(f"  {row['id']}: {row['verdict']} {row['score']}/5. {row['note']}")
    if review.get("summary"):
        _say(f"  Overall: {review['summary']}")


def submit(arg: str | None = None, home: Path | None = None) -> int:
    home = home or coach_home()
    folder = resolve_review(arg, home)
    proposal_path = folder / "proposal.json"
    if (folder / "review-2.json").exists():
        raise CoachError("Both reviewer rounds are done for this review. Settle any disputed change, show the user, then "
                         "run `coach push`. To start over, delete review-1.json and review-2.json and restore "
                         "proposal.json without reviews or replies.")
    proposal = read_json(proposal_path)
    snapshot, stats_json, stats_md, profile = _load_review_inputs(folder, home)
    round_two = (folder / "review-1.json").exists()
    metrics = stats_json.get("metrics")
    if not round_two:
        problems = validate(proposal, snapshot, metrics)
        if problems:
            return _print_problems(problems)
        return _round_one(folder, proposal, snapshot, stats_json, stats_md, profile)
    return _round_two(folder, proposal, snapshot, stats_json, stats_md, profile, metrics)


def _round_one(folder, proposal, snapshot, stats_json, stats_md, profile) -> int:
    if not proposal["changes"]:
        write_json(folder / "review-2.json", {"round": 2, "changes": [], "reviewed": {},
                                              "summary": "Advice only; no plan change to review."})
        _say("This proposal is advice only, with no plan change for the reviewer to argue against. Run `coach push`.")
        return 0
    prompt = reviewer.build_prompt(profile, stats_md, stats_json, snapshot, proposal, 1)
    text, meta = reviewer.run(prompt)
    ids = [c["id"] for c in proposal["changes"]]
    review = reviewer.parse_reply(text, ids)
    review["round"] = 1
    review["reviewed"] = {c["id"]: fingerprint(c) for c in proposal["changes"]}
    review["meta"] = meta
    write_json(folder / "review-1.json", review)
    _print_notes(1, review, proposal["changes"])
    _say("")
    _say("Next: answer each change in proposal.json with "
         '"reply": {"stance": "revised|defended|withdrawn", "text": "..."}, then run `coach submit` again. '
         "A defended change must stay as it is; a revised one must differ; a withdrawn one is removed.")
    return 0


def _round_two(folder, proposal, snapshot, stats_json, stats_md, profile, metrics) -> int:
    round_one = read_json(folder / "review-1.json")
    problems = validate(proposal, snapshot, metrics, allow_reply=True)
    changes = proposal.get("changes", []) if isinstance(proposal, dict) else []
    for change in changes:
        if not isinstance(change, dict):
            continue
        label = f"change {change.get('id')}"
        reply = change.get("reply")
        if not isinstance(reply, dict):
            problems.append(f"{label}: needs a reply (revised, defended or withdrawn) before round 2")
            continue
        if change.get("id") not in round_one["reviewed"]:
            problems.append(f"{label}: was not part of round 1; revise an existing change or withdraw it")
            continue
        changed = fingerprint(change) != round_one["reviewed"][change["id"]]
        stance = reply.get("stance")
        if stance == "defended" and changed:
            problems.append(f"{label}: replied defended but the change was edited; use revised")
        if stance == "revised" and not changed:
            problems.append(f"{label}: replied revised but the change is unchanged; use defended or edit it")
    # A withdrawn change need not stand up to validation: it is leaving.
    withdrawn_ids = {c["id"] for c in changes if isinstance(c, dict) and isinstance(c.get("reply"), dict)
                     and c["reply"].get("stance") == "withdrawn" and isinstance(c.get("id"), str)}
    problems = [p for p in problems if not any(p.startswith(f"change {wid}:") for wid in withdrawn_ids)]
    if problems:
        return _print_problems(problems)

    write_json(folder / "proposal.round2-input.json", proposal)
    withdrawn = [c for c in changes if c["id"] in withdrawn_ids]
    proposal["changes"] = [c for c in changes if c["id"] not in withdrawn_ids]
    for change in withdrawn:
        _say(f"{change['id']} withdrawn by the coach: {change['reply']['text']}")
    if not proposal["changes"]:
        result = {"round": 2, "changes": [], "summary": "Every change was withdrawn.", "reviewed": {},
                  "withdrawn": [{"id": c["id"], "reply": c["reply"]} for c in withdrawn]}
        write_json(folder / "review-2.json", result)
        write_json(folder / "proposal.json", proposal)
        _say("Every change was withdrawn: keep the plan. Nothing to push unless advice remains.")
        return 0

    prompt = reviewer.build_prompt(profile, stats_md, stats_json, snapshot, proposal, 2, previous_review=round_one)
    text, meta = reviewer.run(prompt)
    review = reviewer.parse_reply(text, [c["id"] for c in proposal["changes"]])
    by_id = {row["id"]: row for row in review["changes"]}
    for change in proposal["changes"]:
        row = by_id[change["id"]]
        change["review"] = {"verdict": row["verdict"], "score": row["score"], "note": row["note"],
                            "disputed": row["verdict"] in ("doubt", "reject")}
    review["round"] = 2
    review["reviewed"] = {c["id"]: fingerprint(c) for c in proposal["changes"]}
    review["withdrawn"] = [{"id": c["id"], "reply": c["reply"]} for c in withdrawn]
    review["meta"] = meta
    write_json(folder / "review-2.json", review)
    write_json(folder / "proposal.json", proposal)
    _print_notes(2, review, proposal["changes"])
    disputed = [c["id"] for c in proposal["changes"] if c["review"]["disputed"]]
    _say("")
    if disputed:
        _say(f"Still disputed after round 2: {', '.join(disputed)}. Decide each one yourself and tell the user both "
             "sides and your call; a change you drop is deleted from proposal.json, one you keep stays flagged. "
             "Then run `coach push`.")
    else:
        _say("No change is disputed. Run `coach push`.")
    return 0


# --- push -------------------------------------------------------------------

def push(arg: str | None = None, home: Path | None = None) -> int:
    home = home or coach_home()
    folder = resolve_review(arg, home)
    proposal = read_json(folder / "proposal.json")
    snapshot = read_json(folder / "snapshot.json")
    stats_json = read_json(folder / "stats.json") if (folder / "stats.json").exists() else {}
    if not (folder / "review-2.json").exists():
        raise CoachError("The reviewer has not finished both rounds. Run `coach submit` until it reports the "
                         "second round, then push.")
    problems = validate(proposal, snapshot, stats_json.get("metrics"), allow_reply=True, allow_review=True)
    reviewed = read_json(folder / "review-2.json").get("reviewed", {})
    for change in proposal.get("changes", []):
        if not isinstance(change, dict):
            continue
        label = f"change {change.get('id')}"
        if "review" not in change or change.get("id") not in reviewed:
            problems.append(f"{label}: has no reviewer verdict; every change in a pushed proposal went through round 2")
        elif fingerprint(change) != reviewed[change["id"]]:
            problems.append(f"{label}: was edited after the review; drop it or run the review again")
    if problems:
        return _print_problems(problems)
    outgoing = json.loads(json.dumps(proposal))
    for change in outgoing["changes"]:
        change.pop("reply", None)
    sent = folder / "proposal.sent.json"
    write_json(sent, outgoing)
    phone = device.require_phone()
    problem = device.copy_to(phone, sent, device.INBOX_PATH)
    if problem:
        raise CoachError("Could not copy the proposal to the phone: " + problem)
    write_json(folder / "pushed.json", {"proposalID": outgoing["id"], "pushedAt": format_time(datetime.now(timezone.utc)),
                                        "device": phone})
    _say(f"Pushed {len(outgoing['changes'])} change(s) to the phone's inbox. Open GymTrack to review them.")
    return 0


# --- status -----------------------------------------------------------------

def status(home: Path | None = None) -> int:
    home = home or coach_home()
    phone = device.find_phone()
    _say(f"Phone: {'reachable' if phone else 'not reachable'}")
    folders = review_folders(home)
    last = folders[-1] if folders else None
    _say(f"Last review: {last if last else 'none yet'}")
    pushed = next((f for f in reversed(folders) if (f / "pushed.json").exists()), None)
    if pushed is None:
        _say("Proposal on the phone: none pushed from this Mac.")
        return 0
    proposal_id = read_json(pushed / "pushed.json")["proposalID"]
    decisions, source = None, "as of the last pull"
    if phone:
        with tempfile.TemporaryDirectory(prefix="coach-status-") as scratch:
            target = Path(scratch) / "decisions.json"
            if device.copy_from(phone, device.DECISIONS_PATH, target) is None:
                decisions, source = read_json(target), "from the phone now"
            else:
                decisions, source = {"decisions": []}, "from the phone now (no decisions file yet)"
    elif (last / "decisions.json").exists():
        decisions = read_json(last / "decisions.json")
    entry = next((d for d in (decisions or {}).get("decisions", []) if str(d.get("proposalID", "")).lower()
                  == str(proposal_id).lower()), None)
    _say(f"Proposal {proposal_id} (pushed in {pushed.name}), {source}: {_describe_decision(entry)}")
    return 0


def _describe_decision(entry: dict | None) -> str:
    if entry is None:
        return "no decision yet (still in the inbox, or opened and not decided)."
    if not entry.get("decidedAt"):
        return "received, not decided yet."
    counts = {}
    for change in entry.get("changes", []):
        counts[change.get("decision")] = counts.get(change.get("decision"), 0) + 1
    tally = ", ".join(f"{n} {name}" for name, n in sorted(counts.items()))
    state = "reverted later" if entry.get("revertedAt") else ("applied" if entry.get("appliedAt") else "nothing applied")
    return f"decided ({tally}); {state}."
