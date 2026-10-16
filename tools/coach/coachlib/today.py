"""One training day, read the way a coach reads it right after the workout.

`coach today` is the daily counterpart of `coach stats`: no plan edits and no
reviewer, only what the day's sessions did against their own history and
against what the plan day asked for. Every number comes from the export or
from a definition in stats.py, so the daily check and the periodic review
never disagree about what "beyond noise" or "a working set" means.
"""
from __future__ import annotations

import statistics
from collections import defaultdict
from datetime import date, datetime, time, timedelta

from . import stats as st
from .util import CoachError, is_uuid, parse_time

NOTE_FORMAT = "gymtrack-coach-day"
NOTE_VERSION = 1
# The note is read on a phone screen, so each part is capped where the skill
# caps it: one verdict, up to three things that went well, two to watch.
NOTE_LISTS = {"wentWell": 3, "watch": 2, "nextTime": 3}
NOTE_LINE_MAX = 400

PER_SESSION_CEILING = 11  # fractional sets per muscle; the second lever in policy.md (Remmert 2025)


def _kg(value) -> str:
    return f"{round(float(value or 0), 2):g}"


def _row_text(s: dict) -> str:
    """One logged row in the same words as the "last time" rows, plus what only
    a full session shows: warm-ups, drop or cluster rows and load offers."""
    text = st._set_text(s, s.get("tracking") or "")
    if s.get("isWarmup"):
        return "warm-up " + text
    if s.get("continues"):
        text = f"+{s['continues']} {text}"
    nudge = s.get("loadNudge")
    if isinstance(nudge, dict) and nudge.get("outcome"):
        text += f" (offered {_kg(nudge.get('toKg'))} kg, {nudge['outcome']})"
    return text


def _efforts(rows: list[dict]) -> list[list[dict]]:
    """Completed rows grouped into efforts: a continuation row belongs to the
    row before it, so a drop set's rest is measured from its last row."""
    groups: list[list[dict]] = []
    for s in rows:
        if s.get("continues") and groups:
            groups[-1].append(s)
        else:
            groups.append([s])
    return groups


def _rests(rows: list[dict]) -> dict:
    """Rest between consecutive working efforts of one exercise. Only an
    announced or detected start splits a gap into rest and set; without one
    the gap holds both, so it is reported as a gap and never as rest."""
    working = [g for g in _efforts(rows) if not g[0].get("isWarmup")]
    rest, gap, kinds = [], [], set()
    for before, after in zip(working, working[1:]):
        ended = before[-1].get("completedAt")
        if not ended:
            continue
        ended = parse_time(ended)
        first = after[0]
        if first.get("startedAt"):
            rest.append((parse_time(first["startedAt"]) - ended).total_seconds())
            kinds.add("announced")
        elif first.get("detectedStartedAt"):
            rest.append((parse_time(first["detectedStartedAt"]) - ended).total_seconds())
            kinds.add("detected")
        elif first.get("completedAt"):
            gap.append((parse_time(first["completedAt"]) - ended).total_seconds())
    out = {}
    if rest:
        out["restMedianSeconds"] = round(statistics.median(rest))
        out["restBasis"] = "+".join(sorted(kinds))
        out["restCount"] = len(rest)
    elif gap:
        out["gapMedianSeconds"] = round(statistics.median(gap))
        out["gapCount"] = len(gap)
    return out


def _rep_targets(sets: list[dict]) -> dict | None:
    aimed = [s for s in sets if s.get("targetRepsLow") and s.get("reps") is not None]
    if not aimed:
        return None
    below = sum(1 for s in aimed if s["reps"] < s["targetRepsLow"])
    top = sum(1 for s in aimed if s.get("targetRepsHigh") and s["reps"] >= s["targetRepsHigh"])
    return {"aimed": len(aimed), "below": below, "atTop": top, "inRange": len(aimed) - below - top}


