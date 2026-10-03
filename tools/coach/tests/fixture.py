"""A small, invented training history in the phone's export format.

Nothing here comes from a real lifter. The numbers are chosen so the expected
results can be checked by hand:

* Bench: top set 6 reps at 80, 82.5, 82.5, 85, 85, 87.5, 87.5, 90 kg over eight
  Mondays, so performance (Epley, x1.2 at six reps) climbs 96 ... 108.
* Lateral raise: 10 kg for 12 or 11 reps with solid effort throughout, a plateau.
* Triceps pushdown: a pain note on the last Monday.
* Pull-up: bodyweight reps with every answer "easy"; one Wednesday skipped.
* Seated cable row: fourteen to seventeen reps, so it is scored in reps at 50 kg.
* Plank: timed.
* Leg press: one session tagged as a substitution.

The export is taken on Saturday 2026-10-03; the four complete weeks before it
start on 2026-08-31.
"""
from __future__ import annotations

import json
import uuid
from datetime import date, timedelta
from pathlib import Path

NAMESPACE = uuid.UUID("5d1f0f0e-0000-4000-8000-00000000c0ac")
FIRST_MONDAY = date(2026, 8, 10)
EXPORTED_AT = "2026-10-03T12:00:00Z"
PHONE_ID = "00008150-000504383447401C"


def uid(name: str) -> str:
    """Deterministic, and in capitals the way Swift writes a UUID."""
    return str(uuid.uuid5(NAMESPACE, name)).upper()


PLAN_ID = uid("plan-active")
OLD_PLAN_ID = uid("plan-old")
DAY_PUSH, DAY_PULL, DAY_LEGS, DAY_REST = (uid(f"day-{n}") for n in ("push", "pull", "legs", "rest"))

# catalogID, name, canonical muscles, raw labels, tracking, equipment
CATALOG = [
    ("barbell-bench-press", "Barbell Bench Press", ["Chest", "Triceps", "Shoulders"],
     ["Chest", "Triceps", "Front Delts"], "weightReps", ["Barbell", "Bench"]),
    ("lateral-raise", "Lateral Raise", ["Shoulders"], ["Side Delts"], "weightReps", ["Dumbbell"]),
    ("triceps-pushdown", "Triceps Pushdown", ["Triceps"], ["Triceps"], "weightReps", ["Cable"]),
    ("pull-up", "Pull-Up", ["Lats", "Biceps"], ["Lats", "Biceps"], "bodyweightReps", ["Pull-up Bar"]),
    ("seated-cable-row", "Seated Cable Row", ["Lats", "Upper Back", "Biceps"], ["Lats", "Mid Back", "Biceps"],
     "weightReps", ["Cable"]),
    ("plank", "Plank", ["Abs"], ["Core"], "duration", []),
    ("leg-press", "Leg Press", ["Quads", "Glutes"], ["Quads", "Glutes"], "weightReps", ["Machine"]),
    ("incline-dumbbell-press", "Incline Dumbbell Press", ["Chest", "Shoulders", "Triceps"],
     ["Upper Chest", "Front Delts", "Triceps"], "weightReps", ["Dumbbell", "Bench"]),
]

BENCH_KG = [80, 82.5, 82.5, 85, 85, 87.5, 87.5, 90]
LATERAL_REPS = [12, 11, 12, 12, 11, 12, 12, 11]
PULL_REPS = [8, 8, 9, 9, None, 10, 10, 11]
ROW_REPS = [14, 15, 15, 16, 16, 16, 17, 17]
LEG_REPS = [10, 10, 10, 11, 11, 11, 12, 12]

# (catalogID, targetSets, low, high, rest, extra)
PLAN_DAYS = [
    (DAY_PUSH, "Push A", 2, [("barbell-bench-press", 3, 6, 10, 150), ("lateral-raise", 3, 10, 15, None),
                             ("triceps-pushdown", 3, 10, 15, 75)]),
    (DAY_PULL, "Pull", 4, [("pull-up", 3, 6, 10, None), ("seated-cable-row", 3, 8, 12, None),
                           ("plank", 3, None, None, None)]),
    (DAY_LEGS, "Legs", 6, [("leg-press", 3, 8, 12, None)]),
]
_NAME = {row[0]: row[1] for row in CATALOG}
_TRACKING = {row[0]: row[4] for row in CATALOG}


def item_id(catalog_id: str) -> str:
    return uid(f"item-{catalog_id}")


