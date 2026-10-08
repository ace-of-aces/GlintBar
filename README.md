# Glint

A Liquid Glass replacement for the Touch Bar's Control Strip on macOS 26+.

macOS 27's own Touch Bar UI is in rough shape: volume and brightness popovers hang
instead of closing, and none of it got the Liquid Glass treatment. Glint takes over
the Touch Bar system-wide with its own controls, built on real `NSGlassEffectView`s.

## What it does

- **Full-width Glint bar** over every app: frontmost-app button, media controls
  (previous / play-pause / next), keyboard backlight, display brightness, volume,
  mute and screenshot.
- **Press and slide** on the keyboard, brightness or volume buttons to adjust them in
  place, with a level gauge in the glass and a readout in the middle of the bar.
- **Tap** one of them for a full-width slider with a glass knob that swells while held.
  It **closes itself** after 2.5 s of inactivity (configurable from the menu bar).
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

Commands: `slider:volume`, `slider:display`, `slider:keyboard`, `close`, `appControls`, `glint`.

## How it works

Glint uses private frameworks, all resolved at runtime in
[`Sources/GlintPrivate`](Sources/GlintPrivate) so a missing symbol disables a feature
instead of crashing:

| Feature | API |
| --- | --- |
| System-wide bar, Control Strip button | `NSTouchBar presentSystemModalTouchBar:…`, `DFRElementSetControlStripPresenceForIdentifier` (DFRFoundation) |
| Display brightness | `DisplayServicesGetBrightness` / `SetBrightness` (DisplayServices) |
| Keyboard backlight | `KeyboardBrightnessClient` (CoreBrightness) |
| Media | `MRMediaRemoteSendCommand` (MediaRemote) |
| Volume / mute | CoreAudio (public) |

The whole bar is a single Touch Bar item ([`BarView`](Sources/Glint/TouchBar/BarView.swift)),
so Glint controls layout and the transitions between the main row and the slider row.

Because of the private APIs Glint can't ship on the Mac App Store, and a macOS update
can break it.

## Findings on macOS 27

- `NSGlassEffectView` renders properly on the Touch Bar.
- A Control Strip tray item is squeezed into one slot and replaces one of Apple's items.
- An `NSGlassEffectView` *inside* the Control Strip blacks out the whole Touch Bar, so
  the tray button is a plain `NSButton`.
- After a full-width system modal bar is minimized, the Control Strip drops the tray
  item until it is added again.
