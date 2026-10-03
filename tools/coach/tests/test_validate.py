import copy
import unittest

import helpers  # noqa: F401
import fixture
from coachlib import stats
from coachlib.validate import validate

SNAPSHOT = fixture.export()
METRICS = stats.compute(SNAPSHOT, fixture.decisions())["metrics"]
BENCH, LATERAL, PUSHDOWN = (fixture.item_id(c) for c in ("barbell-bench-press", "lateral-raise", "triceps-pushdown"))
PULL_UP, PLANK, LEG_PRESS = (fixture.item_id(c) for c in ("pull-up", "plank", "leg-press"))


def check(proposal, **kwargs):
    return validate(proposal, SNAPSHOT, kwargs.pop("metrics", METRICS), **kwargs)


def change(**fields):
    base = {"id": "c1", "kind": "setSets", "dayID": fixture.DAY_PUSH, "itemID": LATERAL,
            "expect": {"targetSets": 3}, "to": {"targetSets": 4}, "reason": "Plain reason.", "lever": "volume",
            "evidence": [{"metric": "shoulders.weeklyFractionalSets", "value": 4.5}]}
    base.update(fields)
    return {k: v for k, v in base.items() if v is not None}


def proposal(*changes, **top):
    out = fixture.sample_proposal()
    out["changes"] = list(changes)
    out.update(top)
    return {k: v for k, v in out.items() if v is not None}


class Valid(unittest.TestCase):
    def test_the_sample_proposal_passes(self):
        self.assertEqual(check(fixture.sample_proposal()), [])

    def test_without_stats_evidence_is_only_shape_checked(self):
        self.assertEqual(validate(fixture.sample_proposal(), SNAPSHOT, None), [])

    def test_review_and_reply_pass_when_allowed(self):
        p = fixture.sample_proposal()
        p["changes"][0]["review"] = {"verdict": "doubt", "score": 2, "note": "n", "disputed": True}
        p["changes"][0]["reply"] = {"stance": "defended", "text": "because"}
        self.assertEqual(check(p, allow_review=True, allow_reply=True), [])

    def test_advice_alone_is_a_valid_proposal(self):
        self.assertEqual(check(proposal(advice=["Train closer to failure."])), [])

    def test_every_kind_has_a_valid_form(self):
        legs_extra = proposal(
            change(id="a", kind="setRest", itemID=BENCH, expect={"restSeconds": 150}, to={"restSeconds": 180}, lever="rest"),
            change(id="b", kind="substitute", itemID=PUSHDOWN, expect={"catalogID": "triceps-pushdown"},
                   to={"catalogID": "incline-dumbbell-press", "name": "Incline Dumbbell Press"}, lever="exerciseChoice"),
            change(id="c", kind="addSlot", itemID=None, expect={},
                   to={"catalogID": "incline-dumbbell-press", "name": "Incline Dumbbell Press", "targetSets": 3,
                       "targetRepsLow": 8, "targetRepsHigh": 12, "restSeconds": 90, "afterItemID": BENCH}))
        self.assertEqual(check(legs_extra), [])
        remove = proposal(change(id="r", kind="removeSlot", itemID=PUSHDOWN, expect={"catalogID": "triceps-pushdown"},
                                 to={}, lever="pain"))
        self.assertEqual(check(remove), [])


