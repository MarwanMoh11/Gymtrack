"""The coach's numbers, computed from the phone's export.

The definitions live in `.claude/skills/coach-review/policy.md`. They are
implemented here, once, so a review never depends on a model redoing
arithmetic: the coach reads these numbers and is not allowed to redefine them.

Everything is a pure function of the export (plus the optional decisions file,
the previous review's export and the profile), so a fixture reproduces a review
exactly. "Now" is the export's own `exportedAt`, never the wall clock.
"""
from __future__ import annotations

import math
import re
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

from .util import format_time, parse_time, same_id

EPLEY_REP_CAP = 12
MIN_EXPOSURES_FOR_NOISE = 6
PLATEAU_MIN_EXPOSURES = 4
PLATEAU_MIN_DAYS = 21
NOISE_WINDOW = 12
VOLUME_WEEKS = 4
NOTE_DAYS = 90
EFFORT_ORDINAL = {"easy": 1, "solid": 2, "hard": 3, "allOut": 4}
EFFORT_WORD = {1: "easy", 2: "solid", 3: "hard", 4: "allOut"}
RPE_TO_EFFORT = {6.0: "easy", 8.0: "solid", 9.0: "hard", 10.0: "allOut"}

# The app's own folding of library labels into muscles (Muscle.match), so a
# custom exercise that carries only raw labels still counts toward volume.
_RAW_TO_MUSCLE = {
    "chest": ("chest", "upper chest", "lower chest", "inner chest", "pectorals", "serratus"),
    "shoulders": ("shoulders", "front delts", "side delts", "deltoids", "rotator cuff"),
    "rearDelts": ("rear delts", "posterior deltoids"),
    "biceps": ("biceps", "arms"),
    "triceps": ("triceps",),
    "forearms": ("forearms", "grip"),
    "abs": ("core", "abs", "lower abs", "abdominals"),
    "obliques": ("obliques",),
    "lats": ("lats",),
    "upperBack": ("back", "upper back", "mid back", "rhomboids"),
    "traps": ("traps", "lower traps"),
    "lowerBack": ("lower back", "spine", "erector spinae"),
    "glutes": ("glutes", "hips", "abductors"),
    "quads": ("quads", "legs", "hip flexors", "quadriceps"),
    "hamstrings": ("hamstrings", "posterior chain"),
    "calves": ("calves",),
    "adductors": ("adductors", "inner thighs"),
}
_LABEL_TO_MUSCLE = {label: muscle for muscle, labels in _RAW_TO_MUSCLE.items() for label in labels}


def muscle_from_label(label: str) -> str | None:
    return _LABEL_TO_MUSCLE.get(label.strip().lower())


def slug(display_name: str) -> str:
    """'Rear Delts' becomes 'rearDelts', the muscle's name in the app's code."""
    words = re.split(r"[\s_-]+", display_name.strip())
    return words[0].lower() + "".join(w.capitalize() for w in words[1:])


def epley(weight_kg: float, reps: int) -> float:
    """The app's estimate (TrainingStats): one rep is the weight itself, and
    reps past the cap earn nothing more on the estimate."""
    trusted = min(reps, EPLEY_REP_CAP)
    return weight_kg if trusted == 1 else weight_kg * (1 + trusted / 30.0)


def _round(value: float | None, digits: int = 2) -> float | None:
    return None if value is None else round(value, digits)


def _mean(values):
    return sum(values) / len(values) if values else None


# --- the export, indexed --------------------------------------------------

def _timezone(snapshot: dict):
    name = snapshot.get("timeZone")
    if name:
        try:
            from zoneinfo import ZoneInfo
            return ZoneInfo(name)
        except Exception:
            pass
    return timezone.utc


def _now(snapshot: dict) -> datetime:
    if snapshot.get("exportedAt"):
        return parse_time(snapshot["exportedAt"])
    starts = [parse_time(s["startedAt"]) for s in snapshot.get("sessions", [])]
    return max(starts) if starts else datetime.now(timezone.utc)


def catalog_index(snapshot: dict) -> dict:
    """catalogID -> name, muscles (first is primary) and tracking."""
    index = {}
    for entry in snapshot.get("customExercises") or []:
        muscles = _unique(muscle_from_label(m) for m in entry.get("muscleRaw", []))
        index[entry["id"]] = {"name": entry["name"], "muscles": muscles,
                              "tracking": entry.get("trackingRaw")}
    for entry in snapshot.get("exerciseCatalog") or []:
        muscles = _unique(slug(m) for m in entry.get("muscles", []))
        if not muscles:
            muscles = _unique(muscle_from_label(m) for m in entry.get("muscleRaw", []))
        index[entry["catalogID"]] = {"name": entry["name"], "muscles": muscles,
                                     "tracking": entry.get("trackingRaw")}
    return index


def _unique(items) -> list:
    seen, out = set(), []
    for item in items:
        if item and item not in seen:
            seen.add(item)
            out.append(item)
    return out


def active_plan(snapshot: dict) -> dict | None:
    plans = snapshot.get("plans") or []
    for plan in plans:
        if plan.get("isActive"):
            return plan
    return None


def is_timed(item: dict, catalog: dict) -> bool:
    tracking = item.get("tracking") or (catalog.get(item.get("catalogID"), {}).get("tracking"))
    return tracking == "duration" or item.get("targetSeconds") is not None


# --- sessions and exposures -----------------------------------------------

def finished_sessions(snapshot: dict) -> list[dict]:
    """A session logged afterwards is exported without `endedAt`, since its
    times are a placeholder, but it is a finished workout; leaving it out
    dropped real sets from every series."""
    done = [s for s in snapshot.get("sessions", []) if s.get("endedAt") or s.get("loggedAfterwards")]
    return sorted(done, key=lambda s: parse_time(s["startedAt"]))


def working_sets(session: dict) -> list[dict]:
    """Completed, not a warm-up, and not a drop or cluster row: those belong to
    the set before them and never count as a separate effort."""
    ordered = sorted(session.get("sets", []), key=lambda s: (s.get("exerciseOrder", 0), s.get("setIndex", 0)))
    return [s for s in ordered
            if s.get("isCompleted") and not s.get("isWarmup") and not s.get("continues")]


def effort_ordinal(set_: dict) -> int | None:
    word = set_.get("effort")
    if word in EFFORT_ORDINAL:
        return EFFORT_ORDINAL[word]
    rpe = set_.get("rpe")
    if rpe is not None and float(rpe) in RPE_TO_EFFORT:
        return EFFORT_ORDINAL[RPE_TO_EFFORT[float(rpe)]]
    return None


def _modal_load(sets: list[dict]) -> float:
    counts = Counter(float(s.get("weightKg") or 0) for s in sets)
    top = max(counts.values())
    return max(load for load, n in counts.items() if n == top)


