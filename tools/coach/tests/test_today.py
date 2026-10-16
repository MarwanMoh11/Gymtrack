import json
import unittest
from datetime import date, datetime, timezone

import helpers
import fixture
from coachlib import stats, today
from coachlib.util import CoachError

PUSH_7 = date(2026, 9, 28)   # Monday of the last week: bench 90 kg, a pain note on pushdowns
PUSH_6 = date(2026, 9, 21)
LEGS_3 = date(2026, 9, 4)    # the leg press session tagged as a substitution
LEGS_7 = date(2026, 10, 2)   # the latest workout in the fixture
EXPORTED = datetime(2026, 10, 3, 12, tzinfo=timezone.utc)


def session_on(export, day, title):
    return next(s for s in export["sessions"] if s["startedAt"].startswith(day.isoformat()) and s["title"] == title)


def exercise(result, name):
    return next(e for s in result["sessions"] for e in s["exercises"] if e["name"] == name)


class DayChoice(unittest.TestCase):
    def test_default_is_the_latest_training_day_with_a_finished_workout(self):
        result = today.compute_day(fixture.export(), now=EXPORTED)
        self.assertEqual(result["day"], LEGS_7.isoformat())
        self.assertFalse(result["isToday"])
        self.assertEqual(result["previousDay"], "2026-09-30")
        self.assertEqual(result["daysSincePrevious"], 2)

    def test_half_past_midnight_is_still_the_evening_before(self):
        # 00:30 in Cairo on the 3rd is training day the 2nd, as on the phone.
        result = today.compute_day(fixture.export(), now=datetime(2026, 10, 2, 21, 30, tzinfo=timezone.utc))
        self.assertTrue(result["isToday"])

    def test_a_day_without_a_workout_names_the_latest_one(self):
        with self.assertRaises(CoachError) as caught:
            today.compute_day(fixture.export(), date(2026, 9, 29), now=EXPORTED)
        self.assertIn(LEGS_7.isoformat(), str(caught.exception))

    def test_an_unfinished_session_on_the_day_is_flagged(self):
        export = fixture.export()
        unfinished = dict(session_on(export, LEGS_7, "Legs"), id=fixture.uid("unfinished"))
        unfinished.pop("endedAt")
        export["sessions"].append(unfinished)
        result = today.compute_day(export, LEGS_7, now=EXPORTED)
        self.assertTrue(result["unfinishedSession"])
        self.assertEqual(len(result["sessions"]), 1)


class AgainstHistory(unittest.TestCase):
    def test_compares_with_the_previous_comparable_exposure_and_the_lifters_noise(self):
        bench = exercise(today.compute_day(fixture.export(), PUSH_7, now=EXPORTED), "Barbell Bench Press")
        h = bench["history"]
        self.assertEqual((h["kind"], h["value"], h["previous"], h["delta"]), ("e1rm", 108.0, 105.0, 3.0))
        self.assertEqual(h["bestBefore"], 105.0)
        self.assertTrue(h["newBest"])
        self.assertEqual(h["exposures"], 8)
        noise = stats.typical_error([96, 99, 99, 102, 102, 105, 105, 108])
        self.assertAlmostEqual(h["noise"], round(noise, 2))
        self.assertEqual(h["beyondNoise"], 3.0 > noise)
        self.assertEqual(h["lastTime"]["date"], PUSH_6.isoformat())

    def test_a_past_day_never_sees_the_sessions_after_it(self):
        h = exercise(today.compute_day(fixture.export(), PUSH_6, now=EXPORTED), "Barbell Bench Press")["history"]
        self.assertEqual((h["value"], h["previous"], h["delta"], h["exposures"]), (105.0, 105.0, 0.0, 7))
        self.assertFalse(h["newBest"])

    def test_noise_stays_unknown_below_six_exposures(self):
        h = exercise(today.compute_day(fixture.export(), date(2026, 8, 31), now=EXPORTED),
                     "Barbell Bench Press")["history"]
        self.assertEqual(h["exposures"], 4)
        self.assertNotIn("noise", h)
        self.assertNotIn("beyondNoise", h)

    def test_a_substitution_is_not_compared(self):
        h = exercise(today.compute_day(fixture.export(), LEGS_3, now=EXPORTED), "Leg Press")["history"]
        self.assertFalse(h["comparable"])
        self.assertNotIn("delta", h)

    def test_rep_targets_and_effort_answers(self):
        bench = exercise(today.compute_day(fixture.export(), PUSH_7, now=EXPORTED), "Barbell Bench Press")
        self.assertEqual(bench["repTargets"], {"aimed": 3, "below": 1, "atTop": 0, "inRange": 2})
        self.assertEqual(bench["effortAnswered"], 3)
        self.assertAlmostEqual(bench["effortMean"], round((2 + 2 + 3) / 3, 2))

    def test_the_exercise_note_and_its_tags_travel(self):
        pushdown = exercise(today.compute_day(fixture.export(), PUSH_7, now=EXPORTED), "Triceps Pushdown")
        self.assertEqual(pushdown["notes"], [{"text": "Right elbow twinge on the last set", "tags": ["pain"]}])