# (description, proposal, expected fragment of a problem)
CASES = [
    ("wrong format", proposal(change(), format="nope"), "format must be"),
    ("wrong version", proposal(change(), version=2), "version must be 1"),
    ("id not a uuid", proposal(change(), id="abc"), "id must be a UUID"),
    ("bad createdAt", proposal(change(), createdAt="yesterday"), "createdAt must be"),
    ("empty summary", proposal(change(), summary=" "), "summary must be"),
    ("bad advice", proposal(change(), advice=[1]), "advice must be"),
    ("plan is not the active one", proposal(change(), planID=fixture.OLD_PLAN_ID), "planID must be the active plan"),
    ("four changes", proposal(*[change(id=f"c{i}", itemID=item, expect=e, to=t, kind=k, dayID=d)
                               for i, (item, e, t, k, d) in enumerate([
                                   (LATERAL, {"targetSets": 3}, {"targetSets": 4}, "setSets", fixture.DAY_PUSH),
                                   (BENCH, {"targetSets": 3}, {"targetSets": 4}, "setSets", fixture.DAY_PUSH),
                                   (PUSHDOWN, {"targetSets": 3}, {"targetSets": 4}, "setSets", fixture.DAY_PUSH),
                                   (PULL_UP, {"targetSets": 3}, {"targetSets": 4}, "setSets", fixture.DAY_PULL)])]),
     "at most 3 changes"),
    ("no changes and no advice", proposal(advice=None), "no changes and no advice"),
    ("duplicate change id", proposal(change(), change(itemID=BENCH)), "duplicate change id"),
    ("two changes on one item", proposal(change(), change(id="c2", kind="setRest", expect={"restSeconds": 90},
                                                          to={"restSeconds": 120}, lever="rest")),
     "more than one change for itemID"),
    ("unknown day", proposal(change(dayID=fixture.uid("nope"))), "dayID is not a day"),
    ("item in another day", proposal(change(dayID=fixture.DAY_PULL)), "itemID is not an item of that day"),
    ("unknown item", proposal(change(itemID=fixture.uid("nope"))), "itemID is not an item"),
    ("stale expect", proposal(change(expect={"targetSets": 4}, to={"targetSets": 5})), "stale"),
    ("setSets by two", proposal(change(to={"targetSets": 5})), "exactly one set"),
    ("setSets to zero", proposal(change(expect={"targetSets": 3}, to={"targetSets": 0})), "exactly one set"),
    ("kind unknown", proposal(change(kind="setWeight")), "kind must be one of"),
    ("a load in to", proposal(change(to={"targetSets": 4, "targetWeightKg": 12})), "loads belong to the phone"),
    ("extra key in expect", proposal(change(expect={"targetSets": 3, "restSeconds": 90})), "not part of a setSets change"),
    ("missing key in to", proposal(change(to={})), "to.targetSets is missing"),
    ("non-integer", proposal(change(to={"targetSets": 4.0 + 0.5})), "whole number"),
    ("reason missing", proposal(change(reason=None)), "reason must be"),
    ("reason too long", proposal(change(reason="x" * 300)), "reason is 300 characters"),
    ("lever unknown", proposal(change(lever="frequency")), "lever must be one of"),
    ("no evidence", proposal(change(evidence=[])), "evidence must list"),
    ("evidence malformed", proposal(change(evidence=[{"metric": "x"}])), "needs a metric and a value"),
    ("unknown metric", proposal(change(evidence=[{"metric": "chest.bogus", "value": 1}])), "is not a key in stats.json"),
    ("evidence value off", proposal(change(evidence=[{"metric": "shoulders.weeklyFractionalSets", "value": 9}])),
     "stats.json has 4.5"),
    ("review in a draft", proposal(change(review={"verdict": "agree", "score": 4, "note": "n", "disputed": False})),
     "review is written by `coach submit`"),
    ("reply in a draft", proposal(change(reply={"stance": "defended", "text": "t"})), "reply belongs to the second round"),
    ("null value", proposal(change(reason="ok"), summary=None, advice=None) | {"summary": None}, "is null"),
    ("rep range inverted", proposal(change(kind="setRepRange", itemID=BENCH, expect={"targetRepsLow": 6, "targetRepsHigh": 10},
                                           to={"targetRepsLow": 12, "targetRepsHigh": 8}, lever="repRange")),
     "1 <= low <= high <= 30"),
    ("rep range over thirty", proposal(change(kind="setRepRange", itemID=BENCH, expect={"targetRepsLow": 6, "targetRepsHigh": 10},
                                              to={"targetRepsLow": 6, "targetRepsHigh": 31}, lever="repRange")),
     "1 <= low <= high <= 30"),
    ("rep range on a timed slot", proposal(change(kind="setRepRange", dayID=fixture.DAY_PULL, itemID=PLANK,
                                                  expect={"targetRepsLow": 0, "targetRepsHigh": 0},
                                                  to={"targetRepsLow": 8, "targetRepsHigh": 12}, lever="repRange")),
     "timed slot has no rep range"),
    ("rest too short", proposal(change(kind="setRest", itemID=BENCH, expect={"restSeconds": 150}, to={"restSeconds": 29},
                                       lever="rest")), "restSeconds must be 30 to 600"),
    ("rest too long", proposal(change(kind="setRest", itemID=BENCH, expect={"restSeconds": 150}, to={"restSeconds": 601},
                                      lever="rest")), "restSeconds must be 30 to 600"),
    ("rest expect uses the app default when the slot has none",
     proposal(change(kind="setRest", expect={"restSeconds": 75}, to={"restSeconds": 100}, lever="rest")), "stale"),
    ("substitute unknown exercise", proposal(change(kind="substitute", expect={"catalogID": "lateral-raise"},
                                                    to={"catalogID": "nope", "name": "Nope"}, lever="exerciseChoice")),
     "not in the exported catalog"),
    ("substitute a timed exercise", proposal(change(kind="substitute", expect={"catalogID": "lateral-raise"},
                                                    to={"catalogID": "plank", "name": "Plank"}, lever="exerciseChoice")),
     "is timed"),
    ("substitute the same exercise", proposal(change(kind="substitute", expect={"catalogID": "lateral-raise"},
                                                     to={"catalogID": "lateral-raise", "name": "Lateral Raise"},
                                                     lever="exerciseChoice")), "same exercise"),
    ("substitute with the wrong name", proposal(change(kind="substitute", expect={"catalogID": "lateral-raise"},
                                                       to={"catalogID": "incline-dumbbell-press", "name": "Press"},
                                                       lever="exerciseChoice")), "must be the catalog name"),
    ("substitute out of a timed slot", proposal(change(kind="substitute", dayID=fixture.DAY_PULL, itemID=PLANK,
                                                       expect={"catalogID": "plank"},
                                                       to={"catalogID": "lateral-raise", "name": "Lateral Raise"},
                                                       lever="exerciseChoice")), "slot is timed"),
    ("addSlot to a rest day", proposal(change(kind="addSlot", dayID=fixture.DAY_REST, itemID=None, expect={},
                                              to={"catalogID": "lateral-raise", "name": "Lateral Raise", "targetSets": 3,
                                                  "targetRepsLow": 8, "targetRepsHigh": 12, "restSeconds": 90})),
     "rest day"),
    ("addSlot with an itemID", proposal(change(kind="addSlot", expect={},
                                               to={"catalogID": "lateral-raise", "name": "Lateral Raise", "targetSets": 3,
                                                   "targetRepsLow": 8, "targetRepsHigh": 12, "restSeconds": 90})),
     "addSlot takes dayID"),
    ("addSlot over ten sets", proposal(change(kind="addSlot", itemID=None, expect={},
                                              to={"catalogID": "lateral-raise", "name": "Lateral Raise", "targetSets": 11,
                                                  "targetRepsLow": 8, "targetRepsHigh": 12, "restSeconds": 90})),
     "targetSets must be 1 to 10"),
    ("addSlot with a non-empty expect", proposal(change(kind="addSlot", itemID=None, expect={"targetSets": 3},
                                                        to={"catalogID": "lateral-raise", "name": "Lateral Raise",
                                                            "targetSets": 3, "targetRepsLow": 8, "targetRepsHigh": 12,
                                                            "restSeconds": 90})), "expect.targetSets is not part"),
    ("addSlot after an item of another day", proposal(change(kind="addSlot", itemID=None, expect={},
                                                             to={"catalogID": "lateral-raise", "name": "Lateral Raise",
                                                                 "targetSets": 3, "targetRepsLow": 8,
                                                                 "targetRepsHigh": 12, "restSeconds": 90,
                                                                 "afterItemID": PULL_UP})), "afterItemID is not an item"),
    ("removeSlot of a day's only item", proposal(change(kind="removeSlot", dayID=fixture.DAY_LEGS, itemID=LEG_PRESS,
                                                        expect={"catalogID": "leg-press"}, to={}, lever="pain")),
     "no item"),
    ("removeSlot with a wrong catalogID", proposal(change(kind="removeSlot", itemID=PUSHDOWN,
                                                          expect={"catalogID": "lateral-raise"}, to={}, lever="pain")),
     "stale"),
    ("removeSlot with a non-empty to", proposal(change(kind="removeSlot", itemID=PUSHDOWN,
                                                       expect={"catalogID": "triceps-pushdown"},
                                                       to={"targetSets": 1}, lever="pain")), "not part of a removeSlot"),
]


