import json
import os
import re
import unittest
from pathlib import Path
from unittest import mock

import fixture
import helpers
from coachlib import reviewer, stats
from coachlib.reviewer import ReviewerError

IDS = ["c1", "c2"]


def reply(**overrides):
    rows = [{"id": "c1", "verdict": "doubt", "score": 2, "note": "within noise"},
            {"id": "c2", "verdict": "agree", "score": 4, "note": "fine"}]
    out = {"changes": rows, "summary": "ok"}
    out.update(overrides)
    return out


class ParseReply(unittest.TestCase):
    def test_plain_json(self):
        parsed = reviewer.parse_reply(json.dumps(reply()), IDS)
        self.assertEqual([c["verdict"] for c in parsed["changes"]], ["doubt", "agree"])
        self.assertEqual(parsed["summary"], "ok")

    def test_code_fence_and_prose_around_it(self):
        text = "Here you go:\n```json\n" + json.dumps(reply()) + "\n```\nHope that helps."
        self.assertEqual(len(reviewer.parse_reply(text, IDS)["changes"]), 2)

    def test_a_preceding_brace_does_not_confuse_it(self):
        text = "Note {not json}. " + json.dumps(reply())
        self.assertEqual(len(reviewer.parse_reply(text, IDS)["changes"]), 2)

    def test_garbage_fails_loudly(self):
        for text in ("I think these changes are fine.", "", '{"changes": "none"}', "[1, 2]"):
            with self.subTest(text), self.assertRaises(ReviewerError):
                reviewer.parse_reply(text, IDS)

    def test_content_is_checked(self):
        bad = {
            "missing change": reply(changes=reply()["changes"][:1]),
            "unknown id": reply(changes=reply()["changes"] + [{"id": "c9", "verdict": "agree", "score": 3, "note": "x"}]),
            "duplicate": reply(changes=reply()["changes"] + [reply()["changes"][0]]),
            "verdict": reply(changes=[{"id": "c1", "verdict": "maybe", "score": 3, "note": "x"}, reply()["changes"][1]]),
            "score zero": reply(changes=[{"id": "c1", "verdict": "agree", "score": 0, "note": "x"}, reply()["changes"][1]]),
            "score float": reply(changes=[{"id": "c1", "verdict": "agree", "score": 3.5, "note": "x"}, reply()["changes"][1]]),
            "no note": reply(changes=[{"id": "c1", "verdict": "agree", "score": 3, "note": " "}, reply()["changes"][1]]),
        }
        for name, value in bad.items():
            with self.subTest(name), self.assertRaises(ReviewerError):
                reviewer.parse_reply(json.dumps(value), IDS)