def _history(cid: str, session: dict, exposures: dict, tz) -> dict:
    """Today's exposure against the earlier ones in the same comparable series."""
    mine = exposures.get(cid, [])
    index = next((i for i, e in enumerate(mine) if e["sessionID"] == session["id"]), None)
    if index is None:
        return {}
    today, before = mine[index], mine[:index]
    out = {"kind": today["kind"], "unit": today["unit"], "value": today["value"]}
    if today.get("load") is not None:
        out["loadKg"] = today["load"]
    if before:
        last = before[-1]
        out["lastTime"] = {"date": st.training_day(parse_time(last["date"]), tz).isoformat(),
                           "detail": last["detail"]}
    if not today["comparable"]:
        out["comparable"] = False
        return out
    series = [e for e in before if e["comparable"] and e["seriesKey"] == today["seriesKey"]]
    values = [e["value"] for e in series] + [today["value"]]
    out["exposures"] = len(values)
    if not series:
        out["firstInSeries"] = True
        return out
    previous = series[-1]
    out["previous"] = previous["value"]
    out["previousDate"] = st.training_day(parse_time(previous["date"]), tz).isoformat()
    out["delta"] = round(today["value"] - previous["value"], 2)
    out["bestBefore"] = max(values[:-1])
    out["newBest"] = today["value"] > out["bestBefore"]
    noise = st.typical_error(values)
    if noise is not None:
        out["noise"] = round(noise, 2)
        out["beyondNoise"] = abs(out["delta"]) > noise
    earlier = [x for e in series[-4:] for x in e["effortsAll"]]
    if earlier:
        out["recentEffortMean"] = round(sum(earlier) / len(earlier), 2)
    return out


def _slot_text(slots: list[dict]) -> str:
    sets = sum(slot["targetSets"] for slot in slots)
    ranges = []
    for slot in slots:
        if slot.get("targetSeconds") is not None:
            ranges.append(f"{slot['targetSeconds']}s")
        elif slot.get("targetRepsLow"):
            high = slot.get("targetRepsHigh")
            ranges.append(f"{slot['targetRepsLow']}-{high}" if high and high != slot["targetRepsLow"]
                          else f"{slot['targetRepsLow']}")
    text = f"{sets} sets"
    if ranges:
        text += " of " + " / ".join(dict.fromkeys(ranges))
    rests = sorted({slot["restSeconds"] for slot in slots if slot.get("restSeconds")})
    if rests:
        text += ", rest " + "/".join(f"{r}s" for r in rests)
    return text


def describe_session(session: dict, exposures: dict, catalog: dict, plan_days: dict, tz) -> dict:
    started = parse_time(session["startedAt"])
    day = plan_days.get(str(session.get("planDayID") or "").lower())
    out = {"id": session["id"], "title": session.get("title", ""), "planName": session.get("planName", "")}
    if day:
        out["planDay"] = day.get("name")
    if session.get("loggedAfterwards"):
        out["loggedAfterwards"] = True
    else:
        out["start"] = started.astimezone(tz).strftime("%H:%M")
        if session.get("endedAt"):
            ended = parse_time(session["endedAt"])
            out["end"] = ended.astimezone(tz).strftime("%H:%M")
            out["minutes"] = round((ended - started).total_seconds() / 60)
    for key in ("averageHeartRate", "maxHeartRate", "heartRateSource", "activeEnergyKcal", "energySource",
                "wasWatchDriven"):
        if session.get(key) is not None:
            out[key] = round(session[key]) if isinstance(session[key], float) else session[key]
    if session.get("notes") or session.get("noteTags"):
        out["note"] = {"text": session.get("notes") or "", "tags": session.get("noteTags") or []}

    rows = defaultdict(list)
    for s in sorted(session.get("sets", []), key=lambda s: (s.get("exerciseOrder", 0), s.get("setIndex", 0))):
        if s.get("isCompleted"):
            rows[st.canonical_id(catalog, s["catalogID"])].append(s)
    working = defaultdict(list)
    for s in st.working_sets(session):
        working[st.canonical_id(catalog, s["catalogID"])].append(s)
    notes = defaultdict(list)
    for note in session.get("exerciseNotes") or []:
        notes[st.canonical_id(catalog, note["catalogID"])].append(note)

    slots = st.planned_slots(session, plan_days)
    by_slot = defaultdict(list)
    for slot in slots or []:
        by_slot[st.canonical_id(catalog, slot["catalogID"])].append(slot)

    exercises = []
    for cid, own_rows in rows.items():
        sets = working[cid]
        entry = {"catalogID": cid,
                 "name": own_rows[0].get("exerciseName") or st.catalog_entry(catalog, cid).get("name") or cid,
                 "rows": [_row_text(s) for s in own_rows], "workingSets": len(sets)}
        if by_slot.get(cid):
            own = by_slot[cid]
            entry["planned"] = _slot_text(own)
            entry["plannedSets"] = sum(slot["targetSets"] for slot in own)
            entry["slotSetsDone"] = st.completed_slot_sets(own, sets)
        elif slots is not None:
            entry["notPlanned"] = True
        targets = _rep_targets(sets)
        if targets:
            entry["repTargets"] = targets
        answered = [st.effort_ordinal(s) for s in sets if st.effort_ordinal(s) is not None]
        entry["effortAnswered"] = len(answered)
        if answered:
            entry["effortMean"] = round(sum(answered) / len(answered), 2)
        if not session.get("loggedAfterwards"):
            entry.update(_rests(own_rows))
        history = _history(cid, session, exposures, tz)
        if history:
            entry["history"] = history
        if notes.get(cid):
            entry["notes"] = [{"text": n.get("text", ""), "tags": n.get("tags", [])} for n in notes[cid]]
        exercises.append(entry)
    out["exercises"] = exercises

    if slots is not None:
        worked = set(working)
        out["plan"] = {
            "slots": len(slots),
            "skipped": [slot["name"] for slot in slots if st.canonical_id(catalog, slot["catalogID"]) not in worked],
            "short": [f"{e['name']} {e['slotSetsDone']}/{e['plannedSets']}" for e in exercises
                      if e.get("plannedSets") and 0 < e["slotSetsDone"] < e["plannedSets"]],
            "notPlanned": [e["name"] for e in exercises if e.get("notPlanned") and e["workingSets"]],
        }
    muscles = defaultdict(float)
    for s in st.working_sets(session):
        for muscle, weight in st.fractional_sets(st.catalog_entry(catalog, s["catalogID"]).get("muscles", [])).items():
            muscles[muscle] += weight
    out["muscles"] = dict(sorted(muscles.items(), key=lambda kv: -kv[1]))
    return out