def _performance(sets: list[dict], tracking: str) -> dict | None:
    """One exposure's values, before the best is picked. See `Performance` in
    the policy: Epley up to twelve reps, reps at the modal load beyond that,
    seconds held at the modal load for a timed set."""
    if tracking == "duration" or all(s.get("reps") is None for s in sets):
        timed = [s for s in sets if s.get("seconds")]
        if not timed:
            return None
        load = _modal_load(timed)
        values = [float(s["seconds"]) for s in timed if float(s.get("weightKg") or 0) == load]
        return {"kind": "seconds", "key": f"seconds@{load:g}", "unit": "s", "load": load, "values": values}
    counted = [s for s in sets if s.get("reps")]
    if not counted:
        return None
    estimates = [epley(float(s.get("weightKg") or 0), s["reps"])
                 for s in counted if s["reps"] <= EPLEY_REP_CAP and float(s.get("weightKg") or 0) > 0]
    if estimates:
        return {"kind": "e1rm", "key": "e1rm", "unit": "kg", "values": estimates}
    load = _modal_load(counted)
    values = [float(s["reps"]) for s in counted if float(s.get("weightKg") or 0) == load]
    return {"kind": "reps", "key": f"reps@{load:g}", "unit": "reps", "load": load, "values": values}


def _set_text(s: dict, tracking: str) -> str:
    load = float(s.get("weightKg") or 0)
    if s.get("reps") is None and s.get("seconds") is not None:
        text = f"{s['seconds']}s"
    else:
        text = f"{s.get('reps', 0)}"
    if load > 0:
        text = f"{load:g}kg x {text}"
    word = EFFORT_WORD.get(effort_ordinal(s) or 0)
    return f"{text} {word}" if word else text


def build_exposures(snapshot: dict, catalog: dict) -> dict[str, list[dict]]:
    """catalogID -> exposures, oldest first. Non-comparable ones are kept and
    flagged, because the plateau test needs to know a swap happened."""
    plan_days = {}
    for plan in snapshot.get("plans", []):
        for day in plan.get("days", []):
            plan_days[str(day["id"]).lower()] = day
    out: dict[str, list[dict]] = defaultdict(list)
    for session in finished_sessions(snapshot):
        by_exercise: dict[str, list[dict]] = defaultdict(list)
        for s in working_sets(session):
            by_exercise[s["catalogID"]].append(s)
        notes: dict[str, list[dict]] = defaultdict(list)
        for note in session.get("exerciseNotes") or []:
            notes[note["catalogID"]].append(note)
        day = plan_days.get(str(session.get("planDayID") or "").lower())
        for catalog_id, sets in by_exercise.items():
            tracking = (sets[0].get("tracking") or catalog.get(catalog_id, {}).get("tracking")
                        or ("duration" if all(s.get("reps") is None for s in sets) else "weightReps"))
            perf = _performance(sets, tracking)
            if perf is None:
                continue
            tags = sorted({t for n in notes.get(catalog_id, []) for t in n.get("tags", [])})
            best = max(perf["values"])
            rest = list(perf["values"])
            rest.remove(best)
            answers = [(s, effort_ordinal(s)) for s in sets]
            efforts_all = [e for _, e in answers if e is not None]
            # Answers on sets of twelve reps or fewer (or timed) are trusted
            # more; the rest are kept so a high-rep slot still has a reading.
            efforts = [e for s, e in answers if e is not None and (s.get("reps") is None or s["reps"] <= EPLEY_REP_CAP)]
            last_answer = next((effort_ordinal(s) for s in reversed(sets) if effort_ordinal(s) is not None), None)
            target = None
            if day:
                slot = next((i for i in day.get("items", []) if i["catalogID"] == catalog_id), None)
                target = slot["targetSets"] if slot else None
            shortened = target is not None and len(sets) < max(1, math.ceil(target / 2))
            out[catalog_id].append({
                "date": session["startedAt"],
                "sessionID": session["id"],
                "tracking": tracking,
                "kind": perf["kind"],
                "unit": perf["unit"],
                "load": perf.get("load"),
                "seriesKey": f"{tracking}|{perf['key']}",
                "value": _round(best),
                "restMean": _round(_mean(rest)),
                "sets": len(sets),
                "efforts": efforts,
                "effortsAll": efforts_all,
                "lastSetEffort": last_answer,
                "answeredSets": len([s for s in sets if effort_ordinal(s) is not None]),
                "tags": tags,
                "loggedAfterwards": bool(session.get("loggedAfterwards")),
                "shortened": shortened,
                "comparable": "substitution" not in tags,
                "detail": [_set_text(s, tracking) for s in sets],
            })
    return out


# --- per exercise ---------------------------------------------------------

def typical_error(values: list[float]) -> float | None:
    """The lifter's own session-to-session wobble: the standard deviation of
    consecutive differences over root two (Hecksteden 2018). Differencing
    removes steady progress, so a lifter who is improving is not mistaken for
    a noisy one. Unknown until there are six exposures."""
    if len(values) < MIN_EXPOSURES_FOR_NOISE:
        return None
    recent = values[-NOISE_WINDOW:]
    diffs = [b - a for a, b in zip(recent, recent[1:])]
    return statistics.stdev(diffs) / math.sqrt(2)


def _series(exposures: list[dict]) -> tuple[list[dict], int]:
    comparable = [e for e in exposures if e["comparable"]]
    if not comparable:
        return [], 0
    key = comparable[-1]["seriesKey"]
    series = [e for e in comparable if e["seriesKey"] == key]
    return series, len(comparable) - len(series)


def _days_between(a: dict, b: dict) -> float:
    return (parse_time(b["date"]) - parse_time(a["date"])).total_seconds() / 86400


def plateau(series: list[dict], every: list[dict], noise: float | None) -> dict:
    """The policy's plateau, with the reason whenever it says no."""
    if len(series) < PLATEAU_MIN_EXPOSURES:
        return {"isPlateau": False, "blockedBy": [f"fewer than {PLATEAU_MIN_EXPOSURES} comparable exposures"]}
    start = len(series) - PLATEAU_MIN_EXPOSURES
    while start > 0 and _days_between(series[start], series[-1]) < PLATEAU_MIN_DAYS:
        start -= 1
    window = series[start:]
    days = _days_between(window[0], window[-1])
    result = {"window": {"exposures": len(window), "days": round(days, 1)}}
    blocked = []
    if days < PLATEAU_MIN_DAYS:
        blocked.append(f"the exposures span {days:.0f} days, under {PLATEAU_MIN_DAYS}")
    if noise is None:
        blocked.append(f"noise unknown until {MIN_EXPOSURES_FOR_NOISE} exposures")
    half = len(window) // 2
    gain = max(e["value"] for e in window[half:]) - max(e["value"] for e in window[:half])
    result["gain"] = round(gain, 2)
    if noise is not None and gain > noise:
        blocked.append("best performance improved beyond noise")
    first_effort = _mean([x for e in window[:half] for x in e["effortsAll"]])
    later_effort = _mean([x for e in window[half:] for x in e["effortsAll"]])
    if first_effort is not None and later_effort is not None and later_effort - first_effort <= -0.5:
        blocked.append("effort answers are trending easier")
    since = parse_time(window[0]["date"])
    nearby = [e for e in every if parse_time(e["date"]) >= since]
    for label, test in (("a pain note", lambda e: "pain" in e["tags"]),
                        ("a swap", lambda e: "substitution" in e["tags"] or not e["comparable"]),
                        ("a shortened session", lambda e: e["shortened"]),
                        ("a set logged afterwards", lambda e: e["loggedAfterwards"])):
        if any(test(e) for e in nearby):
            blocked.append(f"{label} in the window may explain it")
    result["isPlateau"] = not blocked
    if blocked:
        result["blockedBy"] = blocked
    return result


