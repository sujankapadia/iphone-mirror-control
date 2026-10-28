# iphone-mirror-control

See and operate your iPhone from your Mac, programmatically — capture the phone
screen, tap, type, scroll, navigate. Built on macOS **iPhone Mirroring**, with
no jailbreak, no Developer Mode, no provisioning profile, and nothing to
install.

Packaged as a [Claude Code](https://claude.com/claude-code) skill (`/phone`),
but `phone.sh` is a standalone script with no agent dependency.

## Why this exists

Apple's real automation story — XCUITest, Appium, WebDriverAgent — is built for
*testing apps you own*. It needs Developer Mode, a signed WebDriverAgent build
on the device, and USB or network pairing. Maestro doesn't support real iPhones
at all, simulators only. Shortcuts automates *tasks* through app-provided
actions, not arbitrary UI.

None of that covers "let me drive my own personal phone from my laptop." This
does, by treating the iPhone Mirroring window as what it is: a video feed you
can screenshot and a surface you can post synthetic input into.

It is a hack. See [Limitations](#limitations) before building on it.

## Requirements

Everything is built into macOS — no installs, no dependencies.

- macOS Sequoia 15+ on Apple silicon or a T2 Mac
- iPhone with iOS 18+ and a passcode set
- Same Apple Account on both, two-factor on
- Wi-Fi and Bluetooth on, Personal Hotspot off
- One Mac to one iPhone at a time
- **Not available in the EU**

Accessibility permission is required for the terminal app you run this from
(System Settings → Privacy & Security → Accessibility), since synthetic input
goes through `CGEvent`.

## Install

```bash
git clone https://github.com/sujankapadia/iphone-mirror-control.git
ln -s "$PWD/iphone-mirror-control" ~/.claude/skills/phone   # for Claude Code
```

The Swift input helper compiles itself on first use (`swiftc` ships with Xcode
or the Command Line Tools) and is cached in `$TMPDIR`.

## Usage

```bash
open -a "iPhone Mirroring"    # then unlock the phone by hand, once

./phone.sh status             # is the session up?
./phone.sh shot               # capture the phone screen; prints a PNG path
./phone.sh tap 397 727        # IMAGE pixel coords, read off the last shot
./phone.sh swipe 326 1000 326 400
./phone.sh scroll 326 900 -5  # + up, - down
./phone.sh type "hello"
./phone.sh key return         # return|delete|escape|tab|space|arrows
./phone.sh home | apps | spotlight
./phone.sh quit               # end the session, give the phone back
```

## How it works

**Coordinates are image pixels, never screen points.** You read a coordinate off
a screenshot, so that's what you pass. `phone.sh` records the window origin and
scale factor at `shot` time and does the conversion. If the window moved since
that shot, it refuses the tap instead of clicking somewhere wrong.

Three things that are load-bearing, each found by it breaking:

1. **The app must be frontmost or clicks are swallowed.** A synthetic click on
   a background window is consumed activating that window and never reaches the
   phone UI. The identical click fails backgrounded and works activated.

2. **Capture by window id, never by screen region.** `screencapture -R<rect>`
   grabs whatever pixels are on screen at that rectangle — so any window
   stacked on top is captured *instead of the phone*, silently and with no
   error. This script resolves the real `CGWindowID` via
   `CGWindowListCopyWindowInfo` and uses `screencapture -l<id>`, which captures
   the window even when fully occluded.

3. **The window moves and resizes.** It relocates the moment the mirroring
   session connects, and again later. Geometry is re-read from the window
   server on every command; nothing is cached.

Navigation uses iPhone Mirroring's own View menu (Home Screen, App Switcher,
Spotlight) rather than synthesized edge swipes, which is far more reliable.

## Performance

The shell work is about 1.2s per step: activate ~260ms, post event ~430ms,
window lookup plus capture ~600ms.

For an AI agent driving this, **the dominant cost is reading the screenshot** —
a model inference pass, several seconds, larger than everything above combined.
That puts a full see-decide-act cycle at roughly 5–15s. Two mitigations:

- **Batch known coordinates.** Typing a string is one call and one capture, not
  one per character.
- **To check merely _whether_ the screen changed, diff the PNG checksum**
  rather than reading the image.

## Limitations

- **There is no accessibility tree.** The entire mirrored phone is a single
  opaque `group` to the macOS accessibility API — it's a video stream. No
  element IDs, no labels, no waiting on a condition. Pixels are the only
  interface, which makes this inherently brittle: a moved button is a missed
  tap.
- **It monopolizes the phone.** iPhone Mirroring requires the handset locked;
  you cannot use it while a session runs.
- **Blind between captures.** No way to wait on a condition, only to sleep and
  look again.
- **It resumes the app that was open on the phone**, not the Home Screen.

Good for "open Settings and read me the iOS version" or "what does that
notification say". Bad for anything repetitive or timing-sensitive. If you want
*reliable repeated* automation, use Shortcuts or a real XCUITest setup instead.

## Privacy

This drives a personal phone, with mail, messages, photos and accounts on it.
The bundled skill instructs the agent to operate it only when asked in the
current exchange, and to stay on the requested task — not to open other apps or
read messages it wasn't pointed at, even when they're on screen. Screenshots
land in `$TMPDIR/phone` and vanish with the session.

## License

MIT
