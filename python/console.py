"""Small console+file logger for F03 checks. Never changes physics or protocol."""
from __future__ import annotations

from pathlib import Path
import sys
import traceback
from collections.abc import Callable


def execute(label: str, callback: Callable[[Callable[[str], None]], None]) -> int:
    """Show progress immediately and save it even if Windows closes a console window."""
    path = Path(__file__).resolve().parents[1] / "logs" / "f03" / "console" / f"f03_last_{label}.log"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        output = path.open("w", encoding="utf-8")
    except OSError as exc:
        print(f"F03: unable to open log {path}: {exc}", file=sys.stderr, flush=True)
        return 1
    with output:
        def write(message: str) -> None:
            print(message, flush=True)
            output.write(message + "\n")
            output.flush()

        write(f"F03 {label.upper()} — starting. Log: {path}")
        write("The remote scene is scenes/remote.tscn (F6); F5 starts the manual scene.")
        try:
            callback(write)
        except Exception as exc:
            write(f"F03 {label.upper()} ERROR: {type(exc).__name__}: {exc}")
            detail = traceback.format_exc()
            output.write(detail + "\n")
            output.flush()
            print(detail, file=sys.stderr, flush=True)
            write("Check that Godot shows 'MODE: REMOTE TCP' and port 55423.")
            return 1
        write(f"F03 {label.upper()} PASS")
        return 0