def compute_day(snapshot: dict, day: date | None = None, now: datetime | None = None) -> dict:
    """The training day `day` (default: the latest one with a finished
    workout). Later sessions are cut from the export first, so a past day
    reads exactly as it would have that evening."""
    tz = st._timezone(snapshot)
    catalog = st.catalog_index(snapshot)
    finished = st.finished_sessions(snapshot)
    if not finished:
        raise CoachError("this export has no finished workout yet")
    by_day = defaultdict(list)
    for session in finished:
        by_day[st.training_day(parse_time(session["startedAt"]), tz)].append(session)
    target = day or max(by_day)
    if target not in by_day:
        last = max(d for d in by_day)
        raise CoachError(f"no finished workout on {target}; the latest is on {last}")

    upto = dict(snapshot, sessions=[s for s in snapshot.get("sessions", [])
                                    if st.training_day(parse_time(s["startedAt"]), tz) <= target])
    exposures = st.build_exposures(upto, catalog)
    plan_days = {str(d["id"]).lower(): d for plan in snapshot.get("plans", []) for d in plan.get("days", [])}

    now = now or datetime.now(tz)
    out = {"day": target.isoformat(), "weekday": target.strftime("%A"),
           "isToday": target == st.training_day(now, tz), "timeZone": snapshot.get("timeZone"),
           "exportedAt": snapshot.get("exportedAt")}
    earlier = [d for d in by_day if d < target]
    if earlier:
        out["previousDay"] = max(earlier).isoformat()
        out["daysSincePrevious"] = (target - max(earlier)).days
    if any(not s.get("endedAt") and not s.get("loggedAfterwards")
           and st.training_day(parse_time(s["startedAt"]), tz) == target for s in snapshot.get("sessions", [])):
        out["unfinishedSession"] = True

    sessions = [describe_session(s, exposures, catalog, plan_days, tz) for s in by_day[target]]
    for described, session in zip(sessions, by_day[target]):
        day_id = str(session.get("planDayID") or "").lower()
        if day_id:
            same = [d for d, group in by_day.items() if d < target
                    and any(str(s.get("planDayID") or "").lower() == day_id for s in group)]
            if same:
                described["planDayLastTrained"] = max(same).isoformat()
    out["sessions"] = sessions

    monday = target - timedelta(days=target.weekday())
    out["week"] = {"sessionsSoFar": sum(len(group) for d, group in by_day.items() if monday <= d <= target)}
    plan = st.active_plan(snapshot)
    due = [d for d in (plan or {}).get("days", []) if not d.get("isRest") and d.get("items")]
    if due:
        out["week"]["planTrainingDays"] = len(due)
    moment = datetime.combine(target, time(12), tzinfo=tz)
    volume = st.muscle_volume(upto, catalog, moment, tz)["muscles"]
    day_muscles = defaultdict(float)
    for described in sessions:
        for muscle, sets in described["muscles"].items():
            day_muscles[muscle] += sets
    out["muscles"] = [
        {"muscle": m, "today": st._round(v), "weekSoFar": volume.get(m, {}).get("thisWeekFractionalSets"),
         **({"typicalWeek": volume[m]["weeklyFractionalSets"]}
            if volume.get(m, {}).get("weeklyFractionalSets") is not None else {})}
        for m, v in sorted(day_muscles.items(), key=lambda kv: -kv[1])]

    weights = [r for r in snapshot.get("bodyMetrics") or []
               if st.training_day(parse_time(r["date"]), tz) == target]
    if weights:
        out["bodyWeightKg"] = round(weights[-1]["weightKg"], 1)
    return out


