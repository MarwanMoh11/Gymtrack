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

    def test_weeks_before_the_plan_was_first_trained_are_not_missed_days(self):
        snap = fixture.export()
        for session in snap["sessions"]:
            if session["startedAt"] < "2026-09-14":
                session.pop("planDayID", None)
        m = stats.compute(snap)["metrics"]
        self.assertEqual(m["adherence.weeksMeasured"], 2)
        self.assertAlmostEqual(m["adherence.weekDaysTrainedShare"], 6 / 6, places=2)

    def test_a_session_logged_afterwards_is_finished_without_an_end_time(self):
        snap = fixture.export()
        last = max(snap["sessions"], key=lambda s: s["startedAt"])
        del last["endedAt"]
        self.assertEqual(len(stats.finished_sessions(snap)), len(snap["sessions"]) - 1)
        last["loggedAfterwards"] = True
        self.assertEqual(len(stats.finished_sessions(snap)), len(snap["sessions"]))

    def test_planned_against_done_reads_the_day_as_it_stood(self):
        snap = fixture.export()
        session = max((s for s in snap["sessions"] if s.get("planDayID")), key=lambda s: s["startedAt"])
        worked = list(dict.fromkeys(s["catalogID"] for s in stats.working_sets(session)))
        names = {s["catalogID"]: s["exerciseName"] for s in session["sets"]}
        session["plannedItems"] = [{"catalogID": cid, "name": names[cid], "order": i, "targetSets": 1}
                                   for i, cid in enumerate(worked[1:])]
        session["plannedItems"].append({"catalogID": "seated-leg-curl-machine", "name": "Seated Leg Curl",
                                        "order": 9, "targetSets": 2})
        result = stats.compute(snap)
        self.assertEqual(result["metrics"]["adherence.sessionsWithPlanRecord"], 1)
        [row] = result["plannedVsDone"]
        self.assertEqual(row["skipped"], ["Seated Leg Curl"])
        self.assertEqual(row["notPlanned"], [names[worked[0]]])
        text = stats.render_markdown(result)
        self.assertIn("skipped Seated Leg Curl; not in the plan that day: " + names[worked[0]], text)

    def test_without_a_plan_record_the_coach_is_told_to_ask(self):
        result = compute()
        self.assertEqual(result["metrics"]["adherence.sessionsWithPlanRecord"], 0)
        self.assertEqual(result["plannedVsDone"], [])
        self.assertIn("cannot be told from a plan edit. Ask.", stats.render_markdown(result))

    def test_recent_sets_show_each_plan_lift_set_by_set(self):
        result = compute()
        bench = result["recentSets"]["barbell-bench-press"]
        self.assertLessEqual(len(bench), 4)
        self.assertEqual([r["date"] for r in bench], sorted(r["date"] for r in bench))
        self.assertRegex(bench[-1]["sets"][0], r"^\d+(\.\d)?x\d+( (easy|solid|hard|allOut))?$")
        self.assertIn("## Recent sets", stats.render_markdown(result))

    def test_notes_and_tags_including_pain(self):
        notes = self.stats["notes"]
        self.assertEqual(notes[0]["tags"], ["pain"])
        self.assertEqual(notes[0]["catalogID"], "triceps-pushdown")
        self.assertEqual({tag for n in notes for tag in n["tags"]}, {"pain", "feltFlat", "substitution"})
        self.assertEqual(self.m["notes.painEntries90d"], 1)

    def test_body_weight(self):
        self.assertEqual(self.m["body.latestKg"], 81.2)
        self.assertEqual(self.m["body.change28dKg"], 1.2)

    def test_priority_muscles_come_from_the_profile_and_tape_lines_there_are_ignored(self):
        text = "Priority muscles: side delts, upper chest\n\n- 2026-09-01: arm 99 cm, waist 82 cm\n"
        result = compute(profile_text=text)
        self.assertEqual(result["profile"]["priorityMuscles"], ["shoulders", "chest"])
        self.assertNotIn("tape", result["profile"])
        self.assertIn("| shoulders | 4.5 | 4.5 | 4.5 | 4.5 | yes |", stats.render_markdown(result))
        self.assertEqual(result["metrics"]["tape.arm.latestCm"], 37.0)
        self.assertNotIn("99 cm", stats.render_markdown(result))

    def test_tape_metrics_compare_each_part_with_its_own_previous_check_in(self):
        m = self.m
        self.assertEqual(m["tape.arm.latestCm"], 37.0)
        self.assertEqual(m["tape.arm.changeCm"], 0.5)
        self.assertEqual(m["tape.arm.daysSincePrevious"], 16)
        # Waist skipped the 15 Sep check-in, so it compares with 1 Sep.
        self.assertEqual(m["tape.waist.latestCm"], 83.0)
        self.assertEqual(m["tape.waist.changeCm"], -1.0)
        self.assertEqual(m["tape.waist.daysSincePrevious"], 30)

    def test_a_tape_part_measured_once_has_no_change_and_one_never_measured_has_no_key(self):
        m = self.m
        self.assertEqual(m["tape.chest.latestCm"], 101.0)
        self.assertEqual(m["tape.thigh.latestCm"], 58.0)
        for key in ("tape.chest.changeCm", "tape.chest.daysSincePrevious", "tape.thigh.changeCm"):
            self.assertNotIn(key, m)
        self.assertFalse([k for k in m if k.startswith("tape.shoulders")])
        self.assertNotIn(None, m.values())

    def test_no_check_ins_means_no_tape_keys_and_a_quiet_section(self):
        snapshot = fixture.export()
        del snapshot["bodyMeasurements"]
        result = stats.compute(snapshot, fixture.decisions())
        self.assertFalse([k for k in result["metrics"] if k.startswith("tape.") or ".tape." in k])
        text = stats.render_markdown(result)
        self.assertIn("## Measurements", text)
        self.assertIn("No tape check-ins logged", text)

    def test_a_zero_or_missing_girth_is_not_a_measurement(self):
        snapshot = fixture.export()
        snapshot["bodyMeasurements"].append({"id": "x", "date": "2026-10-02T07:00:00Z", "waistCm": 0,
                                             "armCm": None, "chestCm": "wide"})
        result = stats.compute(snapshot, fixture.decisions())
        self.assertEqual(result["metrics"]["tape.waist.latestCm"], 83.0)
        self.assertEqual(result["tape"]["checkIns"], 3)

    def test_measurements_section_lists_the_last_four_check_ins_oldest_first(self):
        snapshot = fixture.export()
        snapshot["bodyMeasurements"] = [
            {"id": str(n), "date": f"2026-09-{n:02d}T07:00:00Z", "waistCm": 80.0 + n} for n in (3, 5, 7, 9, 11)
        ]
        text = stats.render_markdown(stats.compute(snapshot, fixture.decisions()))
        section = text.split("## Measurements")[1].split("\n## ")[0]
        self.assertNotIn("2026-09-03", section)
        rows = [line for line in section.splitlines() if line.startswith("| 2026-")]
        self.assertEqual([r.split("|")[1].strip() for r in rows],
                         ["2026-09-05", "2026-09-07", "2026-09-09", "2026-09-11"])
        self.assertIn("| 2026-09-05 | - | - | - | 85 | - |", section)

    def test_the_section_says_when_the_last_check_in_is_over_four_weeks_old(self):
        snapshot = fixture.export()
        snapshot["bodyMeasurements"] = snapshot["bodyMeasurements"][:1]
        text = stats.render_markdown(stats.compute(snapshot, fixture.decisions()))
        self.assertIn("none in the last four weeks", text)
        self.assertNotIn("none in the last four weeks", stats.render_markdown(compute()))

    def test_the_last_applied_proposal_reports_each_parts_change_across_the_decision(self):
        decision = compute()["lastDecision"]
        # Applied 20 Sep: arm 36.5 (15 Sep) to 37 (1 Oct); waist 84 to 83.
        self.assertEqual(decision["tape"]["arm"]["changeCm"], 0.5)
        self.assertEqual(decision["tape"]["waist"]["changeCm"], -1.0)
        self.assertEqual(decision["tape"]["waist"]["beforeDate"], "2026-09-01T07:00:00Z")
        # Chest has nothing after the decision and thigh nothing before it.
        self.assertEqual(set(decision["tape"]), {"arm", "waist"})
        m = compute()["metrics"]
        self.assertEqual(m["lastDecision.tape.waist.changeCm"], -1.0)
        self.assertNotIn("lastDecision.tape.chest.changeCm", m)
        text = stats.render_markdown(compute())
        self.assertIn("Tape, waist: 84 cm on 2026-09-01", text)
        self.assertIn("-1.0 cm", text)

    def test_a_decision_with_no_check_in_on_both_sides_has_no_tape(self):
        snapshot = fixture.export()
        snapshot["bodyMeasurements"] = snapshot["bodyMeasurements"][:2]
        self.assertNotIn("tape", stats.compute(snapshot, fixture.decisions())["lastDecision"])

    def test_a_check_in_at_the_moment_of_applying_counts_as_before(self):
        snapshot = fixture.export()
        snapshot["bodyMeasurements"] = [
            {"id": "a", "date": "2026-09-20T09:00:00Z", "waistCm": 84.0},
            {"id": "b", "date": "2026-10-01T07:00:00Z", "waistCm": 83.0},
        ]
        decision = stats.compute(snapshot, fixture.decisions())["lastDecision"]
        self.assertEqual(decision["tape"]["waist"]["changeCm"], -1.0)

    def test_the_blank_template_names_no_priority_muscles(self):
        from coachlib import commands
        self.assertEqual(stats.parse_profile(commands.PROFILE_TEMPLATE)["priorityLabels"], [])

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
