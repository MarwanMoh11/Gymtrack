"""Shared test scaffolding: a temp COACH_HOME, the fake claude and devicectl, a CLI runner."""
from __future__ import annotations

import contextlib
import copy
import io
import json
import os
import shlex
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

TOOL_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(TOOL_DIR))

from coachlib import cli  # noqa: E402
import fixture  # noqa: E402

FAKES = Path(__file__).resolve().parent / "fakes"


class CoachTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.phone = self.root / "phone-root"
        self.claude_log = self.root / "claude.log"
        self.replies_file = self.root / "replies.json"
        env = {
            "COACH_HOME": str(self.home),
            "COACH_CLAUDE_BIN": str(FAKES / "claude"),
            "COACH_DEVICECTL": shlex.quote(str(FAKES / "devicectl")),
            "FAKE_PHONE_DIR": str(self.phone),
            "FAKE_PHONE_STATE": "available",
            "FAKE_CLAUDE_LOG": str(self.claude_log),
            "FAKE_CLAUDE_REPLIES": str(self.replies_file),
            "COACH_REVIEWER_MODEL": "",
        }
        patcher = mock.patch.dict(os.environ, env)
        patcher.start()
        self.addCleanup(patcher.stop)
        for name in ("COACH_PHONE", "GYMTRACK_PHONE", "FAKE_CLAUDE_EXIT"):
            os.environ.pop(name, None)

    # -- running the CLI
    def coach(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = cli.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    # -- fixtures on disk
    def put_review(self, name="2026-10-03", snapshot=None, decisions=None, stats=True):
        folder = self.home / "reviews" / name
        folder.mkdir(parents=True)
        (folder / "snapshot.json").write_text(json.dumps(snapshot or fixture.export()))
        if decisions:
            (folder / "decisions.json").write_text(json.dumps(decisions))
        if stats:
            code, _, err = self.coach("stats", str(folder))
            assert code == 0, err
        return folder

    def write_proposal(self, folder, proposal=None):
        (folder / "proposal.json").write_text(json.dumps(proposal or fixture.sample_proposal()))

    def read(self, folder, name):
        return json.loads((folder / name).read_text())

    def set_replies(self, *replies):
        self.replies_file.write_text(json.dumps(list(replies)))

    def claude_calls(self):
        if not self.claude_log.exists():
            return []
        return [json.loads(line) for line in self.claude_log.read_text().splitlines()]

    @staticmethod
    def verdicts(**by_id):
        """A reviewer reply: id=(verdict, score, note)."""
        return {"changes": [{"id": cid, "verdict": v, "score": s, "note": n} for cid, (v, s, n) in by_id.items()],
                "summary": "Overall note."}


def mutated(proposal=None, **edits):
    out = copy.deepcopy(proposal or fixture.sample_proposal())
    out.update(edits)
    return out
