"""How the coach reads a session against its own prescription, its own training
day and the app's merged exercise IDs (October review R9-R12)."""
import unittest
from datetime import date, datetime
from zoneinfo import ZoneInfo

import helpers  # noqa: F401  (puts coachlib on the path)
from coachlib import stats
from coachlib.util import parse_time

CAIRO = ZoneInfo("Africa/Cairo")
NOW = parse_time("2026-10-15T12:00:00+03:00")
MERGES = {
    "scaption-dumbbell": "scaption",
    "bicep-curl-band": "banded-bicep-curl",
    "single-leg-leg-extension": "unilateral-leg-extension",
    "dumbbell-pullover-chest": "dumbbell-pullover",
}


def work(cid="bench", reps=8, **extra):
    return {"catalogID": cid, "isCompleted": True, "reps": reps, "weightKg": 60,
            "tracking": "weightReps", **extra}


def slot(cid="bench", sets=3, low=None, high=None, name=None):
    row = {"catalogID": cid, "name": name or cid, "targetSets": sets}
    if low:
        row.update(targetRepsLow=low, targetRepsHigh=high)
    return row


def session(sid="s", started="2026-10-13T12:00:00+03:00", sets=(), planned=None, day="d", **extra):
    out = {"id": sid, "title": "Day", "startedAt": started, "endedAt": started,
           "planDayID": day, "sets": list(sets), **extra}
    if planned is not None:
        out["plannedItems"] = planned
    return out


def snapshot(sessions, live_items=(), catalog=None, **extra):
    plan = {"id": "p", "name": "Plan", "isActive": True,
            "days": [{"id": "d", "name": "Day", "order": 0, "items": list(live_items)}]}
    snap = {"plans": [plan], "sessions": list(sessions), "timeZone": "Africa/Cairo", **extra}
    if catalog is not None:
        snap["exerciseCatalog"] = catalog
    return snap


def catalog_entry(cid, name="Bench", merged_into=None, muscles=("chest",)):
    entry = {"catalogID": cid, "name": name, "muscles": list(muscles), "trackingRaw": "weightReps"}
    if merged_into:
        entry["mergedInto"] = merged_into
    return entry


class RepeatedSlotAdherence(unittest.TestCase):
    """R9: the export names no slot per set, so a repeated exercise is read as
    one total and each logged set counts once."""

    def share(self, logged, slots, extra_sets=()):
        sets = [work(reps=8) for _ in range(logged)] + list(extra_sets)
        snap = snapshot([session(sets=sets, planned=slots)], live_items=slots)
        return stats.adherence(snap, NOW, CAIRO)["slotSetsShare"]

    def test_two_of_five_sets_is_forty_percent(self):
        self.assertEqual(self.share(2, [slot(sets=2), slot(sets=3)]), 0.4)

    def test_every_prescribed_set_is_full_completion(self):
        self.assertEqual(self.share(5, [slot(sets=2), slot(sets=3)]), 1.0)

    def test_extra_sets_do_not_exceed_the_prescription(self):
        self.assertEqual(self.share(8, [slot(sets=2), slot(sets=3)]), 1.0)

    def test_slots_with_different_rep_ranges_share_one_total(self):
        slots = [slot(sets=2, low=3, high=5), slot(sets=3, low=8, high=12)]
        sets = [work(reps=4, targetRepsLow=3), work(reps=5, targetRepsLow=3),
                work(reps=9, targetRepsLow=8), work(reps=10, targetRepsLow=8)]
        snap = snapshot([session(sets=sets, planned=slots)], live_items=slots)
        result = stats.adherence(snap, NOW, CAIRO)
        self.assertEqual(result["slotSetsShare"], 0.8)
        self.assertEqual(result["repTargetHitShare"], 1.0)

    def test_another_exercise_keeps_its_own_total(self):
        slots = [slot(sets=2), slot(sets=3), slot("row", sets=5)]
        sets = [work() for _ in range(2)] + [work("row") for _ in range(5)]
        snap = snapshot([session(sets=sets, planned=slots)], live_items=slots)
        # bench 2 of 5, row 5 of 5
        self.assertEqual(stats.adherence(snap, NOW, CAIRO)["slotSetsShare"], 0.7)

    def test_the_live_day_fallback_counts_once_too(self):
        slots = [slot(sets=2), slot(sets=3)]
        snap = snapshot([session(sets=[work(), work()])], live_items=slots)
        self.assertEqual(stats.adherence(snap, NOW, CAIRO)["slotSetsShare"], 0.4)