class AgainstThePlan(unittest.TestCase):
    def test_skipped_short_and_unplanned_work(self):
        export = fixture.export()
        session = session_on(export, PUSH_7, "Push A")
        session["sets"] = [s for s in session["sets"] if s["catalogID"] != "lateral-raise"
                           and not (s["catalogID"] == "triceps-pushdown" and s["setIndex"] == 2)]
        session["sets"].append(fixture._set("x", "incline-dumbbell-press", 3, 0, 30, 10, "hard", targets=(8, 12)))
        described = today.compute_day(export, PUSH_7, now=EXPORTED)["sessions"][0]
        self.assertEqual(described["plan"], {"slots": 3, "skipped": ["Lateral Raise"],
                                             "short": ["Triceps Pushdown 2/3"],
                                             "notPlanned": ["Incline Dumbbell Press"]})
        self.assertEqual(exercise({"sessions": [described]}, "Barbell Bench Press")["planned"],
                         "3 sets of 6-10, rest 150s")

    def test_a_session_without_a_plan_day_has_no_plan_comparison(self):
        export = fixture.export()
        session = session_on(export, PUSH_7, "Push A")
        session.pop("planDayID")
        described = today.compute_day(export, PUSH_7, now=EXPORTED)["sessions"][0]
        self.assertNotIn("plan", described)
        self.assertNotIn("planned", described["exercises"][0])


class Rest(unittest.TestCase):
    def _bench_with_times(self, announced: bool):
        export = fixture.export()
        session = session_on(export, PUSH_7, "Push A")
        bench = [s for s in session["sets"] if s["catalogID"] == "barbell-bench-press"]
        stamps = [("10:05:00", None), ("10:08:00", "10:07:00"), ("10:11:00", "10:10:30")]
        for s, (done, began) in zip(bench, stamps):
            s["completedAt"] = f"2026-09-28T{done}Z"
            if announced and began:
                s["startedAt"] = f"2026-09-28T{began}Z"
        warmup = dict(bench[0], id=fixture.uid("warm"), setIndex=-1, weightKg=40, reps=10, isWarmup=True,
                      completedAt="2026-09-28T10:02:00Z")
        warmup.pop("effort"), warmup.pop("rpe")
        drop = dict(bench[0], id=fixture.uid("drop"), setIndex=0, weightKg=70, reps=4, continues="drop",
                    completedAt="2026-09-28T10:06:00Z")
        drop.pop("effort"), drop.pop("rpe")
        session["sets"] += [warmup, drop]
        session["sets"].sort(key=lambda s: (s["exerciseOrder"], s["setIndex"], "continues" in s))
        return exercise(today.compute_day(export, PUSH_7, now=EXPORTED), "Barbell Bench Press")

    def test_announced_starts_split_rest_from_the_set_and_a_drop_ends_the_effort(self):
        bench = self._bench_with_times(announced=True)
        # 10:06 (end of the drop) to 10:07, then 10:08 to 10:10:30.
        self.assertEqual((bench["restMedianSeconds"], bench["restBasis"], bench["restCount"]), (105, "announced", 2))
        self.assertNotIn("gapMedianSeconds", bench)
        self.assertEqual(bench["workingSets"], 3)
        self.assertTrue(bench["rows"][0].startswith("warm-up"))
        self.assertTrue(bench["rows"][2].startswith("+drop"))

    def test_without_starts_only_the_gap_is_reported(self):
        bench = self._bench_with_times(announced=False)
        self.assertNotIn("restMedianSeconds", bench)
        self.assertEqual((bench["gapMedianSeconds"], bench["gapCount"]), (150, 2))

    def test_a_session_logged_afterwards_has_no_times(self):
        export = fixture.export()
        session = session_on(export, LEGS_7, "Legs")
        session.pop("endedAt")
        session["loggedAfterwards"] = True
        described = today.compute_day(export, LEGS_7, now=EXPORTED)["sessions"][0]
        self.assertTrue(described["loggedAfterwards"])
        for key in ("start", "end", "minutes"):
            self.assertNotIn(key, described)
        self.assertFalse({"restMedianSeconds", "gapMedianSeconds"} & set(described["exercises"][0]))


