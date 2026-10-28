---
name: phone
description: "See and operate the user's iPhone from the Mac through iPhone Mirroring — capture the phone screen, tap, type, scroll, and navigate. Use when the user asks you to look at something on their phone, read a notification or message, open an app on the phone, or drive the phone UI. Not for taking photos with the phone's camera — that is the `snap` skill."
---

## What this does

macOS iPhone Mirroring puts the live iPhone screen in a Mac window. This skill
captures that window so I can see the phone, and posts synthetic input into it
so I can operate the phone. The helper is `phone.sh` in this skill's directory.

This is a **pixel-driven** remote control: I read a screenshot, work out where
to tap, and post the event. There is no element tree (see Gotchas), so every
interaction depends on me looking at the screen.

## Requirements

Everything is built into macOS — no installs. Per Apple:

- macOS Sequoia 15+ on Apple silicon or a T2 Mac
- iPhone with iOS 18+ and a passcode
- Same Apple Account on both, 2FA on, Wi-Fi + Bluetooth on, Hotspot off
- One Mac to one iPhone at a time
- **Not available in the EU**

First launch of a session needs the user to unlock the phone by hand. **The
phone is locked and unusable by the user for as long as the session runs.**

## Usage

```bash
P=~/.claude/skills/phone/phone.sh

"$P" status                   # is the session up?
"$P" shot                     # capture; prints a PNG path -- then Read it
"$P" tap 397 727              # IMAGE pixel coords, read off the last shot
"$P" swipe 326 1000 326 400   # drag (scroll gestures, sheets)
"$P" scroll 326 900 -5        # scroll wheel; + up, - down
"$P" type "hello"
"$P" key return               # return|delete|escape|tab|space|arrows
"$P" home | apps | spotlight  # navigate via the View menu
"$P" quit                     # end the session, give the phone back
```

If iPhone Mirroring is not running: `open -a "iPhone Mirroring"`, then wait for
the user to unlock on the handset.

## The loop

1. `shot` → `Read` the PNG. That is my eyes.
2. Find the target in the image, note its **image pixel** coordinates.
3. `tap` / `swipe` / `type` with those coordinates.
4. `shot` again only if the outcome is actually uncertain.

**Coordinates are always image pixels, never screen points.** `phone.sh` stores
the window origin and scale at `shot` time and converts for me. If the window
moved since the last shot it refuses rather than tapping the wrong place —
take a fresh `shot` and re-read the coordinates.

## Cost model

The shell is cheap: ~1.2s of real work per step (activate 260ms, event 430ms,
window lookup + capture 600ms). **The expensive part is me reading the PNG** —
a model inference pass, several seconds, dwarfing everything else. So:

- **Batch known coordinates.** Typing a string is one `type` call and one
  capture, not one per character. If a tab bar's position is already known from
  an earlier shot, chain taps and capture once at the end.
- **Don't re-capture to confirm the obvious.** Verify uncertain outcomes only.
- **To check merely *whether* the screen changed, diff the PNG checksum**
  (`md5 -q`) against the previous shot instead of reading the image. Cheap.

## Gotchas

- **The app must be frontmost or clicks are swallowed.** A synthetic click on a
  background window is consumed activating it and never reaches the phone.
  `phone.sh` activates before every input — this is load-bearing, verified:
  the identical click failed backgrounded and worked activated.
- **Capture by window id, never by screen region.** `screencapture -R<rect>`
  grabs whatever pixels are on screen, so any window stacked on top is
  captured *instead of the phone*. This silently returns a screenshot of the
  wrong app. `phone.sh` uses `-l<windowid>` from `CGWindowListCopyWindowInfo`,
  which captures the window even when occluded.
- **The window moves and resizes on connect**, and again later. It went from
  `336,106 640x662` to `872,33 326x720` the moment the session came up. Never
  cache geometry across commands; `phone.sh` re-reads it every time.
- **There is no accessibility tree.** The entire mirrored phone is a single
  opaque `group` to System Events — it is a video stream. No element IDs, no
  labels, no waiting on a condition. Pixels are the only interface.
- **It resumes the app that was open on the phone**, not the Home Screen.
- Use the View-menu commands (`home`, `apps`, `spotlight`) rather than
  synthesizing edge swipes; they are far more reliable.

## When this is the wrong tool

It is brittle (a moved button means a missed tap), blind between captures,
slow, and it monopolizes the user's phone. Fine for "open Settings and tell me
the iOS version" or "read me that message". Bad for anything repetitive or
timing-sensitive.

For *reliable repeated* automation, point the user at **Shortcuts** (Apple's
sanctioned path, automates tasks rather than UI) or a real **XCUITest/Appium**
setup (accessibility-driven, robust — but needs Developer Mode and a signed
WebDriverAgent, and is built for testing apps you own). Don't reach for this
skill to build a recurring job.

## Privacy

This is the user's personal phone, with their mail, messages, photos and
accounts on it. Operate it when the user has asked in the current exchange,
and **stay on the task they asked for** — don't open other apps, scroll through
their inbox, or read messages I wasn't pointed at, even when they're on screen.
Screenshots land in `$TMPDIR/phone` and vanish with the session; don't copy
them somewhere durable without asking.

When done, `quit` the session so the user gets their phone back.