class SlotsKeptApartByRepRange(unittest.TestCase):
    """R9: where the sets' own rep targets say which slot they filled, a
    skipped back-off slot is not covered by the heavy sets."""

    SLOTS = [slot(sets=2, low=3, high=5), slot(sets=3, low=8, high=12)]

    def share(self, heavy, backoff, slots=None, extra=()):
        sets = ([work(reps=4, targetRepsLow=3, targetRepsHigh=5) for _ in range(heavy)]
                + [work(reps=9, targetRepsLow=8, targetRepsHigh=12) for _ in range(backoff)]
                + list(extra))
        slots = slots or self.SLOTS
        snap = snapshot([session(sets=sets, planned=slots)], live_items=slots)
        return stats.adherence(snap, NOW, CAIRO)["slotSetsShare"]

    def test_five_heavy_sets_with_the_back_off_skipped_is_forty_percent(self):
        sets = [work(reps=4, targetRepsLow=3, targetRepsHigh=5) for _ in range(5)]
        snap = snapshot([session(sets=sets, planned=self.SLOTS)], live_items=self.SLOTS)
        self.assertEqual(stats.adherence(snap, NOW, CAIRO)["slotSetsShare"], 0.4)

    def test_both_slots_partly_done(self):
        self.assertEqual(self.share(1, 2), 0.6)

    def test_both_slots_full(self):
        self.assertEqual(self.share(2, 3), 1.0)

    def test_extra_sets_on_one_slot_do_not_fill_the_other(self):
        self.assertEqual(self.share(4, 1), 0.6)

    def test_equal_ranges_fall_back_to_the_sum(self):
        slots = [slot(sets=2, low=8, high=12), slot(sets=3, low=8, high=12)]
        self.assertEqual(self.share(0, 2, slots=slots), 0.4)
        self.assertEqual(self.share(0, 5, slots=slots), 1.0)
        self.assertEqual(self.share(0, 8, slots=slots), 1.0)

    def test_sets_without_a_target_are_pooled_over_what_is_left(self):
        slots = self.SLOTS
        sets = [work(reps=9, targetRepsLow=8, targetRepsHigh=12) for _ in range(3)]
        sets += [work(), work()]
        snap = snapshot([session(sets=sets, planned=slots)], live_items=slots)
        # back-off full (3), the two targetless sets take the heavy slot's room
        self.assertEqual(stats.adherence(snap, NOW, CAIRO)["slotSetsShare"], 1.0)
        snap = snapshot([session(sets=[work(), work()], planned=slots)], live_items=slots)
        self.assertEqual(stats.adherence(snap, NOW, CAIRO)["slotSetsShare"], 0.4)

    def test_a_set_whose_range_matches_no_slot_is_pooled(self):
        stray = [work(reps=6, targetRepsLow=6, targetRepsHigh=8)]
        self.assertEqual(self.share(0, 3, extra=stray), 0.8)


