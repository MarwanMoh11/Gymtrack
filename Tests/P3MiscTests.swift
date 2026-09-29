import Foundation

/// Run with scripts/test-p3-misc.sh; no simulator, device, Siri or Health
/// needed, and none of them is exercised here.
///
/// Four small decisions from the 2026-09-28 review, each one a pure rule or a
/// file the rule can be read off:
///
/// * DATA-12: the screen is held awake by a rule, not by the setting alone.
/// * HK-11: the phone asks Health for exactly the types it uses.
/// * HK-12: an intent's note is read whichever of "app comes forward" and
///   "`perform()` writes the note" happens first, and once.
/// * SESS-07: a rest found over long after its end does not chime.
///
/// What this cannot reach: whether `isIdleTimerDisabled` is set from the right
/// callbacks, what the Health sheet lists, whether the system runs `perform()`
/// before or after the scene is active, and whether the notification and the
/// chime overlap. Those need a device.
@main
struct P3MiscTests {

    @MainActor static func main() {
        screenIsHeldAwakeOnlyDuringAnOpenWorkoutInView()
        healthAsksForExactlyWhatThePhoneUses()
        aNoteIsReadWhicheverArrivesFirst()
        aNoteIsTakenOnce()
        anAnnouncementBeforeTheAppIsReadyLeavesTheNote()
        aLateRestDoesNotChimeAgain()
        print("P3MiscTests passed")
    }

    // MARK: - DATA-12

    static func screenIsHeldAwakeOnlyDuringAnOpenWorkoutInView() {
        for setting in [false, true] {
            for workout in [false, true] {
                for active in [false, true] {
                    let held = ScreenAwakeRules.holdsScreenAwake(
                        setting: setting, workoutOpen: workout, appIsActive: active)
                    let expected = setting && workout && active
                    precondition(held == expected,
                                 "setting \(setting), workout \(workout), active \(active) gave \(held)")
                }
            }
        }
        // The case the review found: the setting on by default, the app open
        // on Progress or Today with no workout, and the phone never locking.
        precondition(!ScreenAwakeRules.holdsScreenAwake(setting: true, workoutOpen: false, appIsActive: true),
                     "With no workout the phone must be allowed to lock")
        precondition(!ScreenAwakeRules.holdsScreenAwake(setting: true, workoutOpen: true, appIsActive: false),
                     "A backgrounded or inactive app holds nothing")
    }

    // MARK: - HK-11

    /// Reads the service's source rather than importing it, because the service
    /// needs a store, a container and HealthKit's entitlements. The permission
    /// sets are written as literal identifier lists so that this can hold them
    /// to the queries next to them.
    ///
    /// `HEALTH_SERVICE_PATH` points the check at another copy of the file, so
    /// that it can be run against the version from before the fix.
    static func healthAsksForExactlyWhatThePhoneUses() {
        let path = ProcessInfo.processInfo.environment["HEALTH_SERVICE_PATH"]
            ?? "GymTrack/Services/HealthKitService.swift"
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            fatalError("Cannot read \(path); run from the repository root")
        }
        let source = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")