def _plan_item(catalog_id, sets, low, high, rest, order):
    item = {"id": item_id(catalog_id), "catalogID": catalog_id, "name": _NAME[catalog_id], "order": order,
            "targetSets": sets}
    if _TRACKING[catalog_id] == "duration":
        item["tracking"] = "duration"
        item["targetSeconds"] = 45
    else:
        item["targetRepsLow"], item["targetRepsHigh"] = low, high
    if rest is not None:
        item["restSeconds"] = rest
    return item


def plans() -> list[dict]:
    days = []
    for order, (day_id, name, weekday, items) in enumerate(PLAN_DAYS):
        days.append({"id": day_id, "name": name, "order": order, "weekday": weekday, "isRest": False,
                     "items": [_plan_item(*row, order=i) for i, row in enumerate(items)]})
    days.append({"id": DAY_REST, "name": "Rest", "order": len(days), "weekday": 1, "isRest": True, "items": []})
    old = {"id": OLD_PLAN_ID, "name": "Old Plan", "summary": "", "isActive": False,
           "createdAt": "2026-01-01T09:00:00Z", "days": []}
    return [{"id": PLAN_ID, "name": "Upper Lower", "summary": "Synthetic plan", "isActive": True,
             "createdAt": "2026-08-01T09:00:00Z", "days": days}, old]


def _set(session_key, catalog_id, order, index, kg, reps, effort=None, seconds=None, targets=None):
    out = {"id": uid(f"{session_key}-{catalog_id}-{index}"), "catalogID": catalog_id,
           "exerciseName": _NAME[catalog_id], "exerciseOrder": order, "setIndex": index, "weightKg": kg,
           "tracking": _TRACKING[catalog_id], "isCompleted": True}
    if reps is not None:
        out["reps"] = reps
    if seconds is not None:
        out["seconds"] = seconds
    if effort:
        out["effort"] = effort
        out["rpe"] = {"easy": 6, "solid": 8, "hard": 9, "allOut": 10}[effort]
    if targets:
        out["targetRepsLow"], out["targetRepsHigh"] = targets
    return out


def _session(day, week, offset, title, day_id, sets, notes=None, key=None):
    stamp = (FIRST_MONDAY + timedelta(weeks=week, days=offset)).isoformat()
    out = {"id": uid(f"session-{key or stamp}"), "title": title, "planName": "Upper Lower", "planDayID": day_id,
           "startedAt": f"{stamp}T10:00:00Z", "endedAt": f"{stamp}T11:00:00Z", "sets": sets}
    if notes:
        out["exerciseNotes"] = notes
    return out


def sessions() -> list[dict]:
    out = []
    for week in range(8):
        key = f"w{week}"
        bench = BENCH_KG[week]
        sets = [_set(key, "barbell-bench-press", 0, 0, bench, 6, "solid", targets=(6, 10)),
                _set(key, "barbell-bench-press", 0, 1, bench, 6, "solid", targets=(6, 10)),
                _set(key, "barbell-bench-press", 0, 2, bench, 5, "hard", targets=(6, 10))]
        sets += [_set(key, "lateral-raise", 1, i, 10, LATERAL_REPS[week], "solid", targets=(10, 15)) for i in range(3)]
        sets += [_set(key, "triceps-pushdown", 2, 0, 25, 12, "solid", targets=(10, 15)),
                 _set(key, "triceps-pushdown", 2, 1, 25, 12, "solid", targets=(10, 15)),
                 _set(key, "triceps-pushdown", 2, 2, 25, 11, "hard", targets=(10, 15))]
        notes = None
        if week == 7:
            notes = [{"catalogID": "triceps-pushdown", "exerciseName": "Triceps Pushdown",
                      "text": "Right elbow twinge on the last set", "tags": ["pain"]}]
        out.append(_session("push", week, 0, "Push A", DAY_PUSH, sets, notes, key=f"push-{week}"))

        reps = PULL_REPS[week]
        if reps is not None:
            sets = [_set(key, "pull-up", 0, i, 0, reps - i, "easy", targets=(6, 10)) for i in range(3)]
            row = ROW_REPS[week]
            sets += [_set(key, "seated-cable-row", 1, i, 50, row - i, "solid", targets=(8, 12)) for i in range(3)]
            sets += [_set(key, "plank", 2, i, 0, None, seconds=60) for i in range(3)]
            notes = None
            if week == 6:
                notes = [{"catalogID": "pull-up", "exerciseName": "Pull-Up", "text": "Slept badly",
                          "tags": ["feltFlat"]}]
            out.append(_session("pull", week, 2, "Pull", DAY_PULL, sets, notes, key=f"pull-{week}"))

        sets = [_set(key, "leg-press", 0, i, 200, LEG_REPS[week], "solid", targets=(8, 12)) for i in range(3)]
        notes = None
        if week == 3:
            notes = [{"catalogID": "leg-press", "exerciseName": "Leg Press", "text": "Other machine",
                      "tags": ["substitution"]}]
        out.append(_session("legs", week, 4, "Legs", DAY_LEGS, sets, notes, key=f"legs-{week}"))
    return out


