"""Proposal validation, exactly per the coach-loop contract.

The phone re-checks everything against its live plan; this is the same check
run earlier, against the export the review was made from, so a bad proposal is
caught at the Mac while the coach can still fix it.

`validate` returns every problem it finds rather than the first, because the
coach fixes a proposal in one pass or not at all.
"""
from __future__ import annotations

from .stats import active_plan, catalog_index, is_timed
from .util import is_uuid, same_id, parse_time

KINDS = ("setSets", "setRepRange", "setRest", "substitute", "addSlot", "removeSlot")
LEVERS = ("effort", "volume", "priority", "exerciseChoice", "pain", "repRange", "rest")
VERDICTS = ("agree", "doubt", "reject")
STANCES = ("revised", "defended", "withdrawn")
MAX_CHANGES = 3
MAX_REASON = 240

_SPECS = {
    "setSets": {"expect": ("targetSets",), "to": ("targetSets",)},
    "setRepRange": {"expect": ("targetRepsLow", "targetRepsHigh"), "to": ("targetRepsLow", "targetRepsHigh")},
    "setRest": {"expect": ("restSeconds",), "to": ("restSeconds",)},
    "substitute": {"expect": ("catalogID",), "to": ("catalogID", "name")},
    "addSlot": {"expect": (), "to": ("catalogID", "name", "targetSets", "targetRepsLow", "targetRepsHigh",
                                     "restSeconds"), "optional": ("afterItemID",)},
    "removeSlot": {"expect": ("catalogID",), "to": ()},
}
_LOAD_KEYS = ("targetWeightKg", "weightKg", "weight", "load")


