"""Optional F05 CC0 material download. Network required ONLY when invoked.

Run from project root: python tools/fetch_cc0.py
The simulator itself never downloads, requires a connection or sends data.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "assets" / "polyhaven"
BASE = "https://dl.polyhaven.org/file/ph-assets/Textures"
ASSET = "rocks_ground_01"
FILES = {
    "diff": ("jpg", "jpg"),
    "nor_gl": ("png", "png"),
    "rough": ("jpg", "jpg"),
}
MAX_BYTES = 10 * 1024 * 1024


def fetch() -> list[dict]:
    TARGET.mkdir(parents=True, exist_ok=True)
    report = []
    for tag, (folder, ext) in FILES.items():
        filename = f"{ASSET}_{tag}_1k.{ext}"
        url = f"{BASE}/{folder}/1k/{ASSET}/{filename}"
        dest = TARGET / filename
        try:
            with urlopen(Request(url, headers={"User-Agent": "RocketLandingRL-F05/0.5.6"}), timeout=30) as response:
                data = response.read(MAX_BYTES + 1)
            if len(data) > MAX_BYTES or len(data) < 1000:
                raise ValueError(f"Invalid image size {len(data)}")
            if ext == "png" and not data.startswith(b"\x89PNG\r\n\x1a\n"):
                raise ValueError("Not a PNG image")
            if ext == "jpg" and not data.startswith(b"\xff\xd8\xff"):
                raise ValueError("Not a JPEG image")
            dest.write_bytes(data)
            report.append({"url": url, "file": str(dest.relative_to(ROOT)).replace('\\', '/'),
                           "size_bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "status": "OK"})
        except Exception as exc:
            report.append({"url": url, "file": str(dest.relative_to(ROOT)).replace('\\', '/'),
                           "status": "FAIL", "error": str(exc)})
    (TARGET / "download_receipt.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    result = fetch()
    for item in result:
        print(f"{item['status']}: {item['file']} {item.get('error', item.get('sha256', ''))}")
    if not all(item['status'] == "OK" for item in result):
        raise SystemExit(1)
    print("F05 CC0 textures downloaded. Reopen Godot editor to import new files.")
