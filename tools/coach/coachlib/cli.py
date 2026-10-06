"""Argument parsing for the `coach` command."""
from __future__ import annotations

import argparse
import sys

from . import commands
from .util import CoachError

DESCRIPTION = """\
GymTrack's coach loop, Mac side. Typical review:
  coach pull            copy the phone's snapshot into a new review folder
  coach stats           compute the numbers the coach reasons with
  coach submit          validate proposal.json and run an independent reviewer round
  coach submit          again, after replying to the reviewer's objections
  coach push            send the final proposal to the phone's inbox

Environment: COACH_HOME (default ~/Documents/GymTrackCoach); GYMTRACK_PHONE or
COACH_PHONE (device id, default the one scripts/install-phone.sh uses);
COACH_CLAUDE_BIN, COACH_REVIEWER_MODEL (default claude-sonnet-5-5),
COACH_REVIEWER_EFFORT (default xhigh; "default" omits either flag), COACH_REVIEWER_TIMEOUT (seconds,
default 900), COACH_REVIEWER_SETTING_SOURCES (default project; "all" loads the
user's settings too).
"""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="coach", description=DESCRIPTION,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("init", help="create COACH_HOME and a profile.md template")
    pull = sub.add_parser("pull", help="copy snapshot.json and decisions.json into a new review folder")
    pull.add_argument("--file", help="use this exported backup instead of the phone")
    for name, text in (("stats", "write stats.json and stats.md for a review"),
                       ("submit", "validate proposal.json and run the next reviewer round"),
                       ("push", "send the reviewed proposal to the phone's inbox")):
        sp = sub.add_parser(name, help=text)
        sp.add_argument("dir", nargs="?", help="review folder (default: the latest)")
    sub.add_parser("status", help="is the phone reachable, and is a proposal waiting on it")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "init":
            return commands.init()
        if args.command == "pull":
            return commands.pull(args.file)
        if args.command == "stats":
            return commands.stats(args.dir)
        if args.command == "submit":
            return commands.submit(args.dir)
        if args.command == "push":
            return commands.push(args.dir)
        return commands.status()
    except CoachError as error:
        print(f"coach: {error}", file=sys.stderr)
        return 2