def export() -> dict:
    return {
        "version": 2,
        "exportedAt": EXPORTED_AT,
        "timeZone": "Africa/Cairo",
        "appVersion": "2.1",
        "appBuild": "1",
        "settings": {"weightUnit": "kg", "userName": "Test Lifter", "defaultRestSeconds": 90, "trackRPE": True},
        "plans": plans(),
        "sessions": sessions(),
        "bodyMetrics": [
            {"id": uid("body-1"), "date": "2026-09-01T07:00:00Z", "weightKg": 80.0, "source": "manual"},
            {"id": uid("body-2"), "date": "2026-10-01T07:00:00Z", "weightKg": 81.2, "source": "manual"},
        ],
        "customExercises": [],
        "hiddenExercises": [],
        "exerciseCatalog": [
            {"catalogID": cid, "name": name, "category": "strength", "muscleRaw": raw, "muscles": muscles,
             "equipment": equipment, "trackingRaw": tracking}
            for cid, name, muscles, raw, tracking, equipment in CATALOG],
        "effectiveLoadScales": [{"catalogID": "barbell-bench-press", "unit": "kg", "increment": 2.5,
                                 "source": "equipmentDefault"}],
        "effortScale": {"rpe": "bucketCode", "buckets": [
            {"effort": "easy", "rpe": 6, "meaning": "3+ left"}, {"effort": "solid", "rpe": 8, "meaning": "2 left"},
            {"effort": "hard", "rpe": 9, "meaning": "1 left"}, {"effort": "allOut", "rpe": 10, "meaning": "nothing left"}]},
    }


def decisions() -> dict:
    """One proposal accepted on 2026-09-19 and applied the next morning, not reverted."""
    return {
        "format": "gymtrack-coach-decisions", "version": 1,
        "decisions": [{
            "proposalID": uid("proposal-earlier"),
            "receivedAt": "2026-09-19T18:00:00Z", "decidedAt": "2026-09-19T18:05:00Z",
            "changes": [{"id": "c1", "decision": "accepted"}],
            "appliedAt": "2026-09-20T09:00:00Z",
            "before": [{"dayID": DAY_PUSH, "itemID": item_id("lateral-raise"),
                        "item": {"catalogID": "lateral-raise", "name": "Lateral Raise", "order": 1,
                                 "targetSets": 2, "targetRepsLow": 10, "targetRepsHigh": 15}}],
        }],
    }


def sample_proposal(plan_id: str = PLAN_ID) -> dict:
    """A valid proposal against the fixture, as the coach would draft it."""
    return {
        "format": "gymtrack-coach-proposal", "version": 1, "id": uid("proposal-now"),
        "createdAt": "2026-10-03T12:30:00Z", "planID": plan_id,
        "summary": "Shoulders have stalled for a month while chest keeps climbing.",
        "changes": [
            {"id": "c1", "kind": "setSets", "dayID": DAY_PUSH, "itemID": item_id("lateral-raise"),
             "expect": {"targetSets": 3}, "to": {"targetSets": 4},
             "reason": "Lateral raises have not moved in four weeks at easy-to-solid effort.",
             "lever": "volume",
             "evidence": [{"metric": "shoulders.weeklyFractionalSets", "value": 4.5},
                          {"metric": "ex.lateral-raise.plateau", "value": True}]},
            {"id": "c2", "kind": "setRepRange", "dayID": DAY_PULL, "itemID": item_id("pull-up"),
             "expect": {"targetRepsLow": 6, "targetRepsHigh": 10}, "to": {"targetRepsLow": 8, "targetRepsHigh": 12},
             "reason": "Every pull-up set is answered easy, so the range ends sets too far from failure.",
             "lever": "effort",
             "evidence": [{"metric": "ex.pull-up.easyShare", "value": 1.0}]},
        ],
        "advice": ["Push the last set of each lift closer to failure."],
    }


def write(path: Path) -> None:
    path.write_text(json.dumps(export(), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    import sys
    write(Path(sys.argv[1]))