class Environment(unittest.TestCase):
    def test_session_markers_are_removed_and_credentials_kept(self):
        base = {"PATH": "/usr/bin", "CLAUDECODE": "1", "CLAUDE_CODE_SESSION_ID": "abc", "CLAUDE_CODE_ENTRYPOINT": "x",
                "CLAUDE_CODE_MESSAGING_TOKEN": "t", "CLAUDE_AGENT_SDK_VERSION": "1", "CLAUDE_PID": "5",
                "CLAUDE_CODE_OAUTH_TOKEN": "keep-me", "ANTHROPIC_API_KEY": "key", "CLAUDE_CODE_USE_BEDROCK": "1"}
        env = reviewer.clean_env(base)
        for gone in ("CLAUDECODE", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_MESSAGING_TOKEN",
                     "CLAUDE_AGENT_SDK_VERSION", "CLAUDE_PID"):
            self.assertNotIn(gone, env)
        for kept in ("PATH", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY", "CLAUDE_CODE_USE_BEDROCK"):
            self.assertIn(kept, env)
        self.assertEqual(env["CLAUDE_CODE_DISABLE_CLAUDE_MDS"], "1")


class FindBinary(unittest.TestCase):
    def test_env_override_wins(self):
        with mock.patch.dict(os.environ, {"COACH_CLAUDE_BIN": "/x/claude"}):
            self.assertEqual(reviewer.find_claude_binary(), "/x/claude")

    def test_path_then_newest_install(self):
        env = {k: v for k, v in os.environ.items() if k != "COACH_CLAUDE_BIN"}
        with mock.patch.dict(os.environ, env, clear=True), mock.patch("shutil.which", return_value="/usr/local/bin/claude"):
            self.assertEqual(reviewer.find_claude_binary(), "/usr/local/bin/claude")
        import tempfile
        with tempfile.TemporaryDirectory() as home:
            for version in ("2.1.9", "2.1.284", "2.0.5"):
                binary = Path(home, "Library/Application Support/Claude/claude-code", version,
                              "claude.app/Contents/MacOS/claude")
                binary.parent.mkdir(parents=True)
                binary.write_text("")
            with mock.patch.dict(os.environ, {**env, "HOME": home}, clear=True), mock.patch("shutil.which", return_value=None):
                self.assertIn("2.1.284", reviewer.find_claude_binary())
            with mock.patch.dict(os.environ, {**env, "HOME": home + "/none"}, clear=True), \
                    mock.patch("shutil.which", return_value=None):
                with self.assertRaises(ReviewerError):
                    reviewer.find_claude_binary()


class Command(unittest.TestCase):
    HELP = (helpers.FAKES / "claude").read_text()

    def test_flags_follow_the_help_text(self):
        help_text = "-p, --print --output-format --tools --no-session-persistence --model --effort"
        with mock.patch.dict(os.environ, {"COACH_REVIEWER_MODEL": "sonnet", "COACH_REVIEWER_EFFORT": "high"}):
            command = reviewer.build_command("claude", help_text)
        self.assertEqual(command[:7], ["claude", "--print", "--output-format", "json", "--tools", "", "--no-session-persistence"])
        self.assertIn("--model", command)
        self.assertEqual(command[command.index("--effort") + 1], "high")
        self.assertNotIn("--system-prompt", command)  # not in this help text

    def test_a_binary_without_print_mode_is_refused(self):
        with self.assertRaises(ReviewerError):
            reviewer.build_command("claude", "--output-format --tools")

    def test_a_model_the_binary_cannot_take_is_refused(self):
        with self.assertRaises(ReviewerError):
            reviewer.build_command("claude", "--print --output-format --tools", model="sonnet")

    def test_no_model_flag_by_default(self):
        with mock.patch.dict(os.environ, {"COACH_REVIEWER_MODEL": ""}):
            self.assertNotIn("--model", reviewer.build_command("claude", self.HELP))


class Bundle(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.snapshot = fixture.export()
        cls.stats = stats.compute(cls.snapshot, fixture.decisions())
        cls.md = stats.render_markdown(cls.stats)

    def prompt(self, proposal=None, round_number=1, previous=None):
        return reviewer.build_prompt("Priority muscles: side delts", self.md, self.stats, self.snapshot,
                                     proposal or fixture.sample_proposal(), round_number, previous)

    def test_template_never_names_what_the_reviewer_is(self):
        text = (reviewer.PROMPT_FILE).read_text()
        for pattern in (r"\bAI\b", r"Claude", r"Anthropic", r"\bLLM\b", r"language model", r"\bmodel\b", r"assistant",
                        r"chatbot", r"\bagent\b"):
            self.assertIsNone(re.search(pattern, text), pattern)
        self.assertIn("A coach proposed", text)

    def test_prompt_has_data_and_no_reason_prose(self):
        proposal = fixture.sample_proposal()
        text = self.prompt(proposal)
        for change in proposal["changes"]:
            self.assertNotIn(change["reason"], text)
        self.assertNotIn(proposal["summary"], text)
        self.assertNotIn("Push the last set", text)  # the advice is prose too
        self.assertIn("Priority muscles: side delts", text)
        self.assertIn("shoulders.weeklyFractionalSets", text)  # the stats header and the evidence
        self.assertIn("Lateral Raise", text)
        self.assertIn("Push A", text)
        self.assertNotIn("{{", text)
        for pattern in (r"\bAI\b", r"Claude"):
            self.assertIsNone(re.search(pattern, text))

    def test_prompt_names_slots_instead_of_uuids(self):
        text = self.prompt()
        shown = text[text.index("## Proposed changes"):]
        self.assertNotIn(fixture.item_id("lateral-raise"), shown)
        self.assertIn('"slot": "Lateral Raise"', shown)

    def test_recent_sessions_of_touched_exercises_are_included(self):
        text = self.prompt()
        self.assertIn("Lateral Raise (8 comparable sessions, newest last):", text)
        self.assertIn("2026-09-28: 13.67 kg; 10kg x 11 solid", text)
        self.assertIn("Pull-Up (7 comparable sessions", text)

    def test_round_two_carries_the_first_notes_and_the_reply(self):
        proposal = fixture.sample_proposal()
        proposal["changes"][0]["reply"] = {"stance": "defended", "text": "Plateau is flagged by the script."}
        previous = {"changes": [{"id": "c1", "verdict": "doubt", "score": 2, "note": "Inside the noise."},
                                {"id": "c2", "verdict": "agree", "score": 4, "note": "Fine."}]}
        proposal["changes"][1]["reply"] = {"stance": "defended", "text": "Agreed."}
        text = self.prompt(proposal, 2, previous)
        self.assertIn("## Second round", text)
        self.assertIn("Inside the noise.", text)
        self.assertIn("Plateau is flagged by the script.", text)
        self.assertIn("defended", text)


class Run(helpers.CoachTestCase):
    def test_child_runs_standalone(self):
        self.set_replies(reply())
        with mock.patch.dict(os.environ, {"CLAUDECODE": "1", "CLAUDE_CODE_SESSION_ID": "parent",
                                          "CLAUDE_CODE_OAUTH_TOKEN": "tok", "COACH_REVIEWER_MODEL": "sonnet"}):
            text, meta = reviewer.run("the prompt")
        self.assertEqual(json.loads(text)["summary"], "ok")
        call = self.claude_calls()[0]
        self.assertEqual(call["prompt"], "the prompt")
        self.assertIsNone(call["claudecode"])
        self.assertIsNone(call["session_id"])
        self.assertEqual(call["oauth"], "tok")
        self.assertEqual(call["disable_mds"], "1")
        self.assertNotIn(str(helpers.TOOL_DIR.parent.parent), call["cwd"])  # not the repo
        argv = call["argv"]
        self.assertEqual(argv[argv.index("--tools") + 1], "")
        for flag in ("--print", "--no-session-persistence", "--disable-slash-commands", "--strict-mcp-config"):
            self.assertIn(flag, argv)
        self.assertEqual(argv[argv.index("--output-format") + 1], "json")
        self.assertEqual(argv[argv.index("--model") + 1], "sonnet")
        self.assertEqual(argv[argv.index("--effort") + 1], "max")
        self.assertEqual(argv[argv.index("--setting-sources") + 1], "project")
        self.assertEqual(meta["total_cost_usd"], 0.01)

    def test_a_failing_child_is_an_error(self):
        self.set_replies(reply())
        with mock.patch.dict(os.environ, {"FAKE_CLAUDE_EXIT": "3"}):
            with self.assertRaisesRegex(ReviewerError, "status 3"):
                reviewer.run("p")

    def test_an_error_envelope_is_an_error(self):
        script = self.root / "badclaude"
        script.write_text('#!/usr/bin/env python3\nimport sys, json\n'
                          'if "--help" in sys.argv:\n    print("--print --output-format --tools"); sys.exit(0)\n'
                          'sys.stdin.read()\nprint(json.dumps({"is_error": True, "result": "rate limited"}))\n')
        script.chmod(0o755)
        with mock.patch.dict(os.environ, {"COACH_CLAUDE_BIN": str(script)}):
            with self.assertRaisesRegex(ReviewerError, "rate limited"):
                reviewer.run("p")

    def test_non_json_output_is_an_error(self):
        script = self.root / "chatty"
        script.write_text('#!/usr/bin/env python3\nimport sys\n'
                          'if "--help" in sys.argv:\n    print("--print --output-format --tools"); sys.exit(0)\n'
                          'sys.stdin.read()\nprint("hello")\n')
        script.chmod(0o755)
        with mock.patch.dict(os.environ, {"COACH_CLAUDE_BIN": str(script)}):
            with self.assertRaisesRegex(ReviewerError, "not JSON"):
                reviewer.run("p")


if __name__ == "__main__":
    unittest.main()