class EveryRule(unittest.TestCase):
    def test_each_rule_is_enforced(self):
        for name, bad, fragment in CASES:
            with self.subTest(name):
                problems = check(bad)
                self.assertTrue(any(fragment in p for p in problems), f"{fragment!r} not in {problems}")

    def test_removing_every_item_of_a_day_with_two_removals(self):
        snap = copy.deepcopy(SNAPSHOT)
        snap["plans"][0]["days"][2]["items"].append(snap["plans"][0]["days"][2]["items"][0] | {"id": "AAAAAAAA-0000-4000-8000-000000000001", "catalogID": "lateral-raise"})
        bad = proposal(
            change(id="a", kind="removeSlot", dayID=fixture.DAY_LEGS, itemID=LEG_PRESS, expect={"catalogID": "leg-press"}, to={}, lever="pain"),
            change(id="b", kind="removeSlot", dayID=fixture.DAY_LEGS, itemID="AAAAAAAA-0000-4000-8000-000000000001",
                   expect={"catalogID": "lateral-raise"}, to={}, lever="pain"))
        problems = validate(bad, snap, None)
        self.assertTrue(any("no item" in p for p in problems), problems)

    def test_invalid_review_and_reply_are_caught_when_allowed(self):
        p = fixture.sample_proposal()
        p["changes"][0]["review"] = {"verdict": "maybe", "score": 7, "note": 3, "disputed": "yes"}
        p["changes"][0]["reply"] = {"stance": "ignored", "text": ""}
        problems = check(p, allow_review=True, allow_reply=True)
        for fragment in ("review.verdict", "review.score", "review.note", "review.disputed", "reply.stance", "reply.text"):
            self.assertTrue(any(fragment in x for x in problems), (fragment, problems))

    def test_a_snapshot_without_plan_ids_is_refused_clearly(self):
        snap = copy.deepcopy(SNAPSHOT)
        for plan in snap["plans"]:
            del plan["id"]
        problems = validate(fixture.sample_proposal(), snap, None)
        self.assertTrue(any("no plan ids" in p for p in problems), problems)

    def test_uuid_case_does_not_matter(self):
        p = fixture.sample_proposal()
        p["planID"] = p["planID"].lower()
        p["changes"][0]["itemID"] = p["changes"][0]["itemID"].lower()
        self.assertEqual(check(p), [])

    def test_all_problems_are_reported_at_once(self):
        bad = proposal(change(lever="nope", reason=None), format="x")
        self.assertGreaterEqual(len(check(bad)), 3)


if __name__ == "__main__":
    unittest.main()