class ShortenedUsesTheFrozenPrescription(unittest.TestCase):
    """R10: a later plan edit never changes how an earlier session reads."""

    def exposure(self, sets_logged, planned, live=(), planned_key=True, day="d", extra=()):
        sets = [work() for _ in range(sets_logged)]
        item = session(sets=sets, planned=planned if planned_key else None, day=day)
        snap = snapshot([item, *extra], live_items=live)
        return stats.build_exposures(snap, {"bench": {"tracking": "weightReps"}})["bench"][0]

    def test_a_raised_live_target_does_not_shorten_an_old_session(self):
        row = self.exposure(3, [slot(sets=3)], live=[slot(sets=10)])
        self.assertFalse(row["shortened"])

    def test_a_lowered_live_target_does_not_hide_a_short_session(self):
        row = self.exposure(3, [slot(sets=10)], live=[slot(sets=2)])
        self.assertTrue(row["shortened"])

    def test_a_removed_live_slot_leaves_the_prescription_intact(self):
        self.assertFalse(self.exposure(3, [slot(sets=3)], live=[])["shortened"])
        self.assertTrue(self.exposure(3, [slot(sets=10)], live=[])["shortened"])

    def test_a_removed_live_day_leaves_the_prescription_intact(self):
        self.assertTrue(self.exposure(3, [slot(sets=10)], live=[slot(sets=1)], day="gone")["shortened"])

    def test_repeated_slots_are_summed(self):
        slots = [slot(sets=2), slot(sets=3)]
        self.assertTrue(self.exposure(2, slots)["shortened"])
        self.assertFalse(self.exposure(3, slots)["shortened"])

    def test_a_session_without_a_record_falls_back_to_the_live_day(self):
        # Older exports froze nothing, so the live day is the only reading.
        self.assertTrue(self.exposure(3, None, live=[slot(sets=10)], planned_key=False)["shortened"])
        self.assertFalse(self.exposure(3, None, live=[slot(sets=4)], planned_key=False)["shortened"])
        self.assertFalse(self.exposure(3, None, live=[], planned_key=False)["shortened"])
        self.assertFalse(self.exposure(3, None, live=[slot(sets=10)], planned_key=False, day="gone")["shortened"])

    def test_a_raised_live_target_does_not_block_a_plateau(self):
        starts = [f"2026-{m:02}-{d:02}T12:00:00+03:00" for m, d in
                  ((8, 24), (8, 31), (9, 7), (9, 14), (9, 21), (9, 28))]
        sessions = [session(sid=str(i), started=s, sets=[work() for _ in range(3)], planned=[slot(sets=3)])
                    for i, s in enumerate(starts)]
        snap = snapshot(sessions, live_items=[slot(sets=10)])
        rows = stats.build_exposures(snap, {"bench": {"tracking": "weightReps"}})["bench"]
        self.assertFalse(any(r["shortened"] for r in rows))
        self.assertTrue(stats.analyse_exercise("bench", rows, "Bench")["plateau"]["isPlateau"])