def analyse_exercise(catalog_id: str, exposures: list[dict], name: str) -> dict:
    series, other = _series(exposures)
    out = {"name": name, "otherSeriesExposures": other, "nonComparableExposures":
           len([e for e in exposures if not e["comparable"]])}
    if not series:
        out["exposures"] = 0
        return out
    values = [e["value"] for e in series]
    noise = typical_error(values)
    latest = series[-1]
    out.update({
        "kind": latest["kind"], "unit": latest["unit"], "seriesKey": latest["seriesKey"],
        "exposures": len(series), "lastDate": latest["date"],
        "performance": latest["value"], "performanceBest": max(values),
        "noiseKnown": noise is not None,
        "plateau": plateau(series, exposures, noise),
        "recent": [{"date": e["date"], "value": e["value"], "restMean": e["restMean"],
                    "sets": e["sets"], "detail": e["detail"], "tags": e["tags"]} for e in series[-6:]],
    })
    if latest["load"] is not None:
        out["loadKg"] = latest["load"]
    if noise is not None:
        out["noise"] = _round(noise)
    if len(series) >= 2:
        delta = round(values[-1] - values[-2], 2)
        out["deltaLatest"] = delta
        out["beyondNoise"] = None if noise is None else abs(delta) > noise
    window = series[-4:]
    efforts = [x for e in window for x in e["efforts"]]
    out["effortBasis"] = "upTo12Reps"
    if not efforts:
        efforts = [x for e in window for x in e["effortsAll"]]
        out["effortBasis"] = "over12Reps"
    if efforts:
        out["effortMean"] = _round(_mean(efforts))
        out["easyShare"] = _round(efforts.count(1) / len(efforts))
        last = [e["lastSetEffort"] for e in window if e["lastSetEffort"] is not None]
        if last:
            out["lastSetEffortMean"] = _round(_mean(last))
    total_sets = sum(e["sets"] for e in window)
    out["effortAnsweredShare"] = _round(sum(e["answeredSets"] for e in window) / total_sets) if total_sets else 0.0
    return out


# --- weekly volume --------------------------------------------------------

def _week_start(moment: datetime, tz) -> datetime:
    local = moment.astimezone(tz).date()
    return datetime.combine(local - timedelta(days=local.weekday()), datetime.min.time())


def fractional_sets(muscles: list[str]) -> dict[str, float]:
    return {m: (1.0 if i == 0 else 0.5) for i, m in enumerate(muscles)}


def muscle_volume(snapshot: dict, catalog: dict, now: datetime, tz) -> dict:
    """Fractional working sets per muscle per local (Monday-first) week."""
    per_week: dict[str, dict[datetime, float]] = defaultdict(lambda: defaultdict(float))
    per_session_max: dict[str, float] = defaultdict(float)
    sessions = finished_sessions(snapshot)
    if not sessions:
        return {"weeks": [], "muscles": {}}
    this_week = _week_start(now, tz)
    first_week = _week_start(parse_time(sessions[0]["startedAt"]), tz)
    window_start = max(first_week, this_week - timedelta(weeks=VOLUME_WEEKS))
    for session in sessions:
        started = parse_time(session["startedAt"])
        week = _week_start(started, tz)
        in_session: dict[str, float] = defaultdict(float)
        for s in working_sets(session):
            for muscle, weight in fractional_sets(catalog.get(s["catalogID"], {}).get("muscles", [])).items():
                per_week[muscle][week] += weight
                in_session[muscle] += weight
        if week >= window_start:
            for muscle, total in in_session.items():
                per_session_max[muscle] = max(per_session_max[muscle], total)
    complete = []
    cursor = window_start
    while cursor < this_week:
        complete.append(cursor)
        cursor += timedelta(weeks=1)
    out = {}
    for muscle, weeks in per_week.items():
        counted = [weeks.get(w, 0.0) for w in complete]
        out[muscle] = {
            "weeklyFractionalSets": _round(_mean(counted)) if counted else None,
            "lastWeekFractionalSets": _round(weeks.get(complete[-1], 0.0)) if complete else None,
            "thisWeekFractionalSets": _round(weeks.get(this_week, 0.0)),
            "maxSessionFractionalSets": _round(per_session_max.get(muscle, 0.0)),
            "weeksCounted": len(counted),
            "weekly": [_round(weeks.get(w, 0.0)) for w in complete],
        }
    return {"weeks": [w.strftime("%Y-%m-%d") for w in complete], "muscles": out}


# --- adherence, notes, body -----------------------------------------------

def adherence(snapshot: dict, now: datetime, tz) -> dict:
    """Only sessions started from a plan day can be measured against a plan."""
    days = {}
    for plan in snapshot.get("plans", []):
        for day in plan.get("days", []):
            days[str(day["id"]).lower()] = day
    since = now - timedelta(days=28)
    done = target = 0
    hits = rep_sets = 0
    from_plan = as_planned = 0
    for session in finished_sessions(snapshot):
        if parse_time(session["startedAt"]) < since:
            continue
        # The day as it stood when the session began, where the phone kept
        # it. Today's version of the day is the fallback for older sessions,
        # and it is wrong for any slot edited since.
        planned = session.get("plannedItems")
        day = days.get(str(session.get("planDayID") or "").lower())
        if planned is None and not day:
            continue
        from_plan += 1
        as_planned += planned is not None
        sets = working_sets(session)
        for slot in planned if planned is not None else day.get("items", []):
            logged = len([s for s in sets if s["catalogID"] == slot["catalogID"]])
            done += min(logged, slot["targetSets"])
            target += slot["targetSets"]
        for s in sets:
            low = s.get("targetRepsLow")
            if low and s.get("reps") is not None:
                rep_sets += 1
                hits += 1 if s["reps"] >= low else 0
    out = {"sessionsFromPlan": from_plan, "sessionsWithPlanRecord": as_planned}
    if target:
        out["slotSetsShare"] = _round(done / target)
    if rep_sets:
        out["repTargetHitShare"] = _round(hits / rep_sets)
    plan = active_plan(snapshot)
    due_days = [d for d in (plan or {}).get("days", []) if not d.get("isRest") and d.get("weekday") is not None
                and d.get("items")]
    if due_days:
        this_week = _week_start(now, tz)
        trained = defaultdict(set)
        for session in finished_sessions(snapshot):
            day_id = str(session.get("planDayID") or "").lower()
            if day_id in {str(d["id"]).lower() for d in due_days}:
                trained[_week_start(parse_time(session["startedAt"]), tz)].add(day_id)
        weeks = [this_week - timedelta(weeks=n) for n in range(1, VOLUME_WEEKS + 1)]
        # Weeks before this plan was first trained belong to another plan.
        # Counting them as missed days made a lifter who trained every day of
        # a two-week-old plan read as skipping more than half of it.
        first = min(trained) if trained else this_week
        weeks = [w for w in weeks if w >= first]
        if weeks:
            out["daysDuePerWeek"] = len(due_days)
            out["weeksMeasured"] = len(weeks)
            out["weekDaysTrainedShare"] = _round(
                sum(min(len(trained[w]), len(due_days)) for w in weeks) / (len(weeks) * len(due_days)))
    return out