# --- the note the phone shows -------------------------------------------------

def validate_note(note: object, day: str) -> list[str]:
    """Problems with a day's note.json, empty when the phone can show it. Keys
    are checked by name so a typo is caught here rather than silently dropped
    by the phone's decoder."""
    if not isinstance(note, dict):
        return ["note.json is not a JSON object"]
    problems = []
    allowed = {"format", "version", "id", "createdAt", "day", "verdict", *NOTE_LISTS}
    for key in sorted(set(note) - allowed):
        problems.append(f"unknown key {key!r}")
    for key, value in note.items():
        if value is None:
            problems.append(f"{key} is null; leave the key out instead")
    if note.get("format") != NOTE_FORMAT:
        problems.append(f"format must be {NOTE_FORMAT!r}")
    if note.get("version") != NOTE_VERSION:
        problems.append(f"version must be {NOTE_VERSION}")
    if not is_uuid(note.get("id")):
        problems.append("id must be a UUID (uuidgen)")
    try:
        parse_time(str(note.get("createdAt", "")))
    except ValueError:
        problems.append("createdAt must be an ISO 8601 time")
    if note.get("day") != day:
        problems.append(f"day must be {day!r}, the training day this folder is for")
    verdict = note.get("verdict")
    if not isinstance(verdict, str) or not verdict.strip():
        problems.append("verdict must be a sentence")
    elif len(verdict) > NOTE_LINE_MAX:
        problems.append(f"verdict is over {NOTE_LINE_MAX} characters")
    for key, most in NOTE_LISTS.items():
        if key not in note or note[key] is None:
            continue
        lines = note[key]
        if not isinstance(lines, list) or not all(isinstance(line, str) and line.strip() for line in lines):
            problems.append(f"{key} must be a list of non-empty strings")
        elif not lines:
            problems.append(f"{key} is empty; leave the key out instead")
        elif len(lines) > most:
            problems.append(f"{key} has {len(lines)} lines; at most {most}")
        elif any(len(line) > NOTE_LINE_MAX for line in lines):
            problems.append(f"a line in {key} is over {NOTE_LINE_MAX} characters")
    return problems


# --- markdown -----------------------------------------------------------------

def _seconds(value: int) -> str:
    minutes, seconds = divmod(int(value), 60)
    return f"{minutes}m{seconds:02d}" if minutes else f"{seconds}s"


def _value(history: dict, value) -> str:
    if history["kind"] == "e1rm":
        return f"{value:g} kg e1RM"
    if history["kind"] == "reps":
        return f"{value:g} reps at {history.get('loadKg', 0):g} kg"
    return f"{value:g}s"


def _history_line(h: dict) -> str:
    if h.get("comparable") is False:
        return "Comparable: no, tagged as a substitution today."
    if h.get("firstInSeries"):
        return f"Comparable: first exposure of this series, {_value(h, h['value'])}."
    text = f"Comparable: {_value(h, h['value'])} vs {h['previous']:g} on {h['previousDate'][5:]}"
    text += f" ({h['delta']:+g}); best before {h['bestBefore']:g}"
    if h.get("newBest"):
        text += ", a new best"
    if "noise" in h:
        verdict = "beyond" if h["beyondNoise"] else "within"
        text += f". Noise {h['noise']:g} over {h['exposures']} exposures: {verdict} noise."
    else:
        text += f". Noise unknown ({h['exposures']} exposures, needs {st.MIN_EXPOSURES_FOR_NOISE})."
    return text


