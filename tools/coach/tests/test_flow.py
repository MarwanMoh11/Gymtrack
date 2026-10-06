import copy
import json
import os
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock

import fixture
import helpers
from helpers import CoachTestCase, mutated


class InitAndPull(CoachTestCase):
    def test_init_writes_the_profile_once(self):
        code, out, _ = self.coach("init")
        self.assertEqual(code, 0)
        profile = self.home / "profile.md"
        text = profile.read_text()
        for needle in ("Priority muscles:", "Injuries", "Equipment", "Days available:"):
            self.assertIn(needle, text)
        self.assertNotIn("Tape measurements", text)
        profile.write_text("mine")
        self.coach("init")
        self.assertEqual(profile.read_text(), "mine")

    def test_pull_from_a_file_makes_dated_folders_with_suffixes(self):
        export = self.root / "export.json"
        export.write_text(json.dumps(fixture.export()))
        today = datetime.now().strftime("%Y-%m-%d")
        paths = []
        for _ in range(3):
            code, out, _ = self.coach("pull", "--file", str(export))
            self.assertEqual(code, 0)
            paths.append(out.strip().splitlines()[-1])
        self.assertEqual([p.rsplit("/", 1)[1] for p in paths], [today, today + "-2", today + "-3"])
        self.assertEqual(json.loads(Path(paths[0], "snapshot.json").read_text())["version"], 2)

    def test_pull_refuses_a_file_that_is_not_a_backup(self):
        bad = self.root / "bad.json"
        bad.write_text('{"hello": 1}')
        code, _, err = self.coach("pull", "--file", str(bad))
        self.assertEqual(code, 2)
        self.assertIn("not a GymTrack backup", err)
        self.assertFalse((self.home / "reviews").exists())

    def test_pull_from_the_phone_uses_devicectl_flags_from_the_contract(self):
        coach_dir = self.phone / "phone" / "Documents" / "Coach"
        coach_dir.mkdir(parents=True)
        (coach_dir / "snapshot.json").write_text(json.dumps(fixture.export()))
        (coach_dir / "decisions.json").write_text(json.dumps(fixture.decisions()))
        code, out, err = self.coach("pull")
        self.assertEqual(code, 0, err)
        folder = self.home / "reviews" / out.strip().splitlines()[-1].rsplit("/", 1)[1]
        self.assertTrue((folder / "snapshot.json").exists() and (folder / "decisions.json").exists())
        calls = [json.loads(line) for line in (self.phone / "calls.log").read_text().splitlines()]
        copies = [c for c in calls if c[:3] == ["device", "copy", "from"]]
        self.assertEqual(len(copies), 2)
        first = copies[0]
        self.assertEqual(first[first.index("--domain-type") + 1], "appDataContainer")
        self.assertEqual(first[first.index("--domain-identifier") + 1], "com.marwanmohamed.gymtrack")
        self.assertEqual(first[first.index("--source") + 1], "Documents/Coach/snapshot.json")
        self.assertEqual(first[first.index("--device") + 1], "00008150-000504383447401C")

    def test_pull_without_decisions_still_works(self):
        coach_dir = self.phone / "phone" / "Documents" / "Coach"
        coach_dir.mkdir(parents=True)
        (coach_dir / "snapshot.json").write_text(json.dumps(fixture.export()))
        code, out, _ = self.coach("pull")
        self.assertEqual(code, 0)
        self.assertIn("No decisions.json", out)

    def test_pull_with_the_phone_away_says_how_to_use_a_file(self):
        for state in ("unavailable", "absent"):
            with self.subTest(state), mock.patch.dict(os.environ, {"FAKE_PHONE_STATE": state}):
                code, _, err = self.coach("pull")
                self.assertEqual(code, 2)
                self.assertIn("not reachable", err)
                self.assertIn("--file", err)
        self.assertFalse((self.home / "reviews").exists())

    def test_pull_with_no_snapshot_on_the_phone_explains(self):
        code, _, err = self.coach("pull")
        self.assertEqual(code, 2)
        self.assertIn("snapshot", err)
        self.assertFalse((self.home / "reviews").exists())