def planned_vs_done(snapshot: dict, now: datetime, tz) -> list[dict]:
    """Sessions in the last four weeks where what was done differed from what
    the day prescribed at the time: planned slots with no working set, and
    exercises worked that were not planned. Only sessions that carry their
    plan record are read; pairing a skipped slot with its stand-in is left to
    the reader, since the file cannot say which replaced which."""
    since = now - timedelta(days=28)
    out = []
    for session in finished_sessions(snapshot):
        planned = session.get("plannedItems")
        if planned is None or parse_time(session["startedAt"]) < since:
            continue
        worked = {}
        for s in working_sets(session):
            worked.setdefault(s["catalogID"], s.get("exerciseName") or s["catalogID"])
        planned_ids = {slot["catalogID"] for slot in planned}
        skipped = [slot["name"] for slot in planned if slot["catalogID"] not in worked]
        extra = [name for cid, name in worked.items() if cid not in planned_ids]
        if skipped or extra:
            out.append({"date": parse_time(session["startedAt"]).astimezone(tz).strftime("%Y-%m-%d"),
                        "title": session.get("title", ""), "skipped": skipped, "notPlanned": extra})
    return out


def recent_sets(snapshot: dict, catalog_ids: list[str], tz, sessions_each: int = 4) -> dict[str, list[dict]]:
    """The last few sessions of each exercise, set by set, so a claim about a
    lift's recent history can be checked against what was logged. A
    comparable series restarts whenever the load changes on a long set, and
    on its own hides a lift that is climbing."""
    out = {cid: [] for cid in catalog_ids}
    for session in reversed(finished_sessions(snapshot)):
        by_exercise = defaultdict(list)
        for s in working_sets(session):
            if s["catalogID"] in out and len(out[s["catalogID"]]) < sessions_each:
                by_exercise[s["catalogID"]].append(s)
        for cid, sets in by_exercise.items():
            out[cid].append({"date": parse_time(session["startedAt"]).astimezone(tz).strftime("%m-%d"),
                             "sets": [_logged_set_text(s) for s in sets]})
    return {cid: list(reversed(rows)) for cid, rows in out.items() if rows}


def _logged_set_text(s: dict) -> str:
    if s.get("seconds") is not None and s.get("reps") is None:
        text = f"{s['seconds']}s"
    else:
        kg = s.get("weightKg") or 0
        text = f"{round(kg, 1):g}x{s.get('reps')}" if kg else f"bw x{s.get('reps')}"
    word = s.get("effort")
    return f"{text} {word}" if word in EFFORT_ORDINAL else text


def collect_notes(snapshot: dict, catalog: dict, now: datetime) -> list[dict]:
    since = now - timedelta(days=NOTE_DAYS)
    notes = []
    for session in finished_sessions(snapshot):
        started = parse_time(session["startedAt"])
        if started < since:
            continue
        for note in session.get("exerciseNotes") or []:
            notes.append({"date": session["startedAt"], "catalogID": note["catalogID"],
                          "exercise": note.get("exerciseName") or catalog.get(note["catalogID"], {}).get("name"),
                          "text": note.get("text", "")[:240], "tags": note.get("tags", [])})
        if session.get("notes") or session.get("noteTags"):
            notes.append({"date": session["startedAt"], "session": session.get("title"),
                          "text": (session.get("notes") or "")[:240], "tags": session.get("noteTags") or []})
    return sorted(notes, key=lambda n: n["date"], reverse=True)


def body_weight(snapshot: dict, now: datetime) -> dict:
    rows = sorted(snapshot.get("bodyMetrics") or [], key=lambda r: r["date"])
    if not rows:
        return {}
    latest = rows[-1]
    out = {"latestKg": round(latest["weightKg"], 1), "latestDate": latest["date"]}
    cutoff = now - timedelta(days=28)
    older = [r for r in rows if parse_time(r["date"]) <= cutoff]
    if older:
        out["change28dKg"] = round(latest["weightKg"] - older[-1]["weightKg"], 1)
    return out


# --- tape measurements -----------------------------------------------------

TAPE_PARTS = ("arm", "chest", "shoulders", "waist", "thigh")


def tape_checkins(snapshot: dict) -> list[dict]:
    """The owner's check-ins from the phone's Progress tab, oldest first.

    A check-in holds only the parts that were measured, and a part that was not
    has no key in the export. Anything that is not a real length above zero is
    treated as not measured rather than as a girth: a zero would read as a
    waist that collapsed.
    """
    rows = []
    for entry in snapshot.get("bodyMeasurements") or []:
        try:
            moment = parse_time(entry["date"])
        except (KeyError, TypeError, ValueError, AttributeError):
            continue
        parts = {}
        for part in TAPE_PARTS:
            cm = entry.get(f"{part}Cm")
            if isinstance(cm, (int, float)) and not isinstance(cm, bool) and math.isfinite(cm) and cm > 0:
                parts[part] = float(cm)
        if parts:
            rows.append({"date": entry["date"], "at": moment, "parts": parts})
    rows.sort(key=lambda row: row["at"])
    return rows