def _exercise_lines(e: dict) -> list[str]:
    head = f"### {e['name']}"
    if e.get("planned"):
        head += f" (planned {e['planned']})"
    elif e.get("notPlanned"):
        head += " (not planned)"
    lines = [head, "Today: " + ", ".join(e["rows"])]
    h = e.get("history") or {}
    if h.get("lastTime"):
        lines.append(f"Last time {h['lastTime']['date'][5:]}: " + ", ".join(h["lastTime"]["detail"]))
    if h:
        lines.append(_history_line(h))
    facts = []
    t = e.get("repTargets")
    if t:
        facts.append(f"reps vs target: {t['inRange']} in range, {t['atTop']} at or above the top, {t['below']} below")
    if e["workingSets"]:
        effort = f"effort answered {e['effortAnswered']}/{e['workingSets']}"
        if "effortMean" in e:
            effort += f", mean {e['effortMean']:g}"
            if "recentEffortMean" in h:
                effort += f" (previous four exposures {h['recentEffortMean']:g})"
        facts.append(effort)
    if "restMedianSeconds" in e:
        facts.append(f"rest median {_seconds(e['restMedianSeconds'])} ({e['restBasis']} starts)")
    elif "gapMedianSeconds" in e:
        facts.append(f"set-to-set gap median {_seconds(e['gapMedianSeconds'])} (rest and set together; no starts)")
    if facts:
        lines.append("; ".join(facts).capitalize() + ".")
    for note in e.get("notes", []):
        tags = f" [{', '.join(note['tags'])}]" if note["tags"] else ""
        lines.append(f'Note: "{note["text"]}"{tags}')
    return lines


def render_markdown(result: dict) -> str:
    when = "today" if result["isToday"] else "not today"
    lines = [f"# Training day {result['day']} ({result['weekday']}, {when})", ""]
    context = []
    if "daysSincePrevious" in result:
        context.append(f"Previous workout {result['daysSincePrevious']} day(s) earlier, on {result['previousDay']}.")
    else:
        context.append("First workout in the export.")
    week = result["week"]
    text = f"Workout {week['sessionsSoFar']} of this week (Monday first)"
    if "planTrainingDays" in week:
        text += f"; the active plan has {week['planTrainingDays']} training days"
    context.append(text + ".")
    if "bodyWeightKg" in result:
        context.append(f"Body weight logged today: {result['bodyWeightKg']:g} kg.")
    if result.get("unfinishedSession"):
        context.append("A workout on this day is still unfinished; the snapshot predates its end.")
    lines += [" ".join(context), ""]
    lines.append("Effort mean: 1 easy, 2 solid, 3 hard, 4 allOut. Noise is the lifter's own session-to-session "
                 "wobble; a change within it is not a change.")
    for s in result["sessions"]:
        title = s["title"] or "Workout"
        if s.get("planDay"):
            title += f" (plan {s['planName'].strip()}, day {s['planDay']})"
        lines += ["", f"## {title}"]
        facts = []
        if s.get("loggedAfterwards"):
            facts.append("Logged afterwards: no times or heart rate")
        elif "minutes" in s:
            facts.append(f"{s['start']} to {s['end']}, {s['minutes']} min")
        if s.get("wasWatchDriven"):
            facts.append("driven from the watch")
        if "averageHeartRate" in s:
            facts.append(f"heart rate avg {s['averageHeartRate']}, max {s.get('maxHeartRate')} "
                         f"({s.get('heartRateSource', 'source unknown')})")
        if "activeEnergyKcal" in s:
            facts.append(f"{s['activeEnergyKcal']} kcal ({s.get('energySource', 'source unknown')})")
        if s.get("planDayLastTrained"):
            facts.append(f"this plan day was last trained {s['planDayLastTrained']}")
        if facts:
            lines.append("; ".join(facts) + ".")
        if s.get("note"):
            tags = f" [{', '.join(s['note']['tags'])}]" if s["note"]["tags"] else ""
            lines.append(f'Session note: "{s["note"]["text"]}"{tags}')
        plan = s.get("plan")
        if plan:
            parts = [f"{plan['slots']} slots planned"]
            for key, label in (("skipped", "skipped"), ("short", "short"), ("notPlanned", "not planned")):
                if plan[key]:
                    parts.append(f"{label}: {', '.join(plan[key])}")
            if len(parts) == 1:
                parts.append("every slot trained in full")
            lines.append("Plan: " + "; ".join(parts) + ".")
        else:
            lines.append("Plan: not started from a plan day, so nothing to compare against.")
        for e in s["exercises"]:
            lines += [""] + _exercise_lines(e)
    lines += ["", "## Muscles (fractional working sets)"]
    for m in result["muscles"]:
        text = f"- {m['muscle']}: {m['today']:g} today"
        if m["today"] > PER_SESSION_CEILING:
            text += f" (past the ~{PER_SESSION_CEILING} per-session point where more stops showing a benefit)"
        if m.get("weekSoFar") is not None:
            text += f", {m['weekSoFar']:g} this week so far"
        if m.get("typicalWeek") is not None:
            text += f", typical week {m['typicalWeek']:g}"
        lines.append(text)
    return "\n".join(lines) + "\n"
