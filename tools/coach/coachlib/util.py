"""Small shared helpers: times, JSON files, review folders."""
from __future__ import annotations

import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_HOME = "~/Documents/GymTrackCoach"
_REVIEW_NAME = re.compile(r"^(\d{4}-\d{2}-\d{2})(?:-(\d+))?$")


class CoachError(Exception):
    """A problem the user can act on; the CLI prints it without a traceback."""


def coach_home() -> Path:
    return Path(os.environ.get("COACH_HOME") or DEFAULT_HOME).expanduser()


def parse_time(text: str) -> datetime:
    """Swift's .iso8601 writes whole seconds and a Z; older Pythons dislike the Z."""
    text = text.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    moment = datetime.fromisoformat(text)
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment


def format_time(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def is_uuid(value: object) -> bool:
    if not isinstance(value, str):
        return False
    try:
        uuid.UUID(value)
    except ValueError:
        return False
    return True


def same_id(a: object, b: object) -> bool:
    """UUIDs compare case-insensitively: Swift writes them in capitals."""
    return isinstance(a, str) and isinstance(b, str) and a.lower() == b.lower()


def read_json(path: Path) -> object:
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise CoachError(f"{path} does not exist")
    except json.JSONDecodeError as error:
        raise CoachError(f"{path} is not valid JSON ({error})")


def write_json(path: Path, value: object) -> None:
    """Written through a temp file so a crash never leaves half a proposal."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temp.replace(path)


def review_sort_key(name: str):
    match = _REVIEW_NAME.match(name)
    if not match:
        return None
    return (match.group(1), int(match.group(2) or 1))


def review_folders(home: Path) -> list[Path]:
    """Review folders, oldest first. Anything not named like a review is ignored."""
    root = Path(home) / "reviews"
    if not root.is_dir():
        return []
    named = [(review_sort_key(p.name), p) for p in root.iterdir() if p.is_dir()]
    return [p for key, p in sorted((k, p) for k, p in named if k is not None)]


def new_review_folder(home: Path, today: str | None = None) -> Path:
    """reviews/YYYY-MM-DD, or -2, -3 for a second review the same day."""
    today = today or datetime.now().strftime("%Y-%m-%d")
    root = Path(home) / "reviews"
    candidate = root / today
    number = 2
    while candidate.exists():
        candidate = root / f"{today}-{number}"
        number += 1
    candidate.mkdir(parents=True)
    return candidate


def resolve_review(arg: str | None, home: Path) -> Path:
    if arg:
        folder = Path(arg).expanduser()
        if not folder.is_dir():
            raise CoachError(f"{folder} is not a review folder")
        return folder
    folders = review_folders(home)
    if not folders:
        raise CoachError(f"no reviews under {Path(home) / 'reviews'}; run `coach pull` first")
    return folders[-1]