class TrainingDayBoundary(unittest.TestCase):
    """R11: before 04:00 local wall-clock time is still the night before."""

    def day(self, text):
        return stats.training_day(parse_time(text), CAIRO)

    def test_03_59_is_the_night_before_and_04_00_is_the_day(self):
        self.assertEqual(self.day("2026-10-12T03:59:00+03:00"), date(2026, 10, 11))
        self.assertEqual(self.day("2026-10-12T04:00:00+03:00"), date(2026, 10, 12))

    def test_weeks_turn_over_at_four_on_monday(self):
        before = stats._week_start(parse_time("2026-10-12T03:59:00+03:00"), CAIRO)
        after = stats._week_start(parse_time("2026-10-12T04:00:00+03:00"), CAIRO)
        self.assertEqual((before, after), (datetime(2026, 10, 5), datetime(2026, 10, 12)))

    def test_sunday_night_stays_in_its_own_week(self):
        week = stats._week_start(parse_time("2026-10-11T23:30:00+03:00"), CAIRO)
        self.assertEqual(week, datetime(2026, 10, 5))

    def test_the_boundary_follows_the_wall_clock_across_cairos_clock_changes(self):
        # Clocks go forward at midnight on Friday 24 April 2026 (that day
        # starts at 01:00), so 04:30 is only three and a half hours in: taking
        # four hours off would call it Thursday's.
        cases = {
            "2026-04-24T04:30:00+03:00": date(2026, 4, 24),
            "2026-04-24T03:30:00+03:00": date(2026, 4, 23),
            "2026-04-24T01:00:00+03:00": date(2026, 4, 23),
            # Clocks go back at midnight on Friday 30 October (that day has
            # 25 hours and its 23:00 repeats), so 04:00 is five hours in.
            "2026-10-30T04:00:00+02:00": date(2026, 10, 30),
            "2026-10-30T03:30:00+02:00": date(2026, 10, 29),
            "2026-10-29T23:30:00+03:00": date(2026, 10, 29),
            "2026-10-29T23:30:00+02:00": date(2026, 10, 29),
        }
        for text, expected in cases.items():
            with self.subTest(text):
                self.assertEqual(self.day(text), expected)

    def test_the_week_boundary_survives_a_clock_change_in_the_week(self):
        # Monday 27 April sits just after the spring change.
        self.assertEqual(stats._week_start(parse_time("2026-04-27T03:30:00+03:00"), CAIRO), datetime(2026, 4, 20))
        self.assertEqual(stats._week_start(parse_time("2026-04-27T04:00:00+03:00"), CAIRO), datetime(2026, 4, 27))
        # Monday 2 November sits just after the autumn change.
        self.assertEqual(stats._week_start(parse_time("2026-11-02T03:30:00+02:00"), CAIRO), datetime(2026, 10, 26))
        self.assertEqual(stats._week_start(parse_time("2026-11-02T04:00:00+02:00"), CAIRO), datetime(2026, 11, 2))

    def volume(self, started, now):
        sets = [work()]
        sessions = [session(sid="a", started="2026-10-06T12:00:00+03:00", sets=sets),
                    session(sid="b", started=started, sets=sets)]
        catalog = {"bench": {"muscles": ["chest"], "tracking": "weightReps"}}
        chest = stats.muscle_volume(snapshot(sessions), catalog, parse_time(now), CAIRO)["muscles"]["chest"]
        return chest["lastWeekFractionalSets"], chest["thisWeekFractionalSets"]

    def test_a_set_before_four_on_monday_belongs_to_last_week(self):
        self.assertEqual(self.volume("2026-10-12T03:59:00+03:00", "2026-10-15T12:00:00+03:00"), (2, 0))
        self.assertEqual(self.volume("2026-10-12T04:00:00+03:00", "2026-10-15T12:00:00+03:00"), (1, 1))

    def test_an_export_taken_before_four_on_monday_is_still_last_week(self):
        # 03:00 on Monday 12 October is Sunday's night, so the week of the 5th
        # is not over: no week is complete yet and the sessions are this week's.
        self.assertEqual(self.volume("2026-10-07T12:00:00+03:00", "2026-10-12T03:00:00+03:00"), (None, 2))
        self.assertEqual(self.volume("2026-10-07T12:00:00+03:00", "2026-10-12T04:00:00+03:00"), (2, 0))

    def test_adherence_reads_the_same_training_week(self):
        plan = {"id": "p", "name": "Plan", "isActive": True,
                "days": [{"id": "d", "name": "Day", "order": 0, "weekday": 1, "items": [slot(sets=1)]}]}
        late = session(started="2026-10-12T00:30:00+03:00", sets=[work()], planned=[slot(sets=1)])
        result = stats.adherence({"plans": [plan], "sessions": [late]}, NOW, CAIRO)
        # Sunday's training day: last week, so one complete week was measured.
        self.assertEqual(result["weeksMeasured"], 1)
        self.assertEqual(result["weekDaysTrainedShare"], 1.0)

    def test_session_dates_in_the_output_are_training_days(self):
        late = session(started="2026-10-12T00:30:00+03:00", sets=[work()], planned=[slot("row", sets=1)])
        snap = snapshot([late])
        self.assertEqual(stats.planned_vs_done(snap, NOW, CAIRO)[0]["date"], "2026-10-11")
        self.assertEqual(stats.recent_sets(snap, ["bench"], CAIRO)["bench"][0]["date"], "10-11")


