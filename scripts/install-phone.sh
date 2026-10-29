#!/bin/sh
# Puts GymTrack on the phone, and keeps it opening.
#
#   sh scripts/install-phone.sh               build this working tree and install it
#   sh scripts/install-phone.sh --refresh     re-sign and reinstall what was installed last
#   sh scripts/install-phone.sh --schedule    run --refresh in the background from now on
#   sh scripts/install-phone.sh --unschedule  stop doing that
#
# A free Apple ID signs an app for seven days, counted from when Xcode made the
# provisioning profile, not from the install. Xcode reuses a cached profile
# until it runs out, so rebuilding is not enough: the 2.1 install on 29
# September carried a profile from the 24th and stopped opening two days later,
# the day before a workout. Every build here first moves GymTrack's cached
# profiles aside, so each install starts a full week.
#
# The watch app runs out the same way, on its own clock: it only gets a new
# copy when this Mac can reach the watch at install time, and only if the
# profile lists the watch. Neither held for a week in October, and the watch
# app stopped opening on the 24th, mid-workout, until it was reinstalled by
# hand. So the watch is registered whenever its profile leaves it out, its
# copy's expiry is kept apart from the phone's, and the refresh acts as soon
# as the watch is in reach with its copy close to running out.
#
# A refresh rebuilds the exact source that was last installed, kept under
# refs/gymtrack/on-phone, rather than whatever the tree holds now. Installing
# older code over a store a newer build has written leaves the app unable to
# open it.
#
# The phone has to be reachable: plugged in, or on the same Wi-Fi with
# "Connect via network" ticked for it in Xcode's Devices window. The scheduled
# run tries every six hours and only acts once two days have passed, so a few
# missed chances cost nothing.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)

PHONE="${GYMTRACK_PHONE:-00008150-000504383447401C}"
WATCH="${GYMTRACK_WATCH:-00008301-508225811A13C02E}"
WORK="$ROOT/build/phone"
REF=refs/gymtrack/on-phone
# Where a snapshot waits until it is actually on the phone, so a build that
# fails doesn't become what every later refresh tries to rebuild.
PENDING=refs/gymtrack/installing
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
LABEL=com.marwanmohamed.gymtrack.refresh
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
# Two days less an hour, so a run every six hours lands inside the window
# rather than just missing it and waiting another six.
REFRESH_AFTER_MINUTES=2820
STAMP="$WORK/last-install"
EXPIRES="$WORK/expires"
# The copy on the watch, written only when an install there succeeds. A build
# the watch never got does nothing for the one it runs.
WATCH_EXPIRES="$WORK/watch-expires"
# How close the watch's copy may run to its expiry before the refresh stops
# waiting for the phone's two days and takes the first chance to reach it.
WATCH_DUE_SECONDS=259200
APP="$WORK/dd/Build/Products/Debug-iphoneos/GymTrack.app"
WATCH_APP="$APP/Watch/GymTrackWatch.app"
NOTIFIER_APP="$WORK/GymTrack Notifier.app"
NOTIFIER="$NOTIFIER_APP/Contents/MacOS/notifier"

mkdir -p "$WORK"

say() { echo "$(date '+%Y-%m-%d %H:%M') $*"; }

# Notification Centre, each message at most once every twenty hours. A run
# every six hours repeating the same problem would teach you to ignore it, but
# a different problem still gets through. A second argument of "now" skips
# the wait, for a message someone at the Mac just asked for.
notify() {
    say "$1"
    NOTIFIED=1
    last="$WORK/last-notice-$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
    if [ "${2:-}" != now ] && [ -f "$last" ] && [ -z "$(find "$last" -mmin +1200 2>/dev/null)" ]; then
        return 0
    fi
    # Under GymTrack's own name and icon where the notifier is built and
    # allowed; osascript's, with Script Editor's icon, where it isn't.
    if ! { [ -x "$NOTIFIER" ] && limit 90 "$NOTIFIER" "Phone refresh" "$1" >/dev/null 2>&1; }; then
        osascript -e "display notification \"$1\" with title \"GymTrack\"" >/dev/null 2>&1 || true
    fi
    touch "$last"
}

# Runs a command, killed after the given number of seconds. A keychain prompt
# nobody sees or a device that stops answering would otherwise hang the run
# for good, and a hung run never gets as far as saying anything.
limit() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