class Volume(unittest.TestCase):
    def test_fractional_sets_today_and_the_week_so_far(self):
        result = today.compute_day(fixture.export(), LEGS_7, now=EXPORTED)
        self.assertEqual(result["week"], {"sessionsSoFar": 3, "planTrainingDays": 3})
        quads = next(m for m in result["muscles"] if m["muscle"] == "quads")
        self.assertEqual((quads["today"], quads["weekSoFar"]), (3.0, 3.0))
        push = today.compute_day(fixture.export(), PUSH_7, now=EXPORTED)
        self.assertEqual(push["week"]["sessionsSoFar"], 1)
        self.assertEqual({m["muscle"]: m["today"] for m in push["muscles"]},
                         {"chest": 3.0, "shoulders": 4.5, "triceps": 4.5})


class Markdown(unittest.TestCase):
    def test_reads_like_the_stats(self):
        text = today.render_markdown(today.compute_day(fixture.export(), PUSH_7, now=EXPORTED))
        self.assertIn("# Training day 2026-09-28 (Monday, not today)", text)
        self.assertIn("Comparable: 108 kg e1RM vs 105 on 09-21 (+3); best before 105, a new best.", text)
        self.assertIn("Last time 09-21: 87.5kg x 6 solid", text)
        self.assertIn('Note: "Right elbow twinge on the last set" [pain]', text)
        self.assertIn("every slot trained in full", text)
        substitution = today.render_markdown(today.compute_day(fixture.export(), LEGS_3, now=EXPORTED))
        self.assertIn("tagged as a substitution", substitution)


class Command(helpers.CoachTestCase):
    def test_writes_under_daily_never_reviews_and_keeps_the_coachs_notes(self):
        export = self.root / "export.json"
        export.write_text(json.dumps(fixture.export()))
        code, out, err = self.coach("today", "--file", str(export))
        self.assertEqual(code, 0, err)
        folder = self.home / "daily" / LEGS_7.isoformat()
        self.assertEqual(out.splitlines()[0], str(folder / "today.md"))
        self.assertEqual(json.loads((folder / "today.json").read_text())["day"], LEGS_7.isoformat())
        self.assertFalse((self.home / "reviews").exists())
        self.assertFalse((folder / "snapshot.json").exists())
        (folder / "notes.md").write_text("mine")
        code, out, _ = self.coach("today", "--file", str(export))
        self.assertEqual((folder / "notes.md").read_text(), "mine")
        self.assertIn("This day's notes so far", out)

    def test_points_at_the_last_review_and_earlier_daily_notes(self):
        export = self.root / "export.json"
        export.write_text(json.dumps(fixture.export()))
        review = self.put_review(stats=False)
        (review / "notes.md").write_text("review")
        for day in ("2026-09-28", "2026-09-30", "2026-10-05"):
            (self.home / "daily" / day).mkdir(parents=True)
            (self.home / "daily" / day / "notes.md").write_text(day)
        code, out, _ = self.coach("today", "--file", str(export))
        self.assertEqual(code, 0)
        self.assertIn(f"Last review's notes: {review / 'notes.md'}", out)
        earlier = [line for line in out.splitlines() if line.startswith("Earlier daily notes")]
        self.assertEqual([line.rsplit("/", 2)[1] for line in earlier], ["2026-09-28", "2026-09-30"])

    def test_reads_the_phone_without_touching_decisions(self):
        coach_dir = self.phone / "phone" / "Documents" / "Coach"
        coach_dir.mkdir(parents=True)
        (coach_dir / "snapshot.json").write_text(json.dumps(fixture.export()))
        code, _, err = self.coach("today", "--day", PUSH_7.isoformat())
        self.assertEqual(code, 0, err)
        self.assertTrue((self.home / "daily" / PUSH_7.isoformat() / "today.md").exists())
        calls = [json.loads(line) for line in (self.phone / "calls.log").read_text().splitlines()]
        sources = [c[c.index("--source") + 1] for c in calls if c[:3] == ["device", "copy", "from"]]
        self.assertEqual(sources, ["Documents/Coach/snapshot.json"])

    def test_a_malformed_day_is_refused(self):
        export = self.root / "export.json"
        export.write_text(json.dumps(fixture.export()))
        code, _, err = self.coach("today", "--file", str(export), "--day", "28/09")
        self.assertEqual(code, 2)
        self.assertIn("YYYY-MM-DD", err)
        self.assertFalse((self.home / "daily").exists())


if __name__ == "__main__":
    unittest.main()