class Stats(CoachTestCase):
    def test_stats_writes_json_and_markdown_and_diffs_against_the_previous_review(self):
        previous = fixture.export()
        previous["exportedAt"] = "2026-09-27T00:00:00Z"
        previous["plans"][0]["days"][0]["items"][1]["targetSets"] = 2
        self.put_review("2026-09-27", snapshot=previous)
        folder = self.put_review("2026-10-03", decisions=fixture.decisions())
        stats = self.read(folder, "stats.json")
        self.assertEqual(stats["planDiff"]["changed"][0]["field"], "targetSets")
        self.assertEqual(stats["review"]["sessionsSinceLastReview"], 3)
        md = (folder / "stats.md").read_text()
        self.assertIn("targetSets 2 to 3", md)
        self.assertIn("Outcome of the last applied proposal", md)

    def test_stats_defaults_to_the_latest_review(self):
        self.put_review("2026-09-01", stats=False)
        latest = self.put_review("2026-10-03", stats=False)
        code, out, _ = self.coach("stats")
        self.assertEqual(code, 0)
        self.assertTrue((latest / "stats.md").exists())
        self.assertFalse((self.home / "reviews" / "2026-09-01" / "stats.md").exists())

    def test_the_real_profile_feeds_the_stats(self):
        (self.home).mkdir(parents=True, exist_ok=True)
        (self.home / "profile.md").write_text("Priority muscles: side delts\n")
        folder = self.put_review()
        self.assertEqual(self.read(folder, "stats.json")["profile"]["priorityMuscles"], ["shoulders"])