# A recorded expiry, in seconds since 1970, or nothing if unknown. The phone
# build's by default; the watch's copy given $WATCH_EXPIRES.
expires_at() {
    value=$(cat "${1:-$EXPIRES}" 2>/dev/null || true)
    case "$value" in ''|*[!0-9]*) ;; *) echo "$value" ;; esac
}

reachable() {
    line=$(xcrun devicectl list devices 2>/dev/null | grep -F "$1" || true)
    [ -n "$line" ] && ! printf '%s\n' "$line" | grep -q unavailable
}

# The working tree as it is, untracked files included, as a commit under
# $PENDING. Nothing on any branch moves and the real index is not touched.
snapshot() {
    index="$WORK/snapshot-index"
    rm -f "$index"
    GIT_INDEX_FILE="$index" git add -A
    tree=$(GIT_INDEX_FILE="$index" git write-tree)
    rm -f "$index"
    commit=$(git commit-tree "$tree" -p HEAD -m "On the phone since $(date '+%Y-%m-%d %H:%M')")
    git update-ref "$PENDING" "$commit"
    say "Snapshot $(git rev-parse --short "$commit") of $(git rev-parse --abbrev-ref HEAD) at $(git rev-parse --short HEAD)"
}

# Moved, not deleted, so a failed fetch can be undone by hand.
set_profiles_aside() {
    [ -d "$PROFILES" ] || return 0
    aside="$WORK/old-profiles"
    mkdir -p "$aside"
    for profile in "$PROFILES"/*.mobileprovision; do
        [ -e "$profile" ] || continue
        if security cms -D -i "$profile" 2>/dev/null | grep -q 'com\.marwanmohamed\.gymtrack'; then
            mv "$profile" "$aside/"
        fi
    done
}

xcode_build() {
    rm -rf "$WORK/dd"
    limit 1800 xcodebuild -project "$WORK/src/GymTrack.xcodeproj" -scheme GymTrack -configuration Debug \
        -destination 'generic/platform=iOS' -derivedDataPath "$WORK/dd" \
        -allowProvisioningUpdates build > "$WORK/build.log" 2>&1
}

# Building the watch app for the watch itself registers it with the signing
# team, which a build for a generic phone never does.
register_watch() {
    limit 1800 xcodebuild -project "$WORK/src/GymTrack.xcodeproj" -scheme GymTrackWatch -configuration Debug \
        -destination "id=$WATCH" -derivedDataPath "$WORK/watch-dd" \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration build > "$WORK/watch-build.log" 2>&1
}

# Whether a watch app's profile names this watch. A build whose profile leaves
# it out is one the watch turns down at install.
lists_watch() {
    security cms -D -i "$1/embedded.mobileprovision" 2>/dev/null | grep -qF "$WATCH"
}

build_snapshot() {
    src="$WORK/src"
    rm -rf "$src"
    mkdir -p "$src"
    git archive "$1" | tar -x -C "$src"
    set_profiles_aside
    say "Building"
    build_for_phone || return 1
    # The profile lists the devices registered to the team, and a free team
    # has dropped the watch before: the profile made on 25 October left it
    # out. Registered while it's in reach, the next profile lists it.
    if [ -d "$WATCH_APP" ] && ! lists_watch "$WATCH_APP" && reachable "$WATCH"; then
        say "Registering the watch, which this build's profile leaves out"
        if register_watch; then
            set_profiles_aside
            say "Building again with the watch in the profile"
            build_for_phone || return 1
        else
            say "Couldn't register the watch. See build/phone/watch-build.log."
        fi
    fi
}

build_for_phone() {
    xcode_build && return 0
    # With nothing cached, Xcode can fetch one target's profile twice in a
    # single build and delete the first copy while another target is still
    # signing with it: "Build input file cannot be found". The profiles this
    # build fetched are fresh and in place by then, so a second build uses
    # them and fetches nothing.
    if grep -q 'Build input file cannot be found: .*Provisioning Profiles' "$WORK/build.log"; then
        say "Building again: Xcode replaced a profile mid-build"
        xcode_build && return 0
    fi
    grep -E 'error:' "$WORK/build.log" | sort -u | head -5
    return 1
}

expiry_of() {
    security cms -D -i "$1/embedded.mobileprovision" 2>/dev/null > "$WORK/profile.plist" || return 1
    plutil -extract ExpirationDate raw -o - "$WORK/profile.plist"
}

install_built() {
    say "Installing on the phone"
    if ! limit 300 xcrun devicectl device install app --device "$PHONE" "$APP" > "$WORK/install.log" 2>&1; then
        tail -5 "$WORK/install.log"
        return 1
    fi
    touch "$STAMP"
    if phone_expiry=$(expiry_of "$APP") &&
        date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$phone_expiry" +%s > "$EXPIRES.new" 2>/dev/null; then
        mv "$EXPIRES.new" "$EXPIRES"
        say "Phone build signed until $(date -r "$(expires_at)" '+%a %d %b %H:%M')"
    else
        rm -f "$EXPIRES.new" "$EXPIRES"
        notify "GymTrack is installed but its expiry couldn't be read, so the warning before it runs out won't come from this Mac."
    fi

    [ -d "$WATCH_APP" ] || return 0
    # Not left to the phone's automatic app install: a copy it passes on is
    # still turned down by a watch the profile leaves out.
    if ! reachable "$WATCH"; then
        watch_left "Can't reach the watch from this Mac"
        return 0
    fi
    if ! lists_watch "$WATCH_APP"; then
        watch_left "The watch isn't in this build's signing profile"
        return 0
    fi
    if ! limit 300 xcrun devicectl device install app --device "$WATCH" "$WATCH_APP" >> "$WORK/install.log" 2>&1; then
        tail -5 "$WORK/install.log"
        watch_left "The watch install failed"
        return 0
    fi
    if watch_expiry=$(expiry_of "$WATCH_APP") &&
        date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$watch_expiry" +%s > "$WATCH_EXPIRES.new" 2>/dev/null; then
        mv "$WATCH_EXPIRES.new" "$WATCH_EXPIRES"
        say "Watch app installed, signed until $(date -r "$(expires_at "$WATCH_EXPIRES")" '+%a %d %b %H:%M')"
    else
        rm -f "$WATCH_EXPIRES.new" "$WATCH_EXPIRES"
        say "Watch app installed; its expiry couldn't be read"
    fi
}

# Says why the watch kept the copy it has, and until when that copy opens. Its
# end is a notification once it is two days off or past: the watch says
# nothing before its app stops opening.
watch_left() {
    expiry=$(expires_at "$WATCH_EXPIRES")
    if [ -z "$expiry" ]; then
        say "$1. The watch keeps the copy it has, which this Mac has no expiry for."
        return 0
    fi
    when=$(date -r "$expiry" '+%A at %H:%M')
    left=$((expiry - $(date +%s)))
    if [ "$left" -le 0 ]; then
        notify "$1. GymTrack on the watch stopped opening $when. Keep the watch on and near this Mac so the refresh can reinstall it."
    elif [ "$left" -lt 172800 ]; then
        notify "$1. GymTrack on the watch stops opening $when. Keep the watch on and near this Mac so the refresh can reach it."
    else
        say "$1. The watch keeps the copy signed until $(date -r "$expiry" '+%a %d %b %H:%M')."
    fi
}

# Whether the watch's copy is close enough to running out that the refresh
# shouldn't wait for the phone's two days: its expiry unknown or inside
# $WATCH_DUE_SECONDS, and the watch in reach to take a new one.
watch_due() {
    expiry=$(expires_at "$WATCH_EXPIRES")
    if [ -n "$expiry" ] && [ $((expiry - $(date +%s))) -ge "$WATCH_DUE_SECONDS" ]; then
        return 1
    fi
    reachable "$WATCH" && return 0
    [ -n "$expiry" ] && watch_left "Can't reach the watch from this Mac"
    return 1
}

refresh() {
    if ! git rev-parse -q --verify "$REF" >/dev/null; then
        notify "Nothing has been installed with install-phone.sh yet, so there is nothing to refresh."
        return 1
    fi
    if [ -f "$STAMP" ] && [ -z "$(find "$STAMP" -mmin +$REFRESH_AFTER_MINUTES 2>/dev/null)" ]; then
        # The phone is fresh, but the watch's copy runs out on its own clock,
        # and this may be the first time in days the watch is in reach.
        watch_due || return 0
        say "Refreshing early for the watch"
    fi
    # A device build made some other way since the last install is probably
    # what the phone runs now. Rebuilding the snapshot would put older code
    # over it.
    newer=$(find "$HOME/Library/Developer/Xcode/DerivedData" "$ROOT/build" \
                -path "$WORK" -prune -o -path '*Index.noindex*' -prune -o \
                -type d -name GymTrack.app -path '*-iphoneos/*' -newer "$STAMP" -print 2>/dev/null | head -1)
    if [ -n "$newer" ]; then
        notify "GymTrack was built for a phone outside install-phone.sh. Run it once by hand so the refresh knows what is installed."
        return 1
    fi
    if ! reachable "$PHONE"; then
        expiry=$(expires_at)
        if [ -n "$expiry" ] && [ $((expiry - $(date +%s))) -lt 172800 ]; then
            notify "Can't reach the phone to refresh GymTrack, which stops opening $(date -r "$expiry" '+%A at %H:%M'). Plug it in or join this Mac's Wi-Fi."
        fi
        return 0
    fi
    say "Refreshing"
    build_snapshot "$REF" || { notify "The GymTrack refresh failed to build. See build/phone/build.log."; return 1; }
    install_built || { notify "The GymTrack refresh built but couldn't install. See build/phone/install.log."; return 1; }
}

# A one-file Mac app whose only job is to post notify()'s messages, so they
# arrive with the phone app's icon. Rebuilt by --schedule.
build_notifier() {
    say "Building the notifier"
    rm -rf "$NOTIFIER_APP"
    mkdir -p "$NOTIFIER_APP/Contents/MacOS" "$NOTIFIER_APP/Contents/Resources"
    xcrun swiftc -O scripts/notifier/main.swift -o "$NOTIFIER"
    iconset="$WORK/AppIcon.iconset"
    rm -rf "$iconset"
    mkdir -p "$iconset"
    master="$iconset/icon_512x512@2x.png"
    xcrun swift scripts/notifier/make-icon.swift \
        GymTrack/Assets.xcassets/AppIcon.appiconset/icon-1024.png "$master"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$master" --out "$iconset/icon_${size}x${size}.png" >/dev/null
        [ "$size" -eq 512 ] ||
            sips -z $((size * 2)) $((size * 2)) "$master" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$iconset" -o "$NOTIFIER_APP/Contents/Resources/AppIcon.icns"
    rm -rf "$iconset"
    cat > "$NOTIFIER_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.marwanmohamed.gymtrack.notifier</string>
    <key>CFBundleName</key><string>GymTrack</string>
    <key>CFBundleDisplayName</key><string>GymTrack</string>
    <key>CFBundleExecutable</key><string>notifier</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
    codesign --force --sign - "$NOTIFIER_APP"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$NOTIFIER_APP"
}

schedule() {
    build_notifier
    mkdir -p "$(dirname "$AGENT")"
    cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>$ROOT/scripts/install-phone.sh</string>
        <string>--refresh</string>
    </array>
    <key>StartInterval</key><integer>21600</integer>
    <key>RunAtLoad</key><true/>
    <key>Nice</key><integer>10</integer>
    <key>StandardOutPath</key><string>$WORK/refresh.log</string>
    <key>StandardErrorPath</key><string>$WORK/refresh.log</string>
</dict>
</plist>
PLIST
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$AGENT"
    say "Scheduled: every six hours, acting once two days have passed. Log: build/phone/refresh.log"
    # Now, while you're at the Mac: the first one asks permission to notify,
    # and a request first seen during a failed refresh at 3 a.m. goes unanswered.
    notify "Notifications from the phone refresh look like this." now
}

unschedule() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$AGENT"
    say "Unscheduled"
}

# One run at a time: a scheduled refresh starting during a manual install
# would rebuild into the same folders.
LOCK="$WORK/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then
        rmdir "$LOCK" && mkdir "$LOCK"
    else
        say "Another run is in progress"
        exit 0
    fi
fi
# Any way out of a refresh that failed without saying so says so here: a
# command failing under set -e, a timeout, anything not foreseen above.
finish() {
    status=$?
    rmdir "$LOCK" 2>/dev/null || true
    if [ "$status" -ne 0 ] && [ "${1:-}" = --refresh ] && [ -z "${NOTIFIED:-}" ]; then
        notify "The GymTrack refresh stopped unexpectedly (exit $status). See build/phone/refresh.log."
    fi
    exit "$status"
}
NOTIFIED=
MODE="${1:-}"
trap 'finish "$MODE"' EXIT

case "${1:-}" in
    --refresh) refresh ;;
    --schedule) schedule ;;
    --unschedule) unschedule ;;
    "")
        reachable "$PHONE" || { say "The phone ($PHONE) isn't reachable. Plug it in or join this Mac's Wi-Fi."; exit 1; }
        snapshot
        build_snapshot "$PENDING"
        install_built
        git update-ref "$REF" "$PENDING"
        git update-ref -d "$PENDING"
        ;;
    *) sed -n '2,7p' "$0"; exit 2 ;;
esac
