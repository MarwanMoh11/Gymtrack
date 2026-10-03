"""The independent reviewer: a separate `claude -p` process for every round.

Independence is the point. The reviewer gets a fresh working directory (so no
repository CLAUDE.md or skill loads), an environment without the markers of
the coach's own session, no tools, no saved session, and a prompt that says only
that "a coach" proposed these changes. It sees data and the proposal stripped
of its reason prose, because a model reading text in its own style tends to
agree with it, and numbers blunt that.
"""
from __future__ import annotations

import glob
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from .stats import active_plan, catalog_index
from .util import CoachError, same_id

PROMPT_FILE = Path(__file__).resolve().parent.parent / "reviewer_prompt.md"
SYSTEM_PROMPT = "You review training plans. Reply only with the JSON object the instructions ask for."
# The reviewer runs twice a review, weekly at most, and its job is catching the
# slip the coach missed; a cheaper pass that misses it costs more than the tokens.
DEFAULT_EFFORT = "max"
DEFAULT_TIMEOUT = 900

# Markers of the coach's own session. Anything else starting CLAUDE_CODE_ is
# also removed unless it carries credentials or provider choice, which the
# child needs to log in.
_KEEP_FRAGMENTS = ("OAUTH", "USE_BEDROCK", "USE_VERTEX", "USE_FOUNDRY", "API_KEY", "CONFIG_DIR", "CA_CERT")
_DROP_EXACT = {"CLAUDECODE", "CLAUDE_PID", "CLAUDE_EFFORT"}


class ReviewerError(CoachError):
    pass


def find_claude_binary() -> str:
    override = os.environ.get("COACH_CLAUDE_BIN")
    if override:
        return override
    on_path = shutil.which("claude")
    if on_path:
        return on_path
    pattern = os.path.expanduser("~/Library/Application Support/Claude/claude-code/*/claude.app/Contents/MacOS/claude")
    found = sorted(glob.glob(pattern), key=lambda p: _version_key(p), reverse=True)
    if found:
        return found[0]
    raise ReviewerError("no claude binary: set COACH_CLAUDE_BIN, put `claude` on PATH, or install Claude Code")


def _version_key(path: str):
    folder = Path(path).parents[3].name
    return tuple(int(part) if part.isdigit() else 0 for part in folder.split("."))


