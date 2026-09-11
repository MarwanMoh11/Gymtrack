import WatchKit

/// Wrist feedback. The watch's haptics are the reason the rest timer works
/// with the phone in a bag, so they're used deliberately rather than on every
/// tap: logging a set, finishing a rest, and finishing a workout.
enum WatchHaptics {
    static func tick() { WKInterfaceDevice.current().play(.click) }
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
