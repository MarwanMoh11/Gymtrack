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

The Home Screen widgets read their numbers out of an App Group —
`group.com.marwanmohamed.gymtrack`, declared in the Release entitlements for the
app and widgets. If you changed the bundle identifier in step 4, change the
group to match in `GymTrack.entitlements`, `GymTrackWidgets.entitlements`, and
`SharedStore.appGroup`, all three together. App Groups need a paid Apple
Developer account, so the default Debug configuration leaves that entitlement
out and can be installed with a free Apple ID. In that build, the widgets say
"Open GymTrack to fill this in" rather than pretending you have no routine.
Nothing else is affected — the app, the watch and the Live Activity never go
through the group, and starting a workout from a widget is an ordinary
`gymtrack://` link.

Minimum deployment target is **iOS 17**. The Live Activity appears on the Lock
Screen on any supported iPhone; the Dynamic Island presentation needs a device
that has one.

## Running it on your watch

The watch app is embedded in the iPhone app, so it goes wherever the phone app
goes — install GymTrack on your iPhone and the watch app appears in the Watch
app on your phone under *Available Apps*.

Two things worth knowing:

- A locally signed build must provision the physical watch as well as the
  iPhone. Connect and unlock the paired iPhone, then open **Xcode → Open
  Developer Tool → Device Hub**. For iOS/watchOS 26 or earlier, the iPhone must
  be connected to the Mac with a data-capable cable; Xcode 27's **+ → Pair
  Nearby Device…** workflow requires iOS/watchOS 27 or later. Begin pairing the
  Apple Watch; the Developer Mode switch may remain hidden until this step.
  Accept the trust prompts on both devices, then enable **Settings → Privacy &
  Security → Developer Mode** on the watch and restart it when prompted. Back
  in Xcode, select the **GymTrackWatch** scheme and the physical watch and press
  ⌘R once. Xcode then registers the watch and refreshes its provisioning
  profile. If the watch is absent from Xcode, installing it from the iPhone's
  Watch app can fail with “integrity could not be verified.”
- Building the project needs **watchOS platform support** installed in Xcode
  (Xcode → Settings → Components). Without it the iPhone scheme won't build
  either, because it embeds the watch app.
- The watch app's bundle identifier has to be your iPhone app's identifier with
  `.watchkitapp` on the end. If you changed the iPhone one in step 4 above,
  change the watch target's to match and update `WKCompanionAppBundleIdentifier`
  in `GymTrackWatch/Info.plist` to your new iPhone identifier.

Minimum watchOS is **10**. Heart rate and calories need HealthKit permission,
which the watch asks for the first time a session starts.

## What it does

**Today** — the session scheduled for today, its exercises and rep targets, and
a one-tap start. Plus the week at a glance, current streak, and recent sessions.

**Logging** — the next set you have to do is always expanded with big steppers;
everything else collapses out of the way. Tap a number to type it instead of
stepping. The weight you use carries to the remaining sets automatically, and
last session's numbers sit next to each set so you know what to beat. A rest
timer starts on its own when you log a set, keeps time correctly if you lock the
phone, and notifies you when it's up.

**Warm-ups** — one tap builds a ramp up to your working weight: roughly 40, 60
and 80% of it, each pulled onto a rung the machine in front of you actually has,
with the reps coming down as the load goes up. Rungs that land on the same pin,
or on the working weight itself, are dropped rather than logged twice. Warm-ups
are numbered W1, W2, W3 in amber and the work stays 1, 2, 3 in green — adding a
ramp never renumbers the sets you're measured on. They count towards finishing
the session and they're written to Health as part of the time you spent on the
exercise, but they're kept out of volume, records, muscle counts and the "last
time" you're chasing, because a ramp isn't something you're trying to beat. Any
set can be turned into a warm-up, or back, from the chip while you're on it or
by holding a row you've already logged.