class Rounds(CoachTestCase):
    def setUp(self):
        super().setUp()
        self.folder = self.put_review()

    def ready(self, proposal=None):
        self.write_proposal(self.folder, proposal)

    def test_an_invalid_proposal_stops_before_the_reviewer(self):
        bad = fixture.sample_proposal()
        bad["changes"][0]["expect"] = {"targetSets": 9}
        bad["changes"][0]["to"] = {"targetSets": 10}
        self.ready(bad)
        self.set_replies(self.verdicts(c1=("agree", 4, "x")))
        code, out, _ = self.coach("submit")
        self.assertEqual(code, 1)
        self.assertIn("stale", out)
        self.assertEqual(self.claude_calls(), [])
        self.assertFalse((self.folder / "review-1.json").exists())

    def test_round_one_saves_notes_and_prints_them(self):
        self.ready()
        self.set_replies(self.verdicts(c1=("doubt", 2, "Inside the lifter's noise."), c2=("agree", 4, "Fine.")))
        code, out, err = self.coach("submit")
        self.assertEqual(code, 0, err)
        self.assertIn("notes from an independent reviewer", out.lower())
        self.assertIn("c1: doubt 2/5. Inside the lifter's noise.", out)
        saved = self.read(self.folder, "review-1.json")
        self.assertEqual(saved["round"], 1)
        self.assertEqual(set(saved["reviewed"]), {"c1", "c2"})
        prompt = self.claude_calls()[0]["prompt"]
        self.assertIn("A coach proposed", prompt)
        self.assertNotIn("Lateral raises have not moved in four weeks", prompt)

    def test_garbage_from_the_reviewer_fails_loudly_and_saves_nothing(self):
        self.ready()
        self.set_replies("Sounds good to me!")
        code, _, err = self.coach("submit")
        self.assertEqual(code, 2)
        self.assertIn("did not return the JSON", err)
        self.assertFalse((self.folder / "review-1.json").exists())

    def after_round_one(self):
        self.ready()
        self.set_replies(
            self.verdicts(c1=("doubt", 2, "Inside the noise."), c2=("agree", 4, "Fine.")),
            self.verdicts(c1=("doubt", 3, "Still thin."), c2=("agree", 5, "Holds.")))
        self.assertEqual(self.coach("submit")[0], 0)
        return self.read(self.folder, "proposal.json")

    def test_round_two_needs_a_reply_for_every_change(self):
        proposal = self.after_round_one()
        proposal["changes"][0]["reply"] = {"stance": "defended", "text": "Plateau flagged by the script."}
        (self.folder / "proposal.json").write_text(json.dumps(proposal))
        code, out, _ = self.coach("submit")
        self.assertEqual(code, 1)
        self.assertIn("change c2: needs a reply", out)
        self.assertEqual(len(self.claude_calls()), 1)

    def test_defended_must_be_unchanged_and_revised_must_differ(self):
        proposal = self.after_round_one()
        proposal["changes"][0]["reply"] = {"stance": "defended", "text": "t"}
        proposal["changes"][0]["reason"] = "A different reason."
        proposal["changes"][1]["reply"] = {"stance": "revised", "text": "t"}
        (self.folder / "proposal.json").write_text(json.dumps(proposal))
        code, out, _ = self.coach("submit")
        self.assertEqual(code, 1)
        self.assertIn("replied defended but the change was edited", out)
        self.assertIn("replied revised but the change is unchanged", out)

    def test_a_change_added_after_round_one_is_refused(self):
        proposal = self.after_round_one()
        for change in proposal["changes"]:
            change["reply"] = {"stance": "defended", "text": "t"}
        extra = copy.deepcopy(proposal["changes"][0])
        extra.update({"id": "c3", "itemID": fixture.item_id("barbell-bench-press"), "expect": {"targetSets": 3}})
        proposal["changes"].append(extra)
        (self.folder / "proposal.json").write_text(json.dumps(proposal))
        code, out, _ = self.coach("submit")
        self.assertEqual(code, 1)
        self.assertIn("was not part of round 1", out)

    def test_round_two_removes_withdrawn_merges_reviews_and_flags_disputes(self):
        proposal = self.after_round_one()
        proposal["changes"][0]["reply"] = {"stance": "revised", "text": "Narrowed the reason."}
        proposal["changes"][0]["reason"] = "Narrower reason."
        proposal["changes"][1]["reply"] = {"stance": "withdrawn", "text": "Fair, the range is fine."}
        (self.folder / "proposal.json").write_text(json.dumps(proposal))
        self.set_replies(self.verdicts(c1=("doubt", 2, "Inside the noise.")),
                         self.verdicts(c1=("reject", 2, "Still within noise.")))
        code, out, err = self.coach("submit")
        self.assertEqual(code, 0, err)
        final = self.read(self.folder, "proposal.json")
        self.assertEqual([c["id"] for c in final["changes"]], ["c1"])
        self.assertEqual(final["changes"][0]["review"],
                         {"verdict": "reject", "score": 2, "note": "Still within noise.", "disputed": True})
        self.assertIn("Still disputed after round 2: c1", out)
        self.assertIn("c2 withdrawn", out)
        round_two = self.read(self.folder, "review-2.json")
        self.assertEqual(round_two["withdrawn"][0]["id"], "c2")
        second = self.claude_calls()[1]["prompt"]
        self.assertIn("Inside the noise.", second)           # the reviewer's own first note
        self.assertIn("Narrowed the reason.", second)        # the coach's reply
        self.assertNotIn("Narrower reason.", second)         # still no reason prose
        self.assertNotIn("Fair, the range is fine.", second)  # a withdrawn change is not shown

    def test_agreeing_changes_are_not_disputed(self):
        proposal = self.after_round_one()
        for change in proposal["changes"]:
            change["reply"] = {"stance": "defended", "text": "t"}
        (self.folder / "proposal.json").write_text(json.dumps(proposal))
        self.set_replies(self.verdicts(c1=("doubt", 2, "x"), c2=("agree", 4, "x")),
                         self.verdicts(c1=("agree", 4, "ok"), c2=("doubt", 3, "meh")))
        code, out, _ = self.coach("submit")
        final = self.read(self.folder, "proposal.json")
        self.assertEqual([c["review"]["disputed"] for c in final["changes"]], [False, True])

    def test_withdrawing_everything_means_keep_the_plan(self):
        proposal = self.after_round_one()
        for change in proposal["changes"]:
            change["reply"] = {"stance": "withdrawn", "text": "Convinced."}
        proposal["advice"] = []
        proposal.pop("advice")
        (self.folder / "proposal.json").write_text(json.dumps(proposal))
        code, out, _ = self.coach("submit")
        self.assertEqual(code, 0)
        self.assertIn("keep the plan", out)
        self.assertEqual(len(self.claude_calls()), 1)
        self.assertTrue((self.folder / "review-2.json").exists())

    def test_a_finished_review_is_not_reviewed_again(self):
        self.after_round_one()
        proposal = self.read(self.folder, "proposal.json")
        for change in proposal["changes"]:
            change["reply"] = {"stance": "defended", "text": "t"}
        (self.folder / "proposal.json").write_text(json.dumps(proposal))
        self.set_replies(self.verdicts(c1=("doubt", 2, "x"), c2=("agree", 4, "x")),
                         self.verdicts(c1=("agree", 4, "ok"), c2=("agree", 4, "ok")))
        self.assertEqual(self.coach("submit")[0], 0)
        code, _, err = self.coach("submit")
        self.assertEqual(code, 2)
        self.assertIn("coach push", err)


