import copy
import json
import unittest
from pathlib import Path

import helpers  # noqa: F401  (puts coachlib on the path)
import fixture
from coachlib import stats


def compute(**kwargs):
    return stats.compute(fixture.export(), fixture.decisions(), **kwargs)


class Definitions(unittest.TestCase):
    def test_epley_is_the_apps_estimate_capped_at_twelve(self):
        self.assertEqual(stats.epley(100, 6), 120)
        self.assertEqual(stats.epley(100, 1), 100)
        self.assertAlmostEqual(stats.epley(100, 20), stats.epley(100, 12))
        self.assertAlmostEqual(stats.epley(100, 12), 140)

    def test_noise_is_typical_error_of_consecutive_differences(self):
        # diffs 2, -4, 3, -1, 3: sd 3.0496, over root two 2.1564
        self.assertAlmostEqual(stats.typical_error([100, 102, 98, 101, 100, 103]), 2.1564, places=3)

    def test_noise_is_unknown_below_six_exposures(self):
        self.assertIsNone(stats.typical_error([100, 102, 98, 101, 100]))

    def test_working_sets_drop_warmups_unfinished_and_continuations(self):
        session = {"sets": [
            {"catalogID": "x", "exerciseOrder": 0, "setIndex": 0, "isCompleted": True, "isWarmup": True},
            {"catalogID": "x", "exerciseOrder": 0, "setIndex": 1, "isCompleted": True},
            {"catalogID": "x", "exerciseOrder": 0, "setIndex": 2, "isCompleted": True, "continues": "drop"},
            {"catalogID": "x", "exerciseOrder": 0, "setIndex": 3, "isCompleted": False},
        ]}
        self.assertEqual([s["setIndex"] for s in stats.working_sets(session)], [1])

    def test_effort_answers_are_ordinal(self):
        self.assertEqual(stats.effort_ordinal({"effort": "allOut"}), 4)
        self.assertEqual(stats.effort_ordinal({"rpe": 9}), 3)
        self.assertIsNone(stats.effort_ordinal({"rpe": 7}))

    def test_muscle_names_are_slugged_like_the_app(self):
        self.assertEqual(stats.slug("Rear Delts"), "rearDelts")
        self.assertEqual(stats.slug("Upper Back"), "upperBack")
        self.assertEqual(stats.muscle_from_label("Side Delts"), "shoulders")