class MergedExerciseIDs(unittest.TestCase):
    """R12: a retired catalog ID and its survivor are one movement; sets keep
    the ID they were logged under."""

    def catalog(self, old, new, with_field=True):
        return [catalog_entry(old, "Old", merged_into=new if with_field else None),
                catalog_entry(new, "Survivor")]

    def history(self, old, new, ids):
        """One session per listed ID, ten days apart."""
        return [session(sid=f"s{i}", started=f"2026-10-{i + 1:02}T12:00:00+03:00",
                        sets=[work(cid, reps=8 + i)]) for i, cid in enumerate(ids)]

    def exposures(self, old, new, ids, with_field=True):
        snap = snapshot(self.history(old, new, ids), catalog=self.catalog(old, new, with_field))
        return stats.build_exposures(snap, stats.catalog_index(snap))

    def test_each_bundled_pair_forms_one_series(self):
        for old, new in MERGES.items():
            with self.subTest(old):
                result = self.exposures(old, new, [old, new])
                self.assertEqual(list(result), [new])
                self.assertEqual(len(result[new]), 2)

    def test_old_only_history_lands_on_the_survivor(self):
        for old, new in MERGES.items():
            with self.subTest(old):
                result = self.exposures(old, new, [old, old])
                self.assertEqual(list(result), [new])
                self.assertEqual([r["loggedAs"] for r in result[new]], [[old], [old]])

    def test_new_only_history_is_unchanged(self):
        for old, new in MERGES.items():
            with self.subTest(old):
                result = self.exposures(old, new, [new, new])
                self.assertEqual(list(result), [new])
                self.assertTrue(all("loggedAs" not in r for r in result[new]))

    def test_mixed_history_in_one_session_cites_the_old_id(self):
        old, new = "scaption-dumbbell", "scaption"
        both = session(sets=[work(old), work(new)])
        snap = snapshot([both], catalog=self.catalog(old, new))
        row = stats.build_exposures(snap, stats.catalog_index(snap))[new][0]
        self.assertEqual((row["sets"], row["loggedAs"]), (2, [old]))

    def test_an_export_without_the_field_keeps_the_ids_apart(self):
        old, new = "single-leg-leg-extension", "unilateral-leg-extension"
        result = self.exposures(old, new, [old, new], with_field=False)
        self.assertEqual(sorted(result), sorted([old, new]))
        self.assertNotIn("mergedInto", stats.catalog_index(snapshot([], catalog=self.catalog(old, new, False)))[old])

    def test_custom_exercises_with_one_name_are_not_merged(self):
        custom = [{"id": "a", "name": "Curl", "muscleRaw": ["Biceps"], "trackingRaw": "weightReps"},
                  {"id": "b", "name": "Curl", "muscleRaw": ["Biceps"], "trackingRaw": "weightReps"}]
        snap = snapshot([session(sid="1", sets=[work("a")]),
                         session(sid="2", started="2026-10-14T12:00:00+03:00", sets=[work("b")])],
                        customExercises=custom)
        self.assertEqual(sorted(stats.build_exposures(snap, stats.catalog_index(snap))), ["a", "b"])

    def test_notes_adherence_and_the_plan_follow_the_survivor(self):
        old, new = "bicep-curl-band", "banded-bicep-curl"
        slots = [slot(new, sets=3)]
        sets = [work(old) for _ in range(3)]
        item = session(sets=sets, planned=slots, exerciseNotes=[
            {"catalogID": old, "text": "Elbow pinch", "tags": ["pain"]}])
        snap = snapshot([item], live_items=slots, catalog=self.catalog(old, new))
        catalog = stats.catalog_index(snap)
        self.assertEqual(stats.adherence(snap, NOW, CAIRO, catalog)["slotSetsShare"], 1.0)
        self.assertEqual(stats.planned_vs_done(snap, NOW, CAIRO, catalog), [])
        self.assertEqual(stats.build_exposures(snap, catalog)[new][0]["tags"], ["pain"])
        recent = stats.recent_sets(snap, [new], CAIRO, catalog=catalog)
        self.assertEqual(recent[new][0]["loggedAs"], [old])
        # the note keeps the ID it was written under
        self.assertEqual(stats.collect_notes(snap, catalog, NOW)[0]["catalogID"], old)
        result = stats.compute(snap)
        self.assertEqual(result["exercises"][new]["painNotes90d"], 1)
        self.assertEqual(result["mergedInto"], {old: new})
        self.assertEqual(result["recentSets"][new][0]["loggedAs"], [old])

    def test_volume_uses_the_survivors_muscles_when_the_old_entry_is_gone(self):
        old, new = "scaption-dumbbell", "scaption"
        catalog = {old: {"muscles": [], "mergedInto": new}, new: {"muscles": ["shoulders"]}}
        snap = snapshot([session(sets=[work(old)])])
        volume = stats.muscle_volume(snap, catalog, NOW, CAIRO)
        self.assertEqual(volume["muscles"]["shoulders"]["thisWeekFractionalSets"], 1.0)

    def test_an_export_without_merges_has_no_map(self):
        snap = snapshot([session(sets=[work()])], catalog=[catalog_entry("bench")])
        self.assertNotIn("mergedInto", stats.compute(snap))

    def test_a_merge_loop_cannot_hang(self):
        catalog = {"a": {"mergedInto": "b"}, "b": {"mergedInto": "a"}}
        self.assertIn(stats.canonical_id(catalog, "a"), ("a", "b"))


if __name__ == "__main__":
    unittest.main()