        func identifiers(in declaration: String) -> Set<String> {
            guard let start = source.range(of: declaration),
                  let open = source.range(of: "= [", range: start.upperBound..<source.endIndex),
                  let close = source.range(of: "]", range: open.upperBound..<source.endIndex)
            else { return [] }
            return Set(matches(of: #"\.(\w+)"#, in: String(source[open.upperBound..<close.lowerBound])))
        }
        let read = identifiers(in: "readQuantityIdentifiers")
        let share = identifiers(in: "shareQuantityIdentifiers")

        precondition(read == ["heartRate", "activeEnergyBurned", "bodyMass"],
                     "The phone reads heart rate, active energy and body weight, and nothing else: \(read.sorted())")
        precondition(share == ["bodyMass"],
                     "The phone writes body weight; its workouts add no energy samples: \(share.sorted())")

        // Every quantity a query names has to be one the sheet asked for, and
        // every one the sheet asks for has to have a query.
        let queried = Set(matches(of: #"(?:forIdentifier|identifier):\s*\.(\w+)"#, in: source))
        precondition(queried.isSubset(of: read.union(share)),
                     "A query names a type the sheet never asks for: \(queried.subtracting(read.union(share)).sorted())")
        precondition(read.isSubset(of: queried),
                     "The sheet asks to read a type nothing queries: \(read.subtracting(queried).sorted())")
        precondition(source.contains("HKQuantitySample("),
                     "Body weight is requested for sharing, so something must write a sample")

        for retired in ["restingHeartRate", "basalEnergyBurned", "activitySummaryType"] {
            precondition(!source.contains(retired),
                         "\(retired) is recovery or unused data and is not the phone's to request")
        }
        precondition(source.contains("HKObjectType.workoutType()"),
                     "Workouts are read and shared: the phone writes them and finds them again to delete")
    }

    static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    // MARK: - HK-12

    /// What an intent's `perform()` does, and what the app's activation does,
    /// in both orders. The listener stands for `RootView` hearing the
    /// announcement; the drain stands for it reading on activation.
    @MainActor static func aNoteIsReadWhicheverArrivesFirst() {
        _ = SharedStore.takeAction()
        let center = NotificationCenter()
        let inbox = PendingActionHandoff.Inbox()
        inbox.open()
        var started: [SharedStore.PendingAction] = []
        let listener = center.addObserver(forName: PendingActionHandoff.didRequest, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { if let action = inbox.take() { started.append(action) } }
        }
        defer { center.removeObserver(listener) }

        // Activation first, the order that used to lose the start: the read
        // finds nothing, and `perform()` then runs.
        precondition(inbox.take() == nil)
        PendingActionHandoff.hand(.startToday, center: center)
        precondition(started == [.startToday],
                     "A note written after the app came forward must start the workout when it is announced")

        // `perform()` first: the note is there when the app comes forward.
        started = []
        SharedStore.request(.startFreestyle)
        precondition(inbox.take() == .startFreestyle)
    }

    @MainActor static func aNoteIsTakenOnce() {
        _ = SharedStore.takeAction()
        let center = NotificationCenter()
        let inbox = PendingActionHandoff.Inbox()
        inbox.open()
        var started = 0
        let listener = center.addObserver(forName: PendingActionHandoff.didRequest, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { if inbox.take() != nil { started += 1 } }
        }
        defer { center.removeObserver(listener) }

        PendingActionHandoff.hand(.startToday, center: center)
        // The activation that follows the announcement reads again.
        if inbox.take() != nil { started += 1 }
        precondition(started == 1, "One tap on a shortcut started \(started) workouts")
    }

    @MainActor static func anAnnouncementBeforeTheAppIsReadyLeavesTheNote() {
        _ = SharedStore.takeAction()
        let center = NotificationCenter()
        let inbox = PendingActionHandoff.Inbox()
        var started: [SharedStore.PendingAction] = []
        let listener = center.addObserver(forName: PendingActionHandoff.didRequest, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { if let action = inbox.take() { started.append(action) } }
        }
        defer { center.removeObserver(listener) }

        // The announcement arrives while `RootView` has not yet adopted the
        // unfinished session it was left with. Acting now would begin a second
        // workout beside it.
        PendingActionHandoff.hand(.startToday, center: center)
        precondition(started.isEmpty, "A start must wait for the unfinished session to be adopted")

        inbox.open()
        precondition(inbox.take() == .startToday,
                     "The note must still be there when the app is ready to read it")
        precondition(inbox.take() == nil)
    }

    // MARK: - SESS-07

    static func aLateRestDoesNotChimeAgain() {
        let end = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func chimes(lateBy seconds: TimeInterval) -> Bool {
            RestChimeRules.chimesOnExpiry(endsAt: end, now: end.addingTimeInterval(seconds))
        }
        precondition(chimes(lateBy: 0), "A rest that ends in view chimes")
        precondition(chimes(lateBy: 0.3), "The ticker runs every quarter second, so it is at most this late in view")
        precondition(chimes(lateBy: 1.5), "A brief stall in the foreground is still a rest the lifter watched")

        // The review's own check: a 30 s rest, the phone locked for 60 s. The
        // notification was delivered 30 s earlier, and the chime is not owed.
        precondition(!chimes(lateBy: 30), "A rest that ended 30 s ago was announced by its notification")
        precondition(!chimes(lateBy: 600), "So was one that ended ten minutes ago")
        precondition(!chimes(lateBy: RestChimeRules.lateTolerance + 0.5))
    }
}