**Effort** — after a set the logger asks how hard it was, 6 to 10. It's one
optional tap that never blocks the next set, and it's what tells the app the
difference between a set that had three reps left in it and one that had none.
See *Progressive overload* for what it does with the answer. Turn the question
off in Settings → Effort and everything behaves exactly as it did before.

**Machine weights** — gyms aren't uniform, so the app doesn't pretend they are.
Every exercise knows what its equipment is marked in and what one step is worth:
a barbell moves 2.5 kg, a dumbbell 2, a pin-selected stack 5, and in a pound gym
those become 5, 5 and 10. When a machine disagrees — the leg press is stamped in
pounds, or its stack jumps in fifteens — tap the unit under the weight while
you're logging it, pick kg or lb and the step, and that one exercise is put right
for good. Steppers, the Digital Crown and the app's own progression suggestions
then only ever offer weights that machine can actually be set to. Everything is
still stored in kilograms and converted, so records, volume and Health stay
comparable whatever each machine says; Settings → Machine weights lists anything
you've corrected and the defaults behind everything else.

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

**Home Screen and Siri** — a Today widget carrying the session you're due to do
and a button that starts it, or, once you're training, the exercise you're on,
the sets logged and the rest counting down. A Streak widget for the Home Screen
and the Lock Screen, in circular, rectangular and inline shapes. And "Hey Siri,
start my GymTrack workout" — which also puts GymTrack on the Action Button, in
Spotlight and in Shortcuts, with no setup. Every one of those routes lands in
the logger on the first set, not on the Today tab.

**Apple Watch** — the session, on your wrist. Swipe between three screens:
controls, the set you're on, and what your body is doing. The weight and reps
sit on the Digital Crown — tap a number to attach the crown to it — with a
− / + pair under them for when the crown isn't to hand, and one button logs the
set. The exercise list is a tap away, so a machine that's taken doesn't stop the
session: pick another and both devices move with you. Rest counts down on the
wrist and taps you when it's over, which is the one thing a phone in a locker
can't do. Start a workout on either device and it appears on the other; finish
it on either and it's finished on both. The watch keeps no database of its own —
everything it does is applied on the phone and mirrored straight back, so the
two can't drift — and a set logged out of range is queued and lands when the
watch is back near the phone.

**Heart rate and calories** — starting a session starts a real workout session
on the watch, so the heart rate sensor comes up to workout sampling, the app
keeps running between sets with your wrist down, and the rings move. The live
heart rate shows in the phone's logger too, and the session's average, peak and
active energy are kept with it.

**Apple Health** — a finished session is written as a traditional strength
training workout with one activity per exercise, carrying its sets, reps and
volume, so GymTrack sessions sit in Fitness alongside everything else. Heart
rate and active energy are read back for each session — from any Apple Watch
worn during it, not just ours. Body weight syncs both ways: a weigh-in typed
into GymTrack lands in Health, and one from a connected scale is pulled in.
Each of the three is a separate switch in Settings → Health & Watch, and
deleting a session in GymTrack removes its workout from Health too.

**Progressive overload** — double progression, built in. Clear the top of the
rep range on every set and the app tells you to add weight and reset to the
bottom of the range. Fall short and it tells you to hold the load or back off.
The weight it names is always the next rung on that machine, never a number
between two pins.

Effort ratings sharpen all of that, because reps alone can't tell a set you
finished with three in the tank from one that nearly buried you. Clear the range
at RPE 7 and it moves you two rungs instead of one, which is what stops a plain
double progression crawling back up through weights you already owned. Clear it
at RPE 10 and it still adds weight, but says to expect a fight. Fall short at
RPE 7 and it stops suggesting a deload — the load isn't what stopped you, so
taking weight off would be fixing the wrong thing. Rate nothing and every
suggestion is identical to what it was.

**Personal records** — recognised on estimated 1RM, so heavier-for-fewer and
lighter-for-more both count. Celebrated the moment you log the set.

**Plan** — multiple routines, one active. Four starter templates (Push/Pull/Legs,
Upper/Lower, Full Body 3×, Minimalist Strength) or build one from scratch. Every
day, exercise, set count, rep range and rest interval is editable.