def tape(snapshot: dict, now: datetime, tz) -> dict:
    """Per part, the latest girth and how far it moved since the previous
    check-in that measured that part. A check-in that skipped the part is
    passed over, so waist taken monthly and arm taken weekly each compare
    with their own last reading. `changeCm` and `daysSincePrevious` are absent
    until a part has been measured twice."""
    rows = tape_checkins(snapshot)
    out = {"checkIns": len(rows), "parts": {}, "recent": []}
    if not rows:
        return out
    for part in TAPE_PARTS:
        measured = [row for row in rows if part in row["parts"]]
        if not measured:
            continue
        latest = measured[-1]
        info = {"latestCm": round(latest["parts"][part], 1), "latestDate": latest["date"]}
        if len(measured) > 1:
            previous = measured[-2]
            info["changeCm"] = round(latest["parts"][part] - previous["parts"][part], 1)
            info["daysSincePrevious"] = (latest["at"].astimezone(tz).date()
                                         - previous["at"].astimezone(tz).date()).days
            info["previousDate"] = previous["date"]
        out["parts"][part] = info
    out["recent"] = [{"date": row["date"], "parts": {k: round(v, 1) for k, v in row["parts"].items()}}
                     for row in rows[-4:]]
    out["daysSinceLast"] = (now.astimezone(tz).date() - rows[-1]["at"].astimezone(tz).date()).days
    return out


def tape_outcome(rows: list[dict], applied_at: datetime) -> dict:
    """Each part's change from the last check-in on or before `applied_at` to
    the latest one after it, for the parts that have both. A part with only one
    side is left out: half a comparison says nothing about the change."""
    out = {}
    for part in TAPE_PARTS:
        before = [row for row in rows if part in row["parts"] and row["at"] <= applied_at]
        after = [row for row in rows if part in row["parts"] and row["at"] > applied_at]
        if before and after:
            was, latest = before[-1], after[-1]
            out[part] = {"beforeCm": round(was["parts"][part], 1), "beforeDate": was["date"],
                         "afterCm": round(latest["parts"][part], 1), "afterDate": latest["date"],
                         "changeCm": round(latest["parts"][part] - was["parts"][part], 1)}
    return out


# --- plan, plan diff, last decision ----------------------------------------

def plan_summary(snapshot: dict) -> dict | None:
    plan = active_plan(snapshot)
    if not plan:
        return None
    default_rest = (snapshot.get("settings") or {}).get("defaultRestSeconds")
    days = []
    for day in sorted(plan.get("days", []), key=lambda d: d.get("order", 0)):
        items = []
        for item in sorted(day.get("items", []), key=lambda i: i.get("order", 0)):
            row = {"id": item.get("id"), "catalogID": item["catalogID"], "name": item["name"],
                   "targetSets": item["targetSets"], "restSeconds": item.get("restSeconds", default_rest)}
            for key in ("targetRepsLow", "targetRepsHigh", "targetSeconds"):
                if item.get(key) is not None:
                    row[key] = item[key]
            items.append(row)
        days.append({"id": day.get("id"), "name": day["name"], "weekday": day.get("weekday"),
                     "isRest": day.get("isRest", False), "items": items})
    return {"id": plan.get("id"), "name": plan["name"], "days": days}


_DIFF_FIELDS = ("catalogID", "targetSets", "targetRepsLow", "targetRepsHigh", "restSeconds", "targetSeconds")


def plan_diff(previous: dict | None, current: dict | None) -> dict:
    if previous is None or current is None:
        return {"available": False}
    if previous.get("id") != current.get("id"):
        return {"available": True, "planReplaced": {"from": previous["name"], "to": current["name"]}}
    def flat(plan):
        rows = {}
        for day in plan.get("days", []):
            for item in day.get("items", []):
                ident = item.get("id") or f"{day['name']}|{item['catalogID']}"
                rows[ident] = (day["name"], item)
        return rows
    before, after = flat(previous), flat(current)
    added = [{"day": d, "name": i["name"]} for k, (d, i) in after.items() if k not in before]
    removed = [{"day": d, "name": i["name"]} for k, (d, i) in before.items() if k not in after]
    changed = []
    for key, (day, item) in after.items():
        if key not in before:
            continue
        old = before[key][1]
        for field in _DIFF_FIELDS:
            if old.get(field) != item.get(field):
                changed.append({"day": day, "name": item["name"], "field": field,
                                "from": old.get(field), "to": item.get(field)})
    return {"available": True, "added": added, "removed": removed, "changed": changed}


def last_decision_outcome(decisions: dict | None, exposures: dict[str, list[dict]],
                          proposals: dict, snapshot: dict, catalog: dict) -> dict | None:
    """What happened to the items the last applied proposal touched: their
    performance before and since, and whether the change was backed out."""
    applied = [d for d in (decisions or {}).get("decisions", []) if d.get("appliedAt")]
    if not applied:
        return None
    decision = max(applied, key=lambda d: d["appliedAt"])
    applied_at = parse_time(decision["appliedAt"])
    catalogs = {}
    for entry in decision.get("before", []):
        item = entry.get("item") or {}
        cid = item.get("catalogID")
        if not cid:
            for plan in snapshot.get("plans", []):
                for day in plan.get("days", []):
                    for it in day.get("items", []):
                        if same_id(it.get("id"), entry.get("itemID")):
                            cid = it["catalogID"]
        if cid:
            catalogs[cid] = True
    proposal = proposals.get(str(decision.get("proposalID", "")).lower())
    kinds = {}
    for change in (proposal or {}).get("changes", []):
        to_id = (change.get("to") or {}).get("catalogID")
        if to_id:
            catalogs[to_id] = True
        accepted = any(c.get("id") == change["id"] and c.get("decision") == "accepted"
                       for c in decision.get("changes", []))
        if accepted:
            kinds[change["id"]] = change["kind"]
    out = {"proposalID": decision.get("proposalID"), "appliedAt": decision["appliedAt"],
           "reverted": bool(decision.get("revertedAt")), "appliedKinds": kinds, "items": {}}
    if decision.get("revertedAt"):
        out["revertedAt"] = decision["revertedAt"]
    for cid in catalogs:
        series, _ = _series(exposures.get(cid, []))
        before = [e for e in series if parse_time(e["date"]) < applied_at]
        after = [e for e in series if parse_time(e["date"]) >= applied_at]
        item = {"name": catalog.get(cid, {}).get("name", cid), "exposuresSince": len(after)}
        if before:
            item["performanceBefore"] = max(e["value"] for e in before[-4:])
        if after:
            item["performanceAfterBest"] = max(e["value"] for e in after)
            item["performanceAfterLatest"] = after[-1]["value"]
        if before and after:
            item["delta"] = round(item["performanceAfterBest"] - item["performanceBefore"], 2)
            noise = typical_error([e["value"] for e in series])
            item["beyondNoise"] = None if noise is None else abs(item["delta"]) > noise
        eb = [x for e in before[-4:] for x in e["effortsAll"]]
        ea = [x for e in after for x in e["effortsAll"]]
        if eb:
            item["effortMeanBefore"] = _round(_mean(eb))
        if ea:
            item["effortMeanAfter"] = _round(_mean(ea))
        out["items"][cid] = item
    outcome = tape_outcome(tape_checkins(snapshot), applied_at)
    if outcome:
        out["tape"] = outcome
    return out


# --- profile ----------------------------------------------------------------

