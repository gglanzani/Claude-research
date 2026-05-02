"""PowerPoint iPhone remote — Flask server bridging the web UI to AppleScript."""

from __future__ import annotations

import socket
import subprocess
from pathlib import Path

from flask import Flask, jsonify, request, send_from_directory

try:
    from Quartz import (
        CGDisplayBounds,
        CGEventCreate,
        CGEventCreateMouseEvent,
        CGEventGetLocation,
        CGEventPost,
        CGMainDisplayID,
        kCGEventMouseMoved,
        kCGHIDEventTap,
        kCGMouseButtonLeft,
    )
    HAS_QUARTZ = True
except ImportError:
    HAS_QUARTZ = False

APP_DIR = Path(__file__).parent
SCRIPT_DIR = APP_DIR / "applescripts"
STATIC_DIR = APP_DIR / "static"

ACTIONS = {
    "next": "next.applescript",
    "prev": "prev.applescript",
    "start": "start.applescript",
    "end": "end.applescript",
    "laser": "laser.applescript",
}

app = Flask(__name__, static_folder=str(STATIC_DIR), static_url_path="")


def run_applescript(name: str) -> tuple[bool, str]:
    path = SCRIPT_DIR / name
    result = subprocess.run(
        ["osascript", str(path)],
        capture_output=True,
        text=True,
        timeout=5,
    )
    msg = (result.stderr or result.stdout).strip()
    return result.returncode == 0, msg


@app.route("/")
def index():
    return send_from_directory(str(STATIC_DIR), "index.html")


@app.route("/api/<action>", methods=["POST"])
def control(action: str):
    script = ACTIONS.get(action)
    if not script:
        return jsonify(ok=False, error="unknown action"), 404
    ok, msg = run_applescript(script)
    return jsonify(ok=ok, message=msg)


@app.route("/api/move", methods=["POST"])
def move():
    if not HAS_QUARTZ:
        return jsonify(ok=False, error="pyobjc Quartz not available"), 500
    data = request.get_json(force=True, silent=True) or {}
    dx = float(data.get("dx", 0))
    dy = float(data.get("dy", 0))

    loc = CGEventGetLocation(CGEventCreate(None))
    bounds = CGDisplayBounds(CGMainDisplayID())
    new_x = max(0.0, min(bounds.size.width - 1, loc.x + dx))
    new_y = max(0.0, min(bounds.size.height - 1, loc.y + dy))

    ev = CGEventCreateMouseEvent(
        None, kCGEventMouseMoved, (new_x, new_y), kCGMouseButtonLeft
    )
    CGEventPost(kCGHIDEventTap, ev)
    return jsonify(ok=True, x=new_x, y=new_y)


def local_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


if __name__ == "__main__":
    port = 8080
    print(f"PPT Remote running — open http://{local_ip()}:{port} on your iPhone")
    app.run(host="0.0.0.0", port=port, threaded=True)