class PushAndStatus(CoachTestCase):
    def setUp(self):
        super().setUp()
        self.folder = self.put_review()
        self.write_proposal(self.folder)
        self.set_replies(self.verdicts(c1=("doubt", 2, "Inside the noise."), c2=("agree", 4, "Fine.")),
                         self.verdicts(c1=("doubt", 3, "Still thin."), c2=("agree", 5, "Holds.")))
        self.coach("submit")
        proposal = self.read(self.folder, "proposal.json")
        for change in proposal["changes"]:
            change["reply"] = {"stance": "defended", "text": "Because the numbers."}
        (self.folder / "proposal.json").write_text(json.dumps(proposal))
        self.assertEqual(self.coach("submit")[0], 0)
        self.inbox = self.phone / "phone" / "Documents" / "Coach" / "Inbox" / "proposal.json"

    def test_push_copies_the_reviewed_proposal_without_replies(self):
        code, out, err = self.coach("push")
        self.assertEqual(code, 0, err)
        sent = json.loads(self.inbox.read_text())
        self.assertEqual(len(sent["changes"]), 2)
        self.assertTrue(all("reply" not in c and "review" in c for c in sent["changes"]))
        self.assertTrue(sent["changes"][0]["review"]["disputed"])
        calls = [json.loads(line) for line in (self.phone / "calls.log").read_text().splitlines()]
        copy_to = next(c for c in calls if c[:3] == ["device", "copy", "to"])
        self.assertEqual(copy_to[copy_to.index("--destination") + 1], "Documents/Coach/Inbox/proposal.json")
        self.assertEqual(copy_to[copy_to.index("--domain-identifier") + 1], "com.marwanmohamed.gymtrack")
        self.assertTrue((self.folder / "pushed.json").exists())

    def test_push_before_both_rounds_is_refused(self):
        folder = self.put_review("2026-10-04")
        self.write_proposal(folder)
        code, _, err = self.coach("push", str(folder))
        self.assertEqual(code, 2)
        self.assertIn("coach submit", err)
        self.assertFalse(self.inbox.exists())

    def test_push_revalidates_against_the_snapshot(self):
        proposal = self.read(self.folder, "proposal.json")
        proposal["planID"] = fixture.OLD_PLAN_ID
        (self.folder / "proposal.json").write_text(json.dumps(proposal))
        code, out, _ = self.coach("push")
        self.assertEqual(code, 1)
        self.assertIn("planID must be the active plan", out)
        self.assertFalse(self.inbox.exists())

    def test_a_change_edited_after_its_review_is_not_pushed(self):
        proposal = self.read(self.folder, "proposal.json")
        proposal["changes"][0]["to"] = {"targetSets": 2}
        (self.folder / "proposal.json").write_text(json.dumps(proposal))
        code, out, _ = self.coach("push")
        self.assertEqual(code, 1)
        self.assertIn("edited after the review", out)

    def test_dropping_a_disputed_change_lets_the_rest_through(self):
        proposal = self.read(self.folder, "proposal.json")
        proposal["changes"] = [c for c in proposal["changes"] if not c["review"]["disputed"]]
        (self.folder / "proposal.json").write_text(json.dumps(proposal))
        code, _, err = self.coach("push")
        self.assertEqual(code, 0, err)
        self.assertEqual([c["id"] for c in json.loads(self.inbox.read_text())["changes"]], ["c2"])

    def test_a_change_with_no_review_is_not_pushed(self):
        proposal = self.read(self.folder, "proposal.json")
        del proposal["changes"][0]["review"]
        (self.folder / "proposal.json").write_text(json.dumps(proposal))
        code, out, _ = self.coach("push")
        self.assertEqual(code, 1)
        self.assertIn("no reviewer verdict", out)

    def test_push_with_the_phone_away_says_so(self):
        with mock.patch.dict(os.environ, {"FAKE_PHONE_STATE": "unavailable"}):
            code, _, err = self.coach("push")
        self.assertEqual(code, 2)
        self.assertIn("not reachable", err)
        self.assertFalse((self.folder / "pushed.json").exists())

    def test_status_follows_a_proposal_through_the_phone(self):
        def line(text):
            return next(l for l in text.splitlines() if l.startswith("Proposal"))
        self.assertEqual(self.coach("push")[0], 0)
        code, out, _ = self.coach("status")
        self.assertIn("Phone: reachable", out)
        self.assertIn("no decision yet", line(out))
        proposal_id = self.read(self.folder, "proposal.json")["id"]
        decisions = self.phone / "phone" / "Documents" / "Coach" / "decisions.json"
        entry = {"proposalID": proposal_id, "receivedAt": "2026-10-04T08:00:00Z", "changes": []}
        decisions.write_text(json.dumps({"decisions": [entry]}))
        self.assertIn("received, not decided", line(self.coach("status")[1]))
        entry.update({"decidedAt": "2026-10-04T08:05:00Z", "appliedAt": "2026-10-04T08:06:00Z",
                      "changes": [{"id": "c1", "decision": "accepted"}, {"id": "c2", "decision": "declined"}]})
        decisions.write_text(json.dumps({"decisions": [entry]}))
        self.assertIn("decided (1 accepted, 1 declined); applied", line(self.coach("status")[1]))

    def test_status_with_nothing_pushed_and_no_phone(self):
        with mock.patch.dict(os.environ, {"FAKE_PHONE_STATE": "absent"}):
            code, out, _ = self.coach("status")
        self.assertEqual(code, 0)
        self.assertIn("Phone: not reachable", out)
        self.assertIn(self.folder.name, out)


if __name__ == "__main__":
    unittest.main()