def parse_profile(text: str | None) -> dict:
    """The one line the stats read: priority muscles. Tape measurements are not
    here; they come from the phone's check-ins."""
    out = {"priorityLabels": [], "priorityMuscles": []}
    if not text:
        return out
    match = re.search(r"^[ \t]*Priority muscles:[ \t]*(\S.*)$", text, re.M | re.I)
    if match:
        labels = [p.strip() for p in re.split(r"[,;]", match.group(1)) if p.strip()]
        out["priorityLabels"] = labels
        out["priorityMuscles"] = _unique(muscle_from_label(label) for label in labels)
    return out


# --- everything -----------------------------------------------------------

def compute(snapshot: dict, decisions: dict | None = None, previous: dict | None = None,
            proposals: dict | None = None, profile_text: str | None = None,
            previous_exported_at: str | None = None) -> dict:
    proposals = proposals or {}
    tz = _timezone(snapshot)
    now = _now(snapshot)
    catalog = catalog_index(snapshot)
    exposures = build_exposures(snapshot, catalog)
    plan = plan_summary(snapshot)
    profile = parse_profile(profile_text)
    metrics: dict = {}

    exercises = {}
    for cid, rows in exposures.items():
        exercises[cid] = analyse_exercise(cid, rows, catalog.get(cid, {}).get("name", cid))
    notes = collect_notes(snapshot, catalog, now)
    pain = Counter()
    pain_entries = 0
    for n in notes:
        if "pain" in n["tags"]:
            pain_entries += 1
            if n.get("catalogID"):
                pain[n["catalogID"]] += 1
    for cid, info in exercises.items():
        info["painNotes90d"] = pain.get(cid, 0)
    for cid, count in pain.items():
        exercises.setdefault(cid, {"name": catalog.get(cid, {}).get("name", cid), "exposures": 0,
                                   "painNotes90d": count})
    for cid, info in exercises.items():
        base = f"ex.{cid}"
        metrics[f"{base}.exposures"] = info["exposures"]
        metrics[f"{base}.painNotes90d"] = info["painNotes90d"]
        if not info["exposures"]:
            continue
        for key in ("performance", "performanceBest", "noise", "effortMean", "easyShare",
                    "effortAnsweredShare", "deltaLatest", "lastDate"):
            if info.get(key) is not None:
                metrics[f"{base}.{key}"] = info[key]
        metrics[f"{base}.plateau"] = info["plateau"]["isPlateau"]
        if info.get("beyondNoise") is not None:
            metrics[f"{base}.beyondNoise"] = info["beyondNoise"]

    volume = muscle_volume(snapshot, catalog, now, tz)
    muscles = volume["muscles"]
    plan_muscles = set()
    for day in (plan or {}).get("days", []):
        for item in day["items"]:
            plan_muscles.update(catalog.get(item["catalogID"], {}).get("muscles", []))
    for muscle in plan_muscles | set(profile["priorityMuscles"]):
        muscles.setdefault(muscle, {"weeklyFractionalSets": 0.0 if volume["weeks"] else None,
                                    "lastWeekFractionalSets": 0.0 if volume["weeks"] else None,
                                    "thisWeekFractionalSets": 0.0, "maxSessionFractionalSets": 0.0,
                                    "weeksCounted": len(volume["weeks"]), "weekly": [0.0] * len(volume["weeks"])})
    for muscle, info in muscles.items():
        for key in ("weeklyFractionalSets", "lastWeekFractionalSets", "thisWeekFractionalSets",
                    "maxSessionFractionalSets"):
            if info.get(key) is not None:
                metrics[f"{muscle}.{key}"] = info[key]

    adhere = adherence(snapshot, now, tz)
    deviations = planned_vs_done(snapshot, now, tz)
    plan_ids = list(dict.fromkeys(item["catalogID"] for day in (plan or {}).get("days", []) for item in day["items"]))
    recent = recent_sets(snapshot, plan_ids, tz)
    for key, value in adhere.items():
        metrics[f"adherence.{key}"] = value
    body = body_weight(snapshot, now)
    for key, value in body.items():
        metrics[f"body.{key}"] = value
    girth = tape(snapshot, now, tz)
    for part, info in girth["parts"].items():
        for key in ("latestCm", "changeCm", "daysSincePrevious"):
            if key in info:
                metrics[f"tape.{part}.{key}"] = info[key]
    metrics["notes.painEntries90d"] = pain_entries

    diff = plan_diff(previous and active_plan(previous), active_plan(snapshot))
    decision = last_decision_outcome(decisions, exposures, proposals, snapshot, catalog)
    if decision:
        metrics["lastDecision.reverted"] = decision["reverted"]
        for cid, item in decision["items"].items():
            for key, value in item.items():
                if key != "name":
                    metrics[f"lastDecision.{cid}.{key}"] = value
        for part, row in decision.get("tape", {}).items():
            metrics[f"lastDecision.tape.{part}.changeCm"] = row["changeCm"]

    since = parse_time(previous_exported_at) if previous_exported_at else None
    sessions_since = [s for s in finished_sessions(snapshot) if since is None or parse_time(s["startedAt"]) > since]
    exposures_since = sum(1 for rows in exposures.values() for e in rows if since is None or parse_time(e["date"]) > since)
    pain_since = len([n for n in notes if "pain" in n["tags"] and (since is None or parse_time(n["date"]) > since)])
    plateaus = [cid for cid, info in exercises.items() if info.get("plateau", {}).get("isPlateau")]
    pending = [d for d in (decisions or {}).get("decisions", []) if not d.get("decidedAt")]
    review = {"previousExportedAt": previous_exported_at, "sessionsSinceLastReview": len(sessions_since),
              "exposuresSinceLastReview": exposures_since, "painNotesSinceLastReview": pain_since,
              "plateauCount": len(plateaus), "plateaus": plateaus, "proposalAwaitingDecision": bool(pending)}
    review["summary"] = _review_sentence(review)
    for key in ("sessionsSinceLastReview", "exposuresSinceLastReview", "painNotesSinceLastReview", "plateauCount"):
        metrics[f"review.{key}"] = review[key]

    return {
        "format": "gymtrack-coach-stats", "version": 1,
        "asOf": format_time(now), "timeZone": snapshot.get("timeZone"),
        "sessionCount": len(finished_sessions(snapshot)),
        "metrics": metrics, "review": review, "plan": plan, "planDiff": diff,
        "lastDecision": decision, "exercises": exercises,
        "muscles": muscles, "volumeWeeks": volume["weeks"], "adherence": adhere,
        "plannedVsDone": deviations, "recentSets": recent,
        "body": body, "tape": girth, "notes": notes[:25], "profile": profile,
    }