def _is_int(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _nulls(value, path="proposal"):
    if value is None:
        yield path
    elif isinstance(value, dict):
        for key, child in value.items():
            yield from _nulls(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _nulls(child, f"{path}[{index}]")


def _find_item(plan: dict, item_id):
    for day in plan.get("days", []):
        for item in day.get("items", []):
            if same_id(item.get("id"), item_id):
                return day, item
    return None, None


def _find_day(plan: dict, day_id):
    return next((d for d in plan.get("days", []) if same_id(d.get("id"), day_id)), None)


def _current(item: dict, key: str, default_rest):
    if key in ("targetRepsLow", "targetRepsHigh"):
        return item.get(key) or 0
    if key == "restSeconds":
        return item.get("restSeconds", default_rest)
    return item.get(key)


def validate(proposal, snapshot: dict, metrics: dict | None = None,
             allow_reply: bool = False, allow_review: bool = False) -> list[str]:
    """Every problem with `proposal` against `snapshot`, or an empty list.

    `metrics` is stats.json's flat metric map; when given, each evidence pair
    must name a key in it and carry its value.
    """
    problems: list[str] = []
    if not isinstance(proposal, dict):
        return ["the proposal is not a JSON object"]
    problems += [f"{path} is null; omit keys that have no value" for path in _nulls(proposal)]

    if proposal.get("format") != "gymtrack-coach-proposal":
        problems.append('format must be "gymtrack-coach-proposal"')
    if proposal.get("version") != 1 or isinstance(proposal.get("version"), bool):
        problems.append("version must be 1")
    if not is_uuid(proposal.get("id")):
        problems.append("id must be a UUID string")
    try:
        parse_time(proposal["createdAt"])
    except (KeyError, ValueError, TypeError, AttributeError):
        problems.append("createdAt must be an ISO 8601 timestamp such as 2026-10-03T18:20:00Z")
    if not (isinstance(proposal.get("summary"), str) and proposal["summary"].strip()):
        problems.append("summary must be a non-empty string")
    advice = proposal.get("advice")
    if advice is not None and not (isinstance(advice, list) and all(isinstance(a, str) and a.strip() for a in advice)):
        problems.append("advice must be a list of non-empty strings")

    plan = active_plan(snapshot)
    if plan is None:
        return problems + ["the export has no active plan"]
    if not plan.get("id"):
        return problems + ["the export carries no plan ids; export again from a build that writes them"]
    if not same_id(proposal.get("planID"), plan["id"]):
        problems.append(f"planID must be the active plan's id ({plan['id']})")

    changes = proposal.get("changes")
    if not isinstance(changes, list):
        return problems + ["changes must be a list"]
    if len(changes) > MAX_CHANGES:
        problems.append(f"at most {MAX_CHANGES} changes, found {len(changes)}")
    if not changes and not advice:
        problems.append("no changes and no advice: if the plan should stay, do not submit a proposal")

    catalog = catalog_index(snapshot)
    default_rest = (snapshot.get("settings") or {}).get("defaultRestSeconds")
    seen_ids: set = set()
    seen_items: set = set()
    removed_per_day: dict[str, int] = {}
    for position, change in enumerate(changes):
        label = f"change {change.get('id', position)}" if isinstance(change, dict) else f"change #{position + 1}"
        if not isinstance(change, dict):
            problems.append(f"{label} is not an object")
            continue
        problems += _check_change(label, change, plan, catalog, default_rest, metrics,
                                  seen_ids, seen_items, removed_per_day, allow_reply, allow_review)
    for day_id, removed in removed_per_day.items():
        day = _find_day(plan, day_id)
        if day and len(day.get("items", [])) - removed < 1:
            problems.append(f"removing {removed} slot(s) would leave day {day['name']} with no item")
    return problems


def _check_change(label, change, plan, catalog, default_rest, metrics, seen_ids, seen_items,
                  removed_per_day, allow_reply, allow_review) -> list[str]:
    problems: list[str] = []
    cid = change.get("id")
    if not (isinstance(cid, str) and cid.strip()):
        problems.append(f"{label}: id must be a non-empty string")
    elif cid in seen_ids:
        problems.append(f"{label}: duplicate change id")
    seen_ids.add(cid)

    kind = change.get("kind")
    if kind not in KINDS:
        problems.append(f"{label}: kind must be one of {', '.join(KINDS)}")
        return problems
    spec = _SPECS[kind]

    reason = change.get("reason")
    if not (isinstance(reason, str) and reason.strip()):
        problems.append(f"{label}: reason must be a short plain sentence")
    elif len(reason) > MAX_REASON:
        problems.append(f"{label}: reason is {len(reason)} characters; it is shown on the phone, keep it under {MAX_REASON}")
    if change.get("lever") not in LEVERS:
        problems.append(f"{label}: lever must be one of {', '.join(LEVERS)}")
    evidence = change.get("evidence")
    if not (isinstance(evidence, list) and evidence):
        problems.append(f"{label}: evidence must list at least one {{metric, value}} pair")
    else:
        for pair in evidence:
            problems += _check_evidence(label, pair, metrics)

    day = _find_day(plan, change.get("dayID"))
    if not is_uuid(change.get("dayID")) or day is None:
        problems.append(f"{label}: dayID is not a day of the active plan")
    item = None
    if kind == "addSlot":
        if "itemID" in change:
            problems.append(f"{label}: addSlot takes dayID and to.afterItemID, not itemID")
    else:
        found_day, item = _find_item(plan, change.get("itemID"))
        if item is None or (day is not None and found_day is not day):
            problems.append(f"{label}: itemID is not an item of that day in the active plan")
            item = None
        else:
            key = str(change["itemID"]).lower()
            if key in seen_items:
                problems.append(f"{label}: more than one change for itemID {change['itemID']}")
            seen_items.add(key)

    problems += _check_values(label, change, spec)
    if problems and not (isinstance(change.get("expect"), dict) and isinstance(change.get("to"), dict)):
        return problems
    expect, to = change.get("expect", {}), change.get("to", {})

    if item is not None:
        for key in spec["expect"]:
            have = _current(item, key, default_rest)
            if expect.get(key) != have:
                problems.append(f"{label}: stale, expect.{key} is {expect.get(key)!r} but the plan has {have!r}")
    if kind == "setSets" and _is_int(to.get("targetSets")) and _is_int(expect.get("targetSets")):
        if abs(to["targetSets"] - expect["targetSets"]) != 1:
            problems.append(f"{label}: setSets changes by exactly one set")
        if not 1 <= to["targetSets"] <= 10:
            problems.append(f"{label}: the result must be 1 to 10 sets")
    if kind == "setRepRange":
        if item is not None and is_timed(item, catalog):
            problems.append(f"{label}: a timed slot has no rep range")
        problems += _check_rep_range(label, to)
        if to == expect:
            problems.append(f"{label}: the rep range does not change")
    if kind == "setRest":
        if _is_int(to.get("restSeconds")) and not 30 <= to["restSeconds"] <= 600:
            problems.append(f"{label}: restSeconds must be 30 to 600")
        if to == expect:
            problems.append(f"{label}: the rest does not change")
    if kind in ("substitute", "addSlot"):
        problems += _check_exercise(label, to, catalog)
    if kind == "substitute":
        if to.get("catalogID") == expect.get("catalogID"):
            problems.append(f"{label}: the substitute is the same exercise")
        if item is not None and is_timed(item, catalog):
            problems.append(f"{label}: the slot is timed, so there is no rep range to carry over")
    if kind == "addSlot":
        if day is not None and day.get("isRest"):
            problems.append(f"{label}: cannot add a slot to a rest day")
        if _is_int(to.get("targetSets")) and not 1 <= to["targetSets"] <= 10:
            problems.append(f"{label}: targetSets must be 1 to 10")
        problems += _check_rep_range(label, to)
        if _is_int(to.get("restSeconds")) and not 30 <= to["restSeconds"] <= 600:
            problems.append(f"{label}: restSeconds must be 30 to 600")
        after = to.get("afterItemID")
        if after is not None and (day is None or not any(same_id(i.get("id"), after) for i in day.get("items", []))):
            problems.append(f"{label}: afterItemID is not an item of that day")
    if kind == "removeSlot" and day is not None and item is not None:
        removed_per_day[str(change["dayID"]).lower()] = removed_per_day.get(str(change["dayID"]).lower(), 0) + 1

    review = change.get("review")
    if review is not None:
        if not allow_review:
            problems.append(f"{label}: review is written by `coach submit`, never by the coach")
        else:
            problems += _check_review(label, review)
    reply = change.get("reply")
    if reply is not None:
        if not allow_reply:
            problems.append(f"{label}: reply belongs to the second round only")
        else:
            problems += _check_reply(label, reply)
    return problems


def _check_values(label, change, spec) -> list[str]:
    problems = []
    for field, wanted in (("expect", spec["expect"]), ("to", spec["to"])):
        value = change.get(field)
        if not isinstance(value, dict):
            problems.append(f"{label}: {field} must be an object")
            continue
        allowed = set(wanted) | set(spec.get("optional", ())) if field == "to" else set(wanted)
        for key in wanted:
            if key not in value:
                problems.append(f"{label}: {field}.{key} is missing")
        for key in value:
            if key not in allowed:
                if key in _LOAD_KEYS:
                    problems.append(f"{label}: {field}.{key} sets a load; loads belong to the phone")
                else:
                    problems.append(f"{label}: {field}.{key} is not part of a {change.get('kind')} change")
        for key in wanted:
            if key in value:
                if key in ("catalogID", "name"):
                    if not (isinstance(value[key], str) and value[key]):
                        problems.append(f"{label}: {field}.{key} must be a non-empty string")
                elif not _is_int(value[key]):
                    problems.append(f"{label}: {field}.{key} must be a whole number")
    return problems


def _check_rep_range(label, to) -> list[str]:
    low, high = to.get("targetRepsLow"), to.get("targetRepsHigh")
    if _is_int(low) and _is_int(high) and not 1 <= low <= high <= 30:
        return [f"{label}: the rep range must satisfy 1 <= low <= high <= 30"]
    return []


def _check_exercise(label, to, catalog) -> list[str]:
    entry = catalog.get(to.get("catalogID"))
    if entry is None:
        return [f"{label}: to.catalogID {to.get('catalogID')!r} is not in the exported catalog"]
    problems = []
    if entry.get("tracking") == "duration":
        problems.append(f"{label}: {entry['name']} is timed; timed exercises are not allowed here")
    if to.get("name") != entry["name"]:
        problems.append(f"{label}: to.name must be the catalog name {entry['name']!r}")
    return problems


def _check_evidence(label, pair, metrics) -> list[str]:
    if not (isinstance(pair, dict) and isinstance(pair.get("metric"), str) and "value" in pair):
        return [f"{label}: each evidence entry needs a metric and a value"]
    value = pair["value"]
    if isinstance(value, (dict, list)):
        return [f"{label}: evidence value for {pair['metric']} must be a number, string or boolean"]
    if metrics is None:
        return []
    if pair["metric"] not in metrics:
        return [f"{label}: evidence metric {pair['metric']!r} is not a key in stats.json"]
    actual = metrics[pair["metric"]]
    if isinstance(actual, bool) or isinstance(value, bool) or isinstance(actual, str) or isinstance(value, str):
        same = actual == value
    else:
        same = abs(actual - value) <= max(0.051, abs(actual) * 0.01)
    if not same:
        return [f"{label}: evidence {pair['metric']} says {value!r} but stats.json has {actual!r}"]
    return []


def _check_review(label, review) -> list[str]:
    if not isinstance(review, dict):
        return [f"{label}: review must be an object"]
    problems = []
    if review.get("verdict") not in VERDICTS:
        problems.append(f"{label}: review.verdict must be agree, doubt or reject")
    score = review.get("score")
    if not (_is_int(score) and 1 <= score <= 5):
        problems.append(f"{label}: review.score must be 1 to 5")
    if not isinstance(review.get("note"), str):
        problems.append(f"{label}: review.note must be a string")
    if not isinstance(review.get("disputed"), bool):
        problems.append(f"{label}: review.disputed must be true or false")
    return problems


def _check_reply(label, reply) -> list[str]:
    if not isinstance(reply, dict):
        return [f"{label}: reply must be an object with stance and text"]
    problems = []
    if reply.get("stance") not in STANCES:
        problems.append(f"{label}: reply.stance must be revised, defended or withdrawn")
    if not (isinstance(reply.get("text"), str) and reply["text"].strip()):
        problems.append(f"{label}: reply.text must say why")
    return problems
