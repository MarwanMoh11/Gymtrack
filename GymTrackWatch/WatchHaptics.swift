import WatchKit

/// Wrist feedback. The watch's haptics are the reason the rest timer works
/// with the phone in a bag, so they're used deliberately rather than on every
/// tap: logging a set, finishing a rest, and finishing a workout.
enum WatchHaptics {
    static func tick() { WKInterfaceDevice.current().play(.click) }
    /// Saying a set is beginning. `.start` is the system's own word for it and
    /// is a rising tap rather than the click every other control here uses, so
    /// the one thing on this screen that gets confirmed without being looked at
    /// is the one thing that feels different.
    static func start() { WKInterfaceDevice.current().play(.start) }
    static func log() { WKInterfaceDevice.current().play(.success) }
    static func restOver() { WKInterfaceDevice.current().play(.notification) }
    static func finish() { WKInterfaceDevice.current().play(.stop) }
    static func celebrate() {
        let device = WKInterfaceDevice.current()
        device.play(.success)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            device.play(.directionUp)
        }
    }
}