def _review_sentence(review: dict) -> str:
    if review["proposalAwaitingDecision"]:
        return "A proposal is still waiting for a decision on the phone; review nothing new until it is decided."
    if review["sessionsSinceLastReview"] == 0:
        return "No finished sessions since the last review: keep the plan."
    parts = [f"{review['sessionsSinceLastReview']} sessions and {review['exposuresSinceLastReview']} exercise exposures "
             "since the last review" if review["previousExportedAt"] else
             f"{review['sessionsSinceLastReview']} sessions and {review['exposuresSinceLastReview']} exercise exposures "
             "in total (no earlier review)"]
    if review["plateauCount"]:
        parts.append(f"{review['plateauCount']} plateau(s)")
    if review["painNotesSinceLastReview"]:
        parts.append(f"{review['painNotesSinceLastReview']} pain note(s)")
    return "; ".join(parts) + "."


# --- stats.md -------------------------------------------------------------

_HEADER = """\
# Stats for this review

Every number below is computed by `coach stats` and is the only source for
`evidence.metric` in a proposal. Keys in stats.json under `metrics`:

- `<muscle>.weeklyFractionalSets`: mean fractional working sets per local week
  over the last four complete weeks (muscle names as in the app: chest,
  shoulders, rearDelts, biceps, triceps, lats, upperBack, quads, ...). Siblings:
  `.lastWeekFractionalSets`, `.thisWeekFractionalSets` (partial),
  `.maxSessionFractionalSets` (largest single session in the window).
- `ex.<catalogID>.exposures | performance | performanceBest | noise |
  effortMean | easyShare | effortAnsweredShare | deltaLatest | plateau |
  beyondNoise | painNotes90d`: per exercise, over its current comparable series.
  `noise` and `beyondNoise` are absent until six comparable exposures exist.
- `adherence.slotSetsShare | repTargetHitShare | weekDaysTrainedShare` (last
  four weeks), `body.latestKg | change28dKg`, `notes.painEntries90d`.
- `tape.<part>.latestCm | changeCm | daysSincePrevious`, for part arm, chest,
  shoulders, waist, thigh: the owner's tape check-ins from the phone's Progress
  tab. `changeCm` and `daysSincePrevious` are against the previous check-in
  that measured that part and are absent until it has been measured twice; a
  part never measured has no key at all.
- `review.sessionsSinceLastReview | exposuresSinceLastReview |
  painNotesSinceLastReview | plateauCount`, and
  `lastDecision.<catalogID>.delta | beyondNoise | exposuresSince`, and
  `lastDecision.tape.<part>.changeCm` (the last check-in on or before the
  decision to the latest after it, where both exist).

Performance is the capped Epley estimate in kg up to 12 reps, reps at the
modal load beyond that, seconds held for a timed set. Effort answers are
ordinal: 1 easy, 2 solid, 3 hard, 4 allOut.
"""


def _f(value, digits=1):
    return "-" if value is None else f"{value:.{digits}f}"


def _recent(info: dict, as_of: str, days: int = 56) -> bool:
    return bool(info.get("lastDate")) and parse_time(as_of) - parse_time(info["lastDate"]) <= timedelta(days=days)


def _measurements_section(girth: dict) -> list[str]:
    out = ["## Measurements", ""]
    if not girth["checkIns"]:
        return out + ["No tape check-ins logged on the phone. A check-in is the owner's to make; "
                      "absence is not a miss.", ""]
    out += ["Tape girths in cm from the owner's check-ins on the phone's Progress tab (last four, oldest "
            "first). `-` is a part not measured that day. Noisy: weigh lightly, and read the waist beside "
            "body weight to tell lean gain from fat.", "",
            "| date | " + " | ".join(TAPE_PARTS) + " |", "|---" * (len(TAPE_PARTS) + 1) + "|"]
    for row in girth["recent"]:
        cells = [f"{row['parts'][part]:g}" if part in row["parts"] else "-" for part in TAPE_PARTS]
        out.append(f"| {row['date'][:10]} | " + " | ".join(cells) + " |")
    out.append("")
    for part, info in girth["parts"].items():
        if "changeCm" in info:
            out.append(f"- {part}: {info['latestCm']:g} cm, {info['changeCm']:+.1f} cm over "
                       f"{info['daysSincePrevious']} days since the previous check-in that measured it")
        else:
            out.append(f"- {part}: {info['latestCm']:g} cm, measured once")
    days = girth["daysSinceLast"]
    out += ["", f"Last check-in {days} day{'s' if days != 1 else ''} before this export"
            + (", none in the last four weeks." if days > 28 else "."), ""]
    return out


