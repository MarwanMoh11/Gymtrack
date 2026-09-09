# GymTrack

A native iOS workout tracker. Build a routine, log every set as you lift, and
watch the numbers move.

Everything lives on the device — no account, no server, no network. It works in
a basement gym with no signal, and your training history is yours.

## Running it on your phone

1. Open `GymTrack.xcodeproj` in Xcode.
2. Select the project in the navigator → **GymTrack** target → **Signing &
   Capabilities**.
3. Tick **Automatically manage signing** and pick your Apple ID under *Team*
   (add one in Xcode → Settings → Accounts if it isn't there).
4. Change the **Bundle Identifier** to something unique to you, e.g.
   `com.yourname.gymtrack`. A free Apple ID can't reuse an identifier someone
   else has registered.
5. Plug in your iPhone, select it in the device menu at the top, and press ⌘R.
6. The first launch is blocked by iOS: on the phone go to **Settings → General →
   VPN & Device Management**, tap your developer certificate, and trust it.

With a free Apple ID the app stays installed for **7 days** before it needs
re-running from Xcode. A paid Apple Developer account raises that to a year.

Minimum deployment target is **iOS 17**. The Live Activity appears on the Lock
Screen on any supported iPhone; the Dynamic Island presentation needs a device
that has one.

## What it does

**Today** — the session scheduled for today, its exercises and rep targets, and
a one-tap start. Plus the week at a glance, current streak, and recent sessions.

**Logging** — the next set you have to do is always expanded with big steppers;
everything else collapses out of the way. Tap a number to type it instead of
stepping. The weight you use carries to the remaining sets automatically, and
last session's numbers sit next to each set so you know what to beat. A rest
timer starts on its own when you log a set, keeps time correctly if you lock the
phone, and notifies you when it's up.

**Putting a session down** — pull the logger down by its handle, or tap
*Minimise*, and it shrinks into a bar above the tab bar that keeps the clock,
the set count and the rest countdown in view. Tap it to go back. The session
survives leaving the app, switching tabs and force-quitting; discarding it is a
separate, deliberate button at the bottom of the logger, never the price of
getting out of the screen.

**Live Activity** — while a session is open it's on the Lock Screen and in the
Dynamic Island: which exercise and set is up, the weight and rep target, the
rest countdown ticking down on its own, sets logged and volume moved. When the
rest runs out the card says so without the app having to wake up. Tapping it
lands straight back on the set you were about to do.

**Progressive overload** — double progression, built in. Clear the top of the
rep range on every set and the app tells you to add weight and reset to the
bottom of the range. Fall short and it tells you to hold the load or back off.

**Personal records** — recognised on estimated 1RM, so heavier-for-fewer and
lighter-for-more both count. Celebrated the moment you log the set.

**Plan** — multiple routines, one active. Four starter templates (Push/Pull/Legs,
Upper/Lower, Full Body 3×, Minimalist Strength) or build one from scratch. Every
day, exercise, set count, rep range and rest interval is editable.

**Library** — 414 exercises, searchable and filterable by muscle and equipment.
Each one shows its full history: a progression chart (est. 1RM, top set or
volume), your bests, and every session you've done it in. Add your own exercises
too.

**Progress** — streaks, volume per day, a body heatmap showing which muscles are
on target for the week and which are falling behind, a 16-week consistency grid,
and your PR board.

**Backups** — export everything as a single JSON file, restore it on any device.
The app's folder is visible in Files (On My iPhone → GymTrack), so a backup can
be dropped in and restored without leaving the phone.

## Project layout

```
GymTrack/            The app
├── App/            App entry point, tab shell, session presentation
├── Models/         SwiftData entities, exercise catalog, muscle taxonomy
├── Services/       Stats, overload, rest timer, backup, templates, Live Activity
├── DesignSystem/   Shared components, haptics
├── Features/       One folder per screen area
└── Resources/      exercises.json — the bundled exercise library

GymTrackShared/      Compiled into both targets: theme tokens, and the
                     Live Activity's attributes and content state
GymTrackWidgets/     Widget extension — the Lock Screen and Dynamic Island
                     presentations of a running session
```

Built with SwiftUI, SwiftData and Swift Charts. No third-party dependencies.

## Notes

- Weights are stored in kilograms and converted for display, so switching
  between kg and lb never rewrites your history.
- An unfinished session survives a force-quit — the app picks it back up on
  launch (minimised or open, whichever you left it), re-adopts its Live Activity
  rather than starting a second one, and closes out anything older than 12 hours.
- `Text(timerInterval:)` is the only clock a Live Activity keeps running on its
  own, so the rest countdown uses it; how finely it ticks is the system's call.
  Everything else on the card — including the session length — is a label the
  app restamps on every change, which is also why it never shows blank digits.
- `SampleData.swift` fills the app with a couple of months of plausible history
  for design work. It's `#if DEBUG` only; launch with `-GTSeedSampleData`.

This replaces an earlier Next.js/Firebase web version of GymTrack. That code is
still in the git history if you want it — the 414-exercise library came from it.
