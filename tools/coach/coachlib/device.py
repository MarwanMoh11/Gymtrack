"""The phone, through `xcrun devicectl` (development-signed builds only).

The approach to finding the phone is scripts/install-phone.sh's: the device id
from GYMTRACK_PHONE, else the id that script defaults to, and "reachable" means
the device is listed and not marked unavailable.
"""
from __future__ import annotations

import os
import re
import shlex
import subprocess
from pathlib import Path

from .util import CoachError

BUNDLE_ID = "com.marwanmohamed.gymtrack"
SNAPSHOT_PATH = "Documents/Coach/snapshot.json"
DECISIONS_PATH = "Documents/Coach/decisions.json"
INBOX_PATH = "Documents/Coach/Inbox/proposal.json"
TIMEOUT = 120

NOT_REACHABLE = ("The phone is not reachable (unlock it and connect it by cable or on the same Wi-Fi, "
                 "then try again). Without the phone, export a backup from Settings and pass it with "
                 "`coach pull --file PATH`.")


def devicectl() -> list[str]:
    """`xcrun devicectl`, or whatever COACH_DEVICECTL names (the tests' stand-in)."""
    return shlex.split(os.environ.get("COACH_DEVICECTL") or "xcrun devicectl")


def _run(args: list[str]) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(devicectl() + args, capture_output=True, text=True, timeout=TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise CoachError(f"devicectl did not run: {error}")


def _install_script_default() -> str | None:
    script = Path(__file__).resolve().parents[3] / "scripts" / "install-phone.sh"
    try:
        match = re.search(r'PHONE="\$\{GYMTRACK_PHONE:-([^}]+)\}"', script.read_text())
    except OSError:
        return None
    return match.group(1) if match else None


def _listing() -> list[str]:
    result = _run(["list", "devices"])
    return result.stdout.splitlines() if result.returncode == 0 else []


def _available(line: str) -> bool:
    return "unavailable" not in line


def find_phone() -> str | None:
    """The phone's device id, or None when it is not reachable right now."""
    lines = _listing()
    wanted = os.environ.get("COACH_PHONE") or os.environ.get("GYMTRACK_PHONE") or _install_script_default()
    if wanted:
        for line in lines:
            if wanted in line and _available(line):
                return wanted
    candidates = [line for line in lines if "iPhone" in line and "physical" in line and _available(line)]
    if len(candidates) == 1:
        match = re.search(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-F]{8}-(?:[0-9A-F]{4}-){3}[0-9A-F]{12}", candidates[0])
        if match:
            return match.group(0)
    return None


def require_phone() -> str:
    phone = find_phone()
    if phone is None:
        raise CoachError(NOT_REACHABLE)
    return phone


def _file_args(device: str) -> list[str]:
    return ["--device", device, "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE_ID]


def copy_from(device: str, source: str, destination: Path) -> str | None:
    """Copies one file off the phone. Returns None on success, else why not."""
    result = _run(["device", "copy", "from", *_file_args(device), "--source", source,
                   "--destination", str(destination)])
    if result.returncode != 0 or not Path(destination).exists():
        return (result.stderr or result.stdout).strip()[-400:] or "devicectl failed"
    return None


def copy_to(device: str, source: Path, destination: str) -> str | None:
    result = _run(["device", "copy", "to", *_file_args(device), "--source", str(source),
                   "--destination", destination])
    if result.returncode != 0:
        return (result.stderr or result.stdout).strip()[-400:] or "devicectl failed"
    return None
