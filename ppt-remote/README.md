# PPT Remote

Tiny webserver that turns your iPhone into a PowerPoint remote for your Mac.
PowerPoint is driven entirely through AppleScript files in `applescripts/`;
the only non-AppleScript piece is cursor movement (the laser pad), which uses
macOS' `Quartz` event API via `pyobjc`.

## Features

- Previous / next slide
- Start / end presentation mode
- Toggle PowerPoint's built-in laser pointer (sends `L` to PowerPoint)
- Touch pad for relative cursor movement (acts as the physical laser)
- Prev/next buttons stay reachable while using the pad

## Setup (Mac)

1. Install dependencies (Python 3.10+ recommended):

   ```sh
   pip install -r requirements.txt
   ```

2. Grant the terminal you'll launch the server from these permissions in
   **System Settings → Privacy & Security**:
   - **Accessibility** — required for `System Events` keystrokes and for moving
     the cursor.
   - **Automation** — first run will prompt for control of "Microsoft
     PowerPoint" and "System Events"; click *OK*.

3. Launch the server:

   ```sh
   python server.py
   ```

   It prints something like
   `PPT Remote running — open http://192.168.1.42:8080 on your iPhone`.

## Use (iPhone)

1. Make sure the iPhone is on the same Wi-Fi as the Mac.
2. Open the printed URL in Safari. Tap the share icon → *Add to Home Screen*
   for a full-screen app feel.
3. Buttons:
   - **Start Show / End Show** — runs/exits the slide show.
   - **Prev / Next** — advances slides (works in or out of presentation mode).
   - **Laser: Off/On** — toggles PowerPoint's laser pointer (only visible while
     a slide show is running).
   - **Drag pad** — moves the Mac's cursor relatively. Combine with *Laser: On*
     to use it as a laser pointer during presentation. Prev/next buttons stay
     visible above and below the pad.

## How it's wired

- `server.py` — Flask app exposing `POST /api/<action>` for PowerPoint
  controls and `POST /api/move` for cursor deltas.
- `applescripts/*.applescript` — one file per PowerPoint action. Each is run
  via `osascript`. Edit them to tweak behavior.
- `static/index.html` — single-page iPhone UI (touch-friendly, dark mode,
  works as a Home Screen web app).

## Troubleshooting

- **"not authorized to send Apple events"** — Grant Automation permission to
  the terminal/Python (System Settings → Privacy & Security → Automation).
- **Cursor doesn't move** — The Quartz cursor API needs Accessibility
  permission on modern macOS; grant it to the terminal/Python.
- **Laser key does nothing** — PowerPoint's laser only works while a slide
  show is running and the PowerPoint window has focus.