class FixtureNumbers(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.stats = compute()
        cls.ex = cls.stats["exercises"]
        cls.m = cls.stats["metrics"]

    def test_performance_kinds(self):
        self.assertEqual((self.ex["barbell-bench-press"]["kind"], self.ex["barbell-bench-press"]["performance"]), ("e1rm", 108.0))
        self.assertEqual((self.ex["seated-cable-row"]["kind"], self.ex["seated-cable-row"]["performance"]), ("reps", 17.0))
        self.assertEqual(self.ex["seated-cable-row"]["loadKg"], 50)
        self.assertEqual((self.ex["plank"]["kind"], self.ex["plank"]["performance"]), ("seconds", 60.0))
        self.assertEqual((self.ex["pull-up"]["kind"], self.ex["pull-up"]["performance"]), ("reps", 11.0))

    def test_best_set_with_the_mean_of_the_rest_beside_it(self):
        row = self.ex["barbell-bench-press"]["recent"][-1]
        self.assertEqual(row["value"], 108.0)
        # sets 90x6, 90x6, 90x5: the rest are 108 and 105
        self.assertAlmostEqual(row["restMean"], 106.5)

    def test_noise_for_the_bench_climb(self):
        # eight exposures, steps 3,0,3,0,3,0,3
        self.assertAlmostEqual(self.ex["barbell-bench-press"]["noise"], 1.13, places=2)
        self.assertTrue(self.ex["barbell-bench-press"]["beyondNoise"])

    def test_noise_needs_six_exposures_and_is_omitted_before(self):
        snap = fixture.export()
        snap["sessions"] = [s for s in snap["sessions"]
                            if not (s["title"] == "Push A" and s["startedAt"] < "2026-08-30")]
        result = stats.compute(snap)
        bench = result["exercises"]["barbell-bench-press"]
        self.assertEqual(bench["exposures"], 5)
        self.assertFalse(bench["noiseKnown"])
        self.assertNotIn("noise", bench)
        self.assertNotIn("ex.barbell-bench-press.noise", result["metrics"])
        self.assertNotIn("ex.barbell-bench-press.beyondNoise", result["metrics"])

    def test_climbing_lift_is_not_a_plateau(self):
        plateau = self.ex["barbell-bench-press"]["plateau"]
        self.assertFalse(plateau["isPlateau"])
        self.assertIn("best performance improved beyond noise", plateau["blockedBy"])

    def test_flat_lift_over_four_exposures_and_three_weeks_is_a_plateau(self):
        plateau = self.ex["lateral-raise"]["plateau"]
        self.assertTrue(plateau["isPlateau"])
        self.assertEqual(plateau["window"], {"exposures": 4, "days": 21.0})

    def test_pain_note_explains_a_flat_lift_so_it_is_not_a_plateau(self):
        plateau = self.ex["triceps-pushdown"]["plateau"]
        self.assertFalse(plateau["isPlateau"])
        self.assertTrue(any("pain" in reason for reason in plateau["blockedBy"]))
        self.assertEqual(self.ex["triceps-pushdown"]["painNotes90d"], 1)

    def test_short_history_is_never_a_plateau(self):
        snap = fixture.export()
        snap["sessions"] = [s for s in snap["sessions"] if s["startedAt"] > "2026-09-10"]
        result = stats.compute(snap)
        plateau = result["exercises"]["lateral-raise"]["plateau"]
        self.assertFalse(plateau["isPlateau"])

    def test_substitution_session_starts_no_series(self):
        leg = self.ex["leg-press"]
        self.assertEqual(leg["exposures"], 7)
        self.assertEqual(leg["nonComparableExposures"], 1)

    def test_a_changed_load_for_reps_starts_a_new_series(self):
        snap = fixture.export()
        for s in snap["sessions"]:
            if s["startedAt"] >= "2026-09-28":
                for st in s["sets"]:
                    if st["catalogID"] == "seated-cable-row":
                        st["weightKg"] = 55
        result = stats.compute(snap)
        row = result["exercises"]["seated-cable-row"]
        self.assertEqual(row["seriesKey"], "weightReps|reps@55")
        self.assertEqual(row["otherSeriesExposures"], 6)

    def test_effort_buckets(self):
        self.assertEqual(self.ex["pull-up"]["effortMean"], 1.0)
        self.assertEqual(self.ex["pull-up"]["easyShare"], 1.0)
        self.assertAlmostEqual(self.ex["barbell-bench-press"]["effortMean"], 2.33, places=2)
        self.assertEqual(self.ex["seated-cable-row"]["effortBasis"], "over12Reps")
        self.assertEqual(self.ex["barbell-bench-press"]["effortBasis"], "upTo12Reps")

    def test_weekly_fractional_sets(self):
        self.assertEqual(self.m["chest.weeklyFractionalSets"], 3.0)
        # bench 3 x 0.5 + lateral raise 3 x 1
        self.assertEqual(self.m["shoulders.weeklyFractionalSets"], 4.5)
        self.assertEqual(self.m["triceps.weeklyFractionalSets"], 4.5)
        # pull day skipped one of the four complete weeks: (6 + 0 + 6 + 6) / 4
        self.assertEqual(self.m["lats.weeklyFractionalSets"], 4.5)
        self.assertAlmostEqual(self.m["upperBack.weeklyFractionalSets"], 1.125, places=2)
        self.assertEqual(self.m["lats.lastWeekFractionalSets"], 6.0)
        self.assertEqual(self.m["lats.maxSessionFractionalSets"], 6.0)
        self.assertEqual(self.stats["volumeWeeks"], ["2026-08-31", "2026-09-07", "2026-09-14", "2026-09-21"])

    def test_a_late_sunday_session_counts_in_the_lifters_monday(self):
        snap = fixture.export()
        snap["sessions"] = [{"id": "s", "title": "Push A", "planName": "x", "startedAt": "2026-09-27T22:30:00Z",
                             "endedAt": "2026-09-27T23:30:00Z",
                             "sets": [{"catalogID": "barbell-bench-press", "exerciseName": "x", "exerciseOrder": 0,
                                       "setIndex": 0, "weightKg": 80, "reps": 8, "isCompleted": True}]}]
        result = stats.compute(snap)
        self.assertEqual(result["metrics"]["chest.thisWeekFractionalSets"], 1.0)

    def test_adherence(self):
        self.assertEqual(self.m["adherence.sessionsFromPlan"], 11)
        self.assertEqual(self.m["adherence.slotSetsShare"], 1.0)
        # 62 of 66 sets reached the lower target: the five-rep third bench set missed, four times
        self.assertAlmostEqual(self.m["adherence.repTargetHitShare"], 62 / 66, places=2)
        # three days due, trained 3, 2, 3, 3 of the last four complete weeks
        self.assertAlmostEqual(self.m["adherence.weekDaysTrainedShare"], 11 / 12, places=2)

    def test_notes_and_tags_including_pain(self):
        notes = self.stats["notes"]
        self.assertEqual(notes[0]["tags"], ["pain"])
        self.assertEqual(notes[0]["catalogID"], "triceps-pushdown")
        self.assertEqual({tag for n in notes for tag in n["tags"]}, {"pain", "feltFlat", "substitution"})
        self.assertEqual(self.m["notes.painEntries90d"], 1)

    def test_body_weight(self):
        self.assertEqual(self.m["body.latestKg"], 81.2)
        self.assertEqual(self.m["body.change28dKg"], 1.2)

    def test_priority_muscles_and_tape_come_from_the_profile(self):
        text = "Priority muscles: side delts, upper chest\n\n- 2026-09-01: arm 36 cm, waist 82 cm\n"
        result = compute(profile_text=text)
        self.assertEqual(result["profile"]["priorityMuscles"], ["shoulders", "chest"])
        self.assertEqual(result["profile"]["tape"], [{"date": "2026-09-01", "text": "arm 36 cm, waist 82 cm"}])
        self.assertIn("| shoulders | 4.5 | 4.5 | 4.5 | 4.5 | yes |", stats.render_markdown(result))

    def test_a_priority_muscle_with_no_work_shows_zero_not_nothing(self):
        result = compute(profile_text="Priority muscles: rear delts")
        self.assertEqual(result["metrics"]["rearDelts.weeklyFractionalSets"], 0.0)

    def test_no_null_values_in_metrics(self):
        self.assertTrue(all(v is not None for v in self.m.values()))


class PreviousReviewAndDecisions(unittest.TestCase):
    def test_plan_diff_against_the_previous_export(self):
        previous = fixture.export()
        push = previous["plans"][0]["days"][0]
        push["items"][1]["targetSets"] = 2
        push["items"].append({"id": "X", "catalogID": "cable-fly", "name": "Cable Fly", "order": 9, "targetSets": 2})
        result = compute(previous=previous)
        diff = result["planDiff"]
        self.assertEqual(diff["changed"], [{"day": "Push A", "name": "Lateral Raise", "field": "targetSets",
                                            "from": 2, "to": 3}])
        self.assertEqual(diff["removed"], [{"day": "Push A", "name": "Cable Fly"}])
        self.assertIn("targetSets 2 to 3", stats.render_markdown(result))

    def test_no_previous_review_means_no_diff(self):
        self.assertEqual(compute()["planDiff"], {"available": False})

    def test_a_replaced_plan_is_said_not_diffed(self):
        previous = fixture.export()
        previous["plans"][0]["id"] = fixture.OLD_PLAN_ID
        self.assertIn("planReplaced", compute(previous=previous)["planDiff"])

    def test_anything_to_review_counts_since_the_previous_export(self):
        review = compute(previous_exported_at="2026-09-27T00:00:00Z")["review"]
        self.assertEqual(review["sessionsSinceLastReview"], 3)
        self.assertEqual(review["exposuresSinceLastReview"], 7)
        self.assertEqual(review["painNotesSinceLastReview"], 1)
        self.assertIn("3 sessions", review["summary"])

    def test_nothing_new_says_keep_the_plan(self):
        review = compute(previous_exported_at="2026-10-03T00:00:00Z")["review"]
        self.assertEqual(review["sessionsSinceLastReview"], 0)
        self.assertIn("keep the plan", review["summary"])

    def test_a_proposal_still_waiting_is_flagged(self):
        decisions = fixture.decisions()
        decisions["decisions"].append({"proposalID": "P", "receivedAt": "2026-10-01T00:00:00Z", "changes": []})
        result = stats.compute(fixture.export(), decisions, previous_exported_at="2026-09-27T00:00:00Z")
        self.assertTrue(result["review"]["proposalAwaitingDecision"])
        self.assertIn("waiting for a decision", result["review"]["summary"])

    def test_outcome_of_the_last_applied_decision(self):
        outcome = compute()["lastDecision"]
        item = outcome["items"]["lateral-raise"]
        self.assertFalse(outcome["reverted"])
        self.assertEqual(item["exposuresSince"], 2)
        self.assertEqual(item["performanceBefore"], 14.0)
        self.assertEqual(item["performanceAfterBest"], 14.0)
        self.assertEqual(item["delta"], 0.0)
        self.assertFalse(item["beyondNoise"])

    def test_a_reverted_decision_says_so(self):
        decisions = fixture.decisions()
        decisions["decisions"][0]["revertedAt"] = "2026-09-25T09:00:00Z"
        result = stats.compute(fixture.export(), decisions)
        self.assertTrue(result["lastDecision"]["reverted"])
        self.assertTrue(result["metrics"]["lastDecision.reverted"])
        self.assertIn("later reverted", stats.render_markdown(result))

    def test_no_applied_decision_means_no_outcome(self):
        self.assertIsNone(stats.compute(fixture.export(), {"decisions": []})["lastDecision"])


class Output(unittest.TestCase):
    def test_markdown_documents_the_metric_names(self):
        md = stats.render_markdown(compute())
        self.assertIn("<muscle>.weeklyFractionalSets", md)
        self.assertIn("ex.<catalogID>.", md)
        self.assertIn("## Anything to review?", md)

    def test_committed_fixture_matches_the_builder(self):
        committed = json.loads((Path(__file__).parent / "fixtures" / "export.json").read_text())
        self.assertEqual(committed, fixture.export())


if __name__ == "__main__":
    unittest.main()