def render_markdown(stats: dict) -> str:
    out = [_HEADER, f"As of {stats['asOf']} ({stats.get('timeZone') or 'UTC'}); {stats['sessionCount']} finished sessions.\n"]
    review = stats["review"]
    out += ["## Anything to review?", "", review["summary"], ""]
    if review["plateaus"]:
        out.append("Plateaus: " + ", ".join(stats["exercises"][c]["name"] for c in review["plateaus"]))
        out.append("")

    plan = stats["plan"]
    out.append("## Active plan")
    if plan:
        out += [f"Plan `{plan['name']}` id `{plan['id']}`", ""]
        for day in plan["days"]:
            tag = " (rest)" if day["isRest"] else ""
            out.append(f"- **{day['name']}**{tag} dayID `{day['id']}`")
            for item in day["items"]:
                reps = (f"{item['targetRepsLow']}-{item['targetRepsHigh']} reps" if "targetRepsLow" in item
                        else f"{item.get('targetSeconds', '?')} s")
                out.append(f"  - {item['name']}: {item['targetSets']} x {reps}, rest {item.get('restSeconds', '?')} s,"
                           f" catalogID `{item['catalogID']}`, itemID `{item['id']}`")
    else:
        out.append("No active plan.")
    out.append("")

    out += ["## Weekly fractional sets per muscle", "",
            "| muscle | 4-week mean | last week | this week (partial) | max in one session | priority |", "|---|---|---|---|---|---|"]
    priority = set(stats["profile"]["priorityMuscles"])
    for muscle, info in sorted(stats["muscles"].items(), key=lambda kv: -(kv[1].get("weeklyFractionalSets") or 0)):
        out.append(f"| {muscle} | {_f(info.get('weeklyFractionalSets'))} | {_f(info.get('lastWeekFractionalSets'))} | "
                   f"{_f(info.get('thisWeekFractionalSets'))} | {_f(info.get('maxSessionFractionalSets'))} | "
                   f"{'yes' if muscle in priority else ''} |")
    out.append("")

    out += ["## Exercises (current comparable series)", "",
            "| exercise | n | latest | best | noise | vs last | plateau | effort mean | easy share | pain 90d |",
            "|---|---|---|---|---|---|---|---|---|---|"]
    plan_ids = {i["catalogID"] for d in (plan or {"days": []})["days"] for i in d["items"]}
    shown = {cid: info for cid, info in stats["exercises"].items()
             if info["exposures"] and (cid in plan_ids or _recent(info, stats["asOf"]))}
    for cid, info in sorted(shown.items(), key=lambda kv: kv[1]["name"]):
        unit = info["unit"]
        if "beyondNoise" in info and info["beyondNoise"] is not None:
            versus = f"{info['deltaLatest']:+.1f} ({'beyond' if info['beyondNoise'] else 'within'} noise)"
        elif "deltaLatest" in info:
            versus = f"{info['deltaLatest']:+.1f} (noise unknown)"
        else:
            versus = "-"
        flag = "YES" if info["plateau"]["isPlateau"] else "no"
        out.append(f"| {info['name']} (`{cid}`) | {info['exposures']} | {_f(info['performance'])} {unit} | "
                   f"{_f(info['performanceBest'])} | {_f(info.get('noise'), 2) if info['noiseKnown'] else 'unknown'} | "
                   f"{versus} | {flag} | {_f(info.get('effortMean'))}{'*' if info.get('effortBasis') == 'over12Reps' else ''} | {_f(info.get('easyShare'), 2)} | "
                   f"{info['painNotes90d']} |")
    out += ["", "`*` effort answers come only from sets above 12 reps, which are less reliable.", ""]
    for cid, info in sorted(shown.items(), key=lambda kv: kv[1]["name"]):
        trail = ", ".join(f"{e['date'][5:10]} {e['value']:g}" for e in info["recent"])
        out.append(f"- {info['name']}: {trail}")
    out.append("")
    unplanned = [i for i in stats["exercises"].values() if i["exposures"] == 0 and i["painNotes90d"]]
    for info in unplanned:
        out.append(f"- {info['name']}: pain notes with no comparable series.")

    names = {item["catalogID"]: item["name"] for day in (stats["plan"] or {}).get("days", []) for item in day["items"]}
    out += ["## Recent sets (active plan, last four sessions each)", "",
            "Load x reps, with the effort answer where one was given; `bw` is no added load.", ""]
    for cid, rows in stats.get("recentSets", {}).items():
        trail = "; ".join(f"{row['date']} " + ", ".join(row["sets"]) for row in rows)
        out.append(f"- {names.get(cid, cid)}: {trail}")
    out.append("")

    adhere = stats["adherence"]
    out += ["## Adherence (last 4 weeks)", ""]
    if adhere.get("sessionsFromPlan"):
        out.append(f"- Sessions started from a plan day: {adhere['sessionsFromPlan']}, "
                   f"{adhere.get('sessionsWithPlanRecord', 0)} of them measured against the day as it stood "
                   "then; the rest against today's version of the day, which may have been edited since")
        if "slotSetsShare" in adhere:
            out.append(f"- Working sets logged against the slots' targets: {adhere['slotSetsShare']:.0%}")
        if "repTargetHitShare" in adhere:
            out.append(f"- Sets at or above the lower rep target: {adhere['repTargetHitShare']:.0%}")
        if "weekDaysTrainedShare" in adhere:
            weeks = adhere["weeksMeasured"]
            out.append(f"- Scheduled days trained per week: {adhere['weekDaysTrainedShare']:.0%} of "
                       f"{adhere['daysDuePerWeek']}, over {weeks} complete week{'s' if weeks != 1 else ''} "
                       "since this plan was first trained")
    else:
        out.append("No sessions started from a plan day in this window.")
    out.append("")

    out += ["## Planned against done (last 4 weeks)", ""]
    deviations = stats.get("plannedVsDone", [])
    if not adhere.get("sessionsWithPlanRecord"):
        out.append("No session in this window recorded what its plan day prescribed (older app builds did not), "
                   "so a skipped or swapped slot cannot be told from a plan edit. Ask.")
    elif not deviations:
        out.append("Every recorded session did what its plan day prescribed.")
    for d in deviations:
        parts = []
        if d["skipped"]:
            parts.append("skipped " + ", ".join(d["skipped"]))
        if d["notPlanned"]:
            parts.append("not in the plan that day: " + ", ".join(d["notPlanned"]))
        out.append(f"- {d['date']} {d['title']}: {'; '.join(parts)}")
    out.append("")

    out += ["## Plan changes since the previous review", ""]
    diff = stats["planDiff"]
    if not diff["available"]:
        out.append("No earlier review to compare with.")
    elif "planReplaced" in diff:
        out.append(f"The active plan was replaced: {diff['planReplaced']['from']} to {diff['planReplaced']['to']}.")
    elif not (diff["added"] or diff["removed"] or diff["changed"]):
        out.append("The plan is unchanged.")
    else:
        for row in diff["added"]:
            out.append(f"- Added {row['name']} on {row['day']}")
        for row in diff["removed"]:
            out.append(f"- Removed {row['name']} from {row['day']}")
        for row in diff["changed"]:
            out.append(f"- {row['name']} ({row['day']}): {row['field']} {row['from']} to {row['to']}")
    out.append("")

    out += ["## Outcome of the last applied proposal", ""]
    decision = stats["lastDecision"]
    if not decision:
        out.append("No proposal has been applied yet.")
    else:
        state = "later reverted" if decision["reverted"] else "still in place"
        out.append(f"Applied {decision['appliedAt']}, {state}.")
        for cid, item in decision["items"].items():
            bits = [f"{item['exposuresSince']} exposures since"]
            if "performanceBefore" in item:
                bits.append(f"before {item['performanceBefore']:g}")
            if "performanceAfterBest" in item:
                bits.append(f"after best {item['performanceAfterBest']:g}")
            if "delta" in item:
                verdict = {True: "beyond noise", False: "within noise", None: "noise unknown"}[item["beyondNoise"]]
                bits.append(f"delta {item['delta']:+g} ({verdict})")
            out.append(f"- {item['name']} (`{cid}`): " + ", ".join(bits))
        for part, row in decision.get("tape", {}).items():
            out.append(f"- Tape, {part}: {row['beforeCm']:g} cm on {row['beforeDate'][:10]} (last check-in on or "
                       f"before it) to {row['afterCm']:g} cm on {row['afterDate'][:10]} (latest since), "
                       f"{row['changeCm']:+.1f} cm")
    out.append("")

    body = stats["body"]
    if body:
        change = f", {body['change28dKg']:+.1f} kg over 28 days" if "change28dKg" in body else ""
        out += ["## Body weight", "", f"Latest {body['latestKg']} kg{change}. Performance can rise from bodyweight "
                "gained as fat; read the two together.", ""]
    out += _measurements_section(stats["tape"])

    out += ["## Notes and tags (last 90 days, newest first)", ""]
    if not stats["notes"]:
        out.append("None.")
    for n in stats["notes"][:15]:
        who = n.get("exercise") or n.get("session") or "session"
        tags = f" [{', '.join(n['tags'])}]" if n["tags"] else ""
        text = f": {n['text']}" if n["text"] else ""
        out.append(f"- {n['date'][:10]} {who}{tags}{text}")
    out.append("")
    return "\n".join(out)