def clean_env(base: dict | None = None) -> dict:
    """The coach's environment minus its session markers, plus switches that
    keep the child from loading memory files or the user's global CLAUDE.md."""
    env = dict(os.environ if base is None else base)
    for name in list(env):
        marked = name in _DROP_EXACT or name.startswith(("CLAUDE_CODE_", "CLAUDE_AGENT_"))
        if marked and not any(fragment in name for fragment in _KEEP_FRAGMENTS):
            del env[name]
    env["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1"
    env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
    env["CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS"] = "1"
    return env


def _help_text(binary: str) -> str:
    try:
        result = subprocess.run([binary, "--help"], capture_output=True, text=True, timeout=60,
                                env=clean_env(), cwd=tempfile.gettempdir())
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ReviewerError(f"could not run `{binary} --help`: {error}")
    return result.stdout + result.stderr


def build_command(binary: str, help_text: str, model: str | None = None, effort: str | None = None) -> list[str]:
    """Flags are picked from the binary's own --help, so a renamed flag fails
    here with a clear message rather than inside the child."""
    for required in ("--print", "--output-format", "--tools"):
        if required not in help_text:
            raise ReviewerError(f"{binary} does not list {required} in --help; cannot run a print-mode reviewer")
    command = [binary, "--print", "--output-format", "json", "--tools", ""]
    optional = [("--no-session-persistence", []), ("--disable-slash-commands", []),
                ("--strict-mcp-config", []), ("--system-prompt", [SYSTEM_PROMPT])]
    for flag, values in optional:
        if flag in help_text:
            command += [flag] + values
    sources = os.environ.get("COACH_REVIEWER_SETTING_SOURCES", "project")
    if "--setting-sources" in help_text and sources != "all":
        command += ["--setting-sources", sources]
    model = model or os.environ.get("COACH_REVIEWER_MODEL")
    if model:
        if "--model" not in help_text:
            raise ReviewerError(f"{binary} has no --model flag")
        command += ["--model", model]
    effort = effort if effort is not None else os.environ.get("COACH_REVIEWER_EFFORT", DEFAULT_EFFORT)
    if effort and effort != "default" and "--effort" in help_text:
        command += ["--effort", effort]
    return command


def run(prompt: str, model: str | None = None) -> tuple[str, dict]:
    """One reviewer call. Returns the reply text and a little metadata."""
    binary = find_claude_binary()
    command = build_command(binary, _help_text(binary), model=model)
    timeout = int(os.environ.get("COACH_REVIEWER_TIMEOUT", DEFAULT_TIMEOUT))
    with tempfile.TemporaryDirectory(prefix="coach-reviewer-") as workdir:
        try:
            result = subprocess.run(command, input=prompt, capture_output=True, text=True,
                                    timeout=timeout, cwd=workdir, env=clean_env())
        except subprocess.TimeoutExpired:
            raise ReviewerError(f"the reviewer did not answer within {timeout} s (COACH_REVIEWER_TIMEOUT)")
        except OSError as error:
            raise ReviewerError(f"could not start the reviewer: {error}")
    if result.returncode != 0:
        raise ReviewerError(f"the reviewer exited with status {result.returncode}: "
                            f"{(result.stderr or result.stdout).strip()[:600]}")
    try:
        envelope = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise ReviewerError(f"the reviewer's output was not JSON: {result.stdout.strip()[:600]}")
    if not isinstance(envelope, dict) or "result" not in envelope:
        raise ReviewerError(f"unexpected reviewer envelope: {result.stdout.strip()[:600]}")
    if envelope.get("is_error"):
        raise ReviewerError(f"the reviewer reported an error: {str(envelope['result'])[:600]}")
    meta = {key: envelope[key] for key in ("duration_ms", "total_cost_usd", "num_turns") if key in envelope}
    meta["command"] = ["<system prompt>" if part == SYSTEM_PROMPT else part for part in command]
    return str(envelope["result"]), meta


# --- the reply --------------------------------------------------------------

def parse_reply(text: str, expected_ids: list[str]) -> dict:
    """The reviewer's JSON, tolerant of a code fence or a sentence around it and
    strict about content: every change reviewed once, verdict and score valid."""
    value = _extract_object(text)
    if value is None:
        raise ReviewerError(f"the reviewer did not return the JSON object asked for: {text.strip()[:600]}")
    changes = value.get("changes")
    if not isinstance(changes, list):
        raise ReviewerError("the reviewer's JSON has no changes list")
    clean, seen = [], set()
    for row in changes:
        if not isinstance(row, dict):
            raise ReviewerError("a reviewer change entry is not an object")
        cid = row.get("id")
        if cid not in expected_ids:
            raise ReviewerError(f"the reviewer judged an unknown change id {cid!r}")
        if cid in seen:
            raise ReviewerError(f"the reviewer judged {cid} twice")
        seen.add(cid)
        verdict, score = row.get("verdict"), row.get("score")
        if verdict not in ("agree", "doubt", "reject"):
            raise ReviewerError(f"reviewer verdict for {cid} is {verdict!r}")
        if isinstance(score, bool) or not isinstance(score, int) or not 1 <= score <= 5:
            raise ReviewerError(f"reviewer score for {cid} is {score!r}, not 1 to 5")
        note = row.get("note")
        if not isinstance(note, str) or not note.strip():
            raise ReviewerError(f"reviewer gave no note for {cid}")
        clean.append({"id": cid, "verdict": verdict, "score": score, "note": note.strip()})
    missing = [cid for cid in expected_ids if cid not in seen]
    if missing:
        raise ReviewerError(f"the reviewer left out {', '.join(missing)}")
    summary = value.get("summary")
    return {"changes": clean, "summary": summary.strip() if isinstance(summary, str) else ""}


def _extract_object(text: str):
    text = text.strip()
    decoder = json.JSONDecoder()
    try:
        value = json.loads(text)
        if isinstance(value, dict):
            return value
    except json.JSONDecodeError:
        pass
    index = text.find("{")
    while index != -1:
        try:
            value, _ = decoder.raw_decode(text[index:])
            if isinstance(value, dict) and "changes" in value:
                return value
        except json.JSONDecodeError:
            pass
        index = text.find("{", index + 1)
    return None


# --- the bundle -------------------------------------------------------------

def _names(plan: dict) -> dict:
    return {str(item["id"]).lower(): (day, item) for day in plan.get("days", []) for item in day.get("items", [])
            if item.get("id")}


def describe_change(change: dict, plan: dict) -> dict:
    """A change as the reviewer sees it: names instead of UUIDs, no `reason`."""
    day = next((d for d in plan.get("days", []) if same_id(d.get("id"), change.get("dayID"))), {})
    out = {"id": change["id"], "kind": change["kind"], "day": day.get("name")}
    if change.get("itemID"):
        _, item = _names(plan).get(str(change["itemID"]).lower(), (None, {}))
        out["slot"] = item.get("name")
    out["expect"] = change.get("expect", {})
    to = dict(change.get("to", {}))
    if to.get("afterItemID"):
        _, after = _names(plan).get(str(to["afterItemID"]).lower(), (None, {}))
        to["afterItemID"] = after.get("name", "?")
        to["after"] = to.pop("afterItemID")
    out["to"] = to
    out["lever"] = change.get("lever")
    out["evidence"] = change.get("evidence", [])
    return out


def touched_exercises(changes: list[dict], plan: dict) -> list[str]:
    ids = []
    for change in changes:
        if change.get("itemID"):
            _, item = _names(plan).get(str(change["itemID"]).lower(), (None, {}))
            if item.get("catalogID"):
                ids.append(item["catalogID"])
        if (change.get("to") or {}).get("catalogID"):
            ids.append(change["to"]["catalogID"])
    return list(dict.fromkeys(ids))


def build_prompt(profile: str, stats_md: str, stats: dict | None, snapshot: dict, proposal: dict,
                 round_number: int, previous_review: dict | None = None) -> str:
    plan = active_plan(snapshot)
    catalog = catalog_index(snapshot)
    changes = proposal["changes"]
    days = []
    for change in changes:
        day = next((d for d in plan["days"] if same_id(d.get("id"), change.get("dayID"))), None)
        if day and day not in days:
            days.append(day)
    day_lines = []
    for day in days:
        day_lines.append(f"{day['name']}:")
        for item in sorted(day.get("items", []), key=lambda i: i.get("order", 0)):
            reps = f"{item.get('targetRepsLow')}-{item.get('targetRepsHigh')} reps" if item.get("targetRepsLow") else "timed"
            rest = item.get("restSeconds", (snapshot.get("settings") or {}).get("defaultRestSeconds"))
            day_lines.append(f"  - {item['name']}: {item['targetSets']} sets, {reps}, rest {rest} s")
    history = []
    for cid in touched_exercises(changes, plan):
        info = ((stats or {}).get("exercises") or {}).get(cid)
        name = catalog.get(cid, {}).get("name", cid)
        if not info or not info.get("recent"):
            history.append(f"{name}: no history in the log.")
            continue
        history.append(f"{name} ({info['exposures']} comparable sessions, newest last):")
        for row in info["recent"]:
            history.append(f"  - {row['date'][:10]}: {row['value']:g} {info['unit']}; " + "; ".join(row["detail"]))
    shown = [describe_change(c, plan) for c in changes]
    prompt = PROMPT_FILE.read_text(encoding="utf-8")
    replacements = {
        "{{PROFILE}}": profile.strip() or "(no profile written)",
        "{{STATS}}": stats_md.strip(),
        "{{DAYS}}": "\n".join(day_lines),
        "{{HISTORY}}": "\n".join(history) or "none",
        "{{CHANGES}}": json.dumps(shown, indent=2, ensure_ascii=False),
        "{{ROUND}}": _round_block(round_number, changes, previous_review),
    }
    for token, text in replacements.items():
        prompt = prompt.replace(token, text)
    return prompt


def _round_block(round_number: int, changes: list[dict], previous: dict | None) -> str:
    if round_number == 1:
        return "This is the first round."
    notes = {row["id"]: row for row in (previous or {}).get("changes", [])}
    lines = ["## Second round", "",
             "This is the same proposal after the coach read your first notes. For each change you will see what "
             "you said and the coach's reply; the change may have been revised, so judge it as it now stands. A "
             "reply that restates a claim without new evidence does not answer an objection; one that corrects a "
             "number or narrows the change does. Give your final verdict on each.", ""]
    for change in changes:
        before = notes.get(change["id"], {})
        reply = change.get("reply", {})
        lines.append(f"Change {change['id']}:")
        lines.append(f"  your first verdict: {before.get('verdict', '?')} ({before.get('score', '?')}/5): "
                     f"{before.get('note', '')}")
        lines.append(f"  the coach's reply ({reply.get('stance', '?')}): {reply.get('text', '')}")
    return "\n".join(lines)