**Library** — 410 exercises, filterable by muscle and equipment, and searched the
way people actually type: word by word rather than as one literal string, with
gym shorthand folded in. "lat pull down" finds the Lat Pulldowns, "incline db
press" finds the Incline Dumbbell Press, "rdl" finds the Romanian Deadlifts.
Each one shows its full history: a progression chart (est. 1RM, top set or
volume), your bests, and every session you've done it in.

Build your own for whatever the bundled library hasn't got — straight from the
search box, including mid-workout, where it drops into the session as soon as
you save it. Custom exercises can be edited and deleted afterwards. Anything
redundant can be swiped away and restored later from Library ▸ Hidden; hiding
only governs search and browsing, so a hidden exercise already in a plan or your
history keeps its name and its numbers.

**Progress** — streaks, volume per day, a body heatmap showing which muscles are
on target for the week and which are falling behind, a 16-week consistency grid,
body weight over the last twelve weeks, and your PR board.

**Backups** — export everything as a single JSON file, restore it on any device.
The app's folder is visible in Files (On My iPhone → GymTrack), so a backup can
be dropped in and restored without leaving the phone.

## Project layout

```
GymTrack/            The iPhone app
├── App/            App entry point, tab shell, session presentation
├── Models/         SwiftData entities, exercise catalog, muscle taxonomy
├── Services/       Stats, overload, rest timer, backup, templates,
│                   Live Activity, HealthKit, the watch link
├── DesignSystem/   Shared components, haptics
├── Features/       One folder per screen area
└── Resources/      exercises.json — the bundled exercise library

GymTrackWatch/       The watch app — mirror of the session, wrist logging,
                     and the HKWorkoutSession that records heart rate
GymTrackShared/      Compiled into every target: theme tokens, weight units,
                     the Live Activity's attributes, and the phone/watch
                     payloads
GymTrackWidgets/     Widget extension — the Lock Screen and Dynamic Island
                     presentations of a running session, plus the Today and
                     Streak widgets for the Home and Lock Screens
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
- The phone owns the data, including during a watch session: the watch sends a
  command, the phone applies it through the same code path its own UI uses — the
  same PR check, the same load carried to the next set — and pushes the result
  back. The one thing the watch does locally is draw a logged set as done
  immediately, because waiting for a round trip before the button responds is
  unusable in a gym. That optimism is reconciled against the next mirror.
- When the watch drove a session it saves the workout to Health itself, since it
  holds the beat-by-beat heart rate. The phone waits for the watch's workout ID
  rather than racing it to a duplicate, and writes its own copy only when no
  watch was involved.
- The widgets get a small snapshot written into the App Group rather than a
  share of the database. Moving the SwiftData store into the group container
  would strand the history already on anyone's device, and a widget only ever
  needs a dozen numbers — so the app restamps those whenever they move, the same
  arrangement the watch has and for the same reason.
- Nothing outside the app can start a workout: a session needs the store, the
  plan behind today, the progression that picks the opening weights, a Live
  Activity and the watch link. So all of it ends in the app. The widget's own
  button is a plain `gymtrack://start-today` link, which needs nothing shared
  with the widget's process; Siri, the Action Button and a Shortcut go through
  an App Intent that leaves a note for the app to read as it comes to the front,
  and notes older than two minutes are dropped rather than replayed.
- The store's path is stated outright in `GymTrackApp` rather than left to
  SwiftData's default, because that default is `NSPersistentContainer`'s — which
  moves to the App Group container the moment an app has the app-groups
  entitlement. Adding that entitlement for the widgets would otherwise have
  pointed the app at a new empty store and left every existing session unread in
  the old location, which on an installed copy looks exactly like losing your
  training history.
- `SampleData.swift` fills the app with a couple of months of plausible history
  for design work. It's `#if DEBUG` only; launch with `-GTSeedSampleData`.

This replaces an earlier Next.js/Firebase web version of GymTrack. That code is
still in the git history if you want it — the bundled exercise library came from
it.
