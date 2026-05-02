# PPT Remote (Swift)

Standalone macOS menu-bar app that turns your iPhone into a PowerPoint
remote. PowerPoint is driven by AppleScript; cursor movement (laser pad)
goes through `CGEvent`. No Python or third-party dependencies.

## Features

- Menu-bar app (no Dock icon) showing the connect URL
- Built-in HTTP server on `:8080` (Network framework, `NWListener`)
- Bundled AppleScripts handle prev/next, start/end show, laser toggle
- Touch pad moves the macOS cursor — works as a physical laser when
  PowerPoint's laser pointer is on
- Prev/next stay reachable while using the laser pad

## Build

Requires Xcode 15+ (or Swift 5.9+ command-line tools) and macOS 13+.

```sh
./build.sh
open "dist/PPT Remote.app"
```

Or, for development:

```sh
swift run
```

`build.sh` produces a notarization-ready `.app` in `dist/` and ad-hoc signs
it. For distribution, replace the `codesign --sign -` step with your
Developer ID identity and run `xcrun notarytool submit`.

## First-run permissions

macOS will prompt for two grants the first time:

1. **Automation → Microsoft PowerPoint / System Events** — driven by
   `NSAppleEventsUsageDescription` in `Info.plist`.
2. **Accessibility** — required for `CGEvent` cursor posting. Open
   *System Settings → Privacy & Security → Accessibility* and toggle
   *PPT Remote* on.

Optionally, *Local Network* on macOS 15+ for serving over Wi-Fi.

## Use

1. Click the menu-bar icon, copy the URL (e.g. `http://192.168.1.42:8080`).
2. Open it in Safari on your iPhone (same Wi-Fi). *Add to Home Screen* for
   a full-screen launcher.
3. Buttons: *Start Show*, *End Show*, *Prev*, *Next*, *Laser On/Off*.
   Drag the pad to move the cursor.

## Project layout

```
ppt-remote-mac/
├── Package.swift              SwiftPM manifest, declares resources
├── Info.plist                 Bundle metadata + usage descriptions
├── build.sh                   swift build + .app assembly
├── Sources/PPTRemote/
│   ├── main.swift             NSApplication entry
│   ├── AppDelegate.swift      Menu bar item, server lifecycle, local IP
│   ├── HTTPServer.swift       NWListener-backed HTTP/1.1 parser+server
│   ├── Router.swift           Maps /api/<action> → AppleScript or move
│   ├── AppleScriptRunner.swift  Spawns osascript on bundled scripts
│   ├── CursorMover.swift      CGEvent cursor posting
│   └── Resources/
│       ├── index.html         iPhone UI
│       └── Scripts/*.applescript
```

## Tweaking PowerPoint behavior

All PowerPoint interaction lives in `Sources/PPTRemote/Resources/Scripts/`.
Edit those files (or open them in Script Editor) and rebuild — no Swift
changes needed.

## Distribution notes

- For other Macs to run the app without "unidentified developer" warnings,
  sign with a Developer ID Application certificate and notarize.
- For App Store distribution you'd need to replace `Process` (running
  `osascript`) with a sandboxed alternative — `NSAppleScript` from in-process,
  declared `com.apple.security.temporary-exception.apple-events` per-target,
  and the cursor mover would need an Accessibility entitlement.
