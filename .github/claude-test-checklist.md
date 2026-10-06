# The test checklist on every pull request

Every pull request in this repo ends with a **Test before you merge** section written from this file,
whether a Claude run or a local session opened it. The owner reads it on a phone, ticks the boxes in
the pull request as they go, and merges once every box is ticked.

## About the owner

This part is the owner's to edit. Where it disagrees with the rest of the file, it wins.

- I read pull requests on my iPhone, and install builds at my Mac with
  `gh pr checkout <n> && sh scripts/install-phone.sh` (phone plugged in, or on the same Wi-Fi). It's a
  free Apple ID, so there is no TestFlight.
- I wear an Apple Watch; the watch app comes with the phone install.
- I test at home before a workout, never during one, and on my real data.
- Plain words. Tell me what to tap and what I should see, not the code behind it.
- What matters most: logging a set stays fast, and my workout history stays correct.

## The section

```markdown
## Test before you merge

**What changed:** one sentence, as I would notice it in the app.
**Risk:** Low, Medium or High, and why in a few words.
**You need:** Nothing, merge when the checks are green | iPhone, about N minutes | iPhone and watch, about N minutes

**Already covered by tests:** what the suites prove, in a line or two of plain words.

**Install** (at your Mac)
- [ ] Today, gear button, "Export a backup", save it to Files.   (High risk only)
- [ ] `gh pr checkout <n> && sh scripts/install-phone.sh`

**Check the change**
- [ ] Today: tap "Start workout", then log one set. You should see ...

**Check nothing nearby broke**
- [ ] ...

**Then**
- All good: merge.
- Something's off: comment `@claude` and what you saw, here on this pull request.
- Not merging: `git switch main && git pull && sh scripts/install-phone.sh` puts the old build back.
```

The example steps above show the shape; write real ones for the change.

## How to write it

- **Every step is one you could follow from the code.** Read the views you changed and the ones on
  the way to them. Quote each button and label exactly as the app shows it, and start from a tab
  (Today, Plan, Library, Progress); Settings is the gear button on Today. Each step is one action and
  what the owner should then see.
- **Short.** Two to six steps for the change, one to three for nearby things. Set up what a step
  needs the fastest way: log one set, not a whole workout.
- **Check what the issue cares about.** The main path first, then the issue's "What must not
  change" items that the tests can't see.
- **Check the data rules in `CLAUDE.md` when the change touches them.**
  - Something that can be undone: undo it, and check it left no trace (for example, the set is gone
    from History, not shown as zero).
  - A new optional feature: check that logging a set without touching it takes the same taps as
    before.
  - A change to what is saved or exported: one step that shows the new detail in the app. Rely on
    the tests for the backup file itself, and say so in the tests line.
- **The watch.** When `GymTrackWatch/` or the watch link (`WatchLink`, `WatchBridge`,
  `WatchCommandCenter`) changes, add watch steps, including one done on the watch and checked on the
  phone.
- **Widgets and the Live Activity.** When `GymTrackWidgets/` or the Live Activity changes, say where
  to see it: the Lock Screen during a workout, or the widget on the Home Screen.
- **What can't be checked in a few minutes** (a week of history, a rest day, Health data, a given
  date): say so in the tests line and name what covers it in plain words. Never write a step the
  owner can't do.
- **Nothing to see.** For tests, CI, scripts, docs, or a refactor that changes no behavior, write
  "You need: Nothing", one line on why, and leave out every section but **Then**.
- **Don't send the owner to recheck what CI proved.** The tests line is what they can skip.
- **No code names in the steps.** No file paths, type names or test names; the tests line may
  describe a suite in plain words.

Risk:
- **Low**: one screen's text, layout or colour; tests, CI, scripts or docs.
- **Medium**: what a screen does, a calculation, a suggestion, or a new setting.
- **High**: anything under `GymTrack/Models/` (the saved data), backup or restore, the watch link,
  or anything that could lose a set or block logging mid-workout. High adds the backup step and,
  under **Then**, this line in place of the usual one: "Not merging: delete GymTrack from the phone,
  install the old build (`git switch main && git pull && sh scripts/install-phone.sh`), then Today,
  gear button, 'Restore from a backup'". A build that changed the saved data can leave the old one
  unable to open it: it shows "Training data unavailable" with only "Try again", so the data has
  to go before the backup can come back.

## When the pull request changes

After a follow-up comment makes you change the pull request, rewrite the section to match: read
the current body (`gh pr view <n> --json body`), keep the owner's ticks on steps your change didn't
touch, untick or rewrite the ones it did, and save it with `gh pr edit <n> --body-file
build/pr-body.md`. Then say in your comment which steps to redo.
