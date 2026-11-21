# Snapdrag

A menu bar screenshot and screen recording app for macOS, built for personal use.

## Features

- **Capture** an area, a window, or the full screen, and repeat the last area.
- **Floating thumbnail** after each capture that you can drag straight into another app.
  Nothing is saved to disk unless you choose Save.
- **Clipboard**: captures are copied automatically.
- **Annotation editor**: arrows, shapes, pen, highlighter, text, numbered steps, pixelate, blur, crop, undo.
- **Capture history** with automatic clean-up.
- **Capture Text**: select an area and copy the text in it (on-device OCR).
- **Screen recording** to MP4 or GIF, with optional computer audio and microphone.
- **Global shortcuts** for every action, changeable in Settings.

## Requirements

- macOS 27 or later
- Xcode 27 or later
- An "Apple Development" signing certificate (free: add your Apple ID in Xcode → Settings → Accounts)

## Building

```sh
./build.sh           # build the development version
./build.sh run       # build the development version and launch it
./build.sh install   # build the release version, install it in /Applications,
                     # set it to open at login, and launch it
```

The project file contains no developer team ID. `build.sh` reads the team from the
Apple Development certificate in your keychain, or from `DEVELOPMENT_TEAM` if you set it.
If you build from the Xcode window instead, pick your team under Signing & Capabilities,
and don't commit that change.

## First run

Snapdrag needs the **Screen & System Audio Recording** permission, and asks for it on first launch.
To use ⇧⌘3, ⇧⌘4 and ⇧⌘5, turn off the built-in screenshot shortcuts in
System Settings → Keyboard → Keyboard Shortcuts → Screenshots.

## Default shortcuts

| Shortcut | Action |
|---|---|
| ⇧⌘3 | Capture full screen |
| ⇧⌘4 | Capture area |
| ⇧⌘5 | Capture window |
| ⇧⌘6 | Repeat last area |
| ⇧⌘2 | Capture text |
| ⇧⌘7 | Record screen (press again to stop) |
