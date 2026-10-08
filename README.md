# Glint

A Liquid Glass replacement for the Touch Bar's Control Strip on macOS 26+.

macOS 27's own Touch Bar UI is in rough shape: volume and brightness popovers hang
instead of closing, and none of it got the Liquid Glass treatment. Glint takes over
the Touch Bar system-wide with its own controls, built on real `NSGlassEffectView`s.

## What it does

- **Full-width Glint bar** over every app: frontmost-app button, media controls
  (previous / play-pause / next), keyboard backlight, display brightness, volume,
  mute and screenshot.
- **Sliders that pop out of their button**, like the native Control Strip: touch the
  keyboard, brightness or volume button and a fixed-size slider grows out of it
  straight away, with the same touch dragging the knob (relative to where it is, so
  the level never jumps). The knob is solid at rest and turns into a clear glass lens
  while dragged.
- When the finger lifts, an ✕ appears in the button's slot and the slider **closes
  itself** 1.5 s later (configurable from the menu bar).
- **Play/pause shows the real playback state** (see below).
- **App controls**: tap the app icon on the left to hand the Touch Bar back to the
  frontmost app's own controls. The ✨ button in Apple's Control Strip brings Glint back.
- Menu bar item for switching modes, the auto-close delay and launch at login.

## Build & run

Requires Xcode 26+ and a Mac with a Touch Bar (13" M1/M2 MacBook Pro on macOS 27).

```bash
./scripts/build-app.sh            # builds build/Glint.app
./scripts/build-app.sh --install  # also copies it to ~/Applications and launches it
```

For development, `swift build && .build/debug/Glint` runs it without a bundle
(launch at login is only available from the `.app`).

Debug builds accept commands over a distributed notification, which makes it possible
to drive the bar without touching it and capture it with `screencapture -b`:

```bash
osascript -l JavaScript -e 'ObjC.import("Foundation"); $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("center.julian.Glint.debug", "slider:volume", $(), true)'
```

Commands simulate a finger on a level button (x positions in bar points):
`down:volume` (or `down:volume:850`), `move:700`, `up`, `tap:display`; plus `close`,
`appControls` and `glint`.

## How it works

Glint uses private frameworks, all resolved at runtime in
[`Sources/GlintPrivate`](Sources/GlintPrivate) so a missing symbol disables a feature
instead of crashing:

| Feature | API |
| --- | --- |
| System-wide bar, Control Strip button | `NSTouchBar presentSystemModalTouchBar:…`, `DFRElementSetControlStripPresenceForIdentifier` (DFRFoundation) |
| Display brightness | `DisplayServicesGetBrightness` / `SetBrightness` (DisplayServices) |
| Keyboard backlight | `KeyboardBrightnessClient` (CoreBrightness) |
| Media commands | `MRMediaRemoteSendCommand` (MediaRemote) |
| Playback state | MediaRemote, queried from inside `/usr/bin/perl` ([`GlintNowPlaying`](Sources/GlintNowPlaying)) |
| Volume / mute | CoreAudio (public) |

Since macOS 15.4 MediaRemote tells third-party processes that nothing is playing.
`NowPlayingMonitor` therefore loads the small `libGlintNowPlaying.dylib` into the
Apple-signed `/usr/bin/perl`, which may still ask, and reads its state changes as JSON
lines. The helper exits when Glint's end of its stdin pipe closes.

The whole bar is a single Touch Bar item ([`BarView`](Sources/Glint/TouchBar/BarView.swift)),
so Glint controls layout and the transitions between the main row and the level panel.

Because of the private APIs Glint can't ship on the Mac App Store, and a macOS update
can break it.
