import SwiftUI

/// The wait before `WatchRestFocus` brings the countdown back, in a view of
/// its own. It restarts with every second of a scroll, and anything else that
/// read the touch would be re-evaluated with it.
struct WatchRestReturnClock: View {
    var focus: WatchRestFocus
    var rest: WatchRestTimer
    /// Called once the countdown is due back, after `focus` has counted it.
    let onReturn: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private struct Key: Hashable {
        var touchedAt: Date?
        var resting: Bool
        var questionWaiting: Bool
        var voiceOver: Bool
    }

    private var key: Key {
        Key(touchedAt: focus.touchedAt, resting: rest.isRunning,
            questionWaiting: focus.questionWaiting, voiceOver: voiceOverEnabled)
    }

    var body: some View {
        Color.clear
            .task(id: key) {
                // Moving the screen moves the VoiceOver cursor with it, so a
                // VoiceOver reader stays wherever they put themselves, the same
                // as the effort question that never folds away for them.
                guard !voiceOverEnabled else { return }
                // Restarted at most once a second by a scroll, so its last
                // frames can land after the wait was worked out. Each pass works
                // it out again from the exact last touch.
                while let due = focus.returnDue(resting: rest.isRunning, now: .now) {
                    let wait = due.timeIntervalSinceNow
                    if wait > 0 {
                        do { try await Task.sleep(for: .seconds(wait)) } catch { return }
                    } else if focus.bringBackIfDue(resting: rest.isRunning, now: .now) {
                        onReturn()
                        return
                    }
                }
            }
    }
}

extension View {
    /// Tells `focus` each time this content is scrolled. Goes on the content
    /// inside a `ScrollView`.
    ///
    /// Read from where the content sits on screen rather than from a gesture:
    /// a gesture laid over a scroll view competes with it for the finger, and
    /// the Digital Crown never makes one.
    @MainActor
    func reportsScrolling(to focus: WatchRestFocus) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear
                    .onChange(of: geometry.frame(in: .global).minY) { _, _ in
                        focus.touch(at: .now)
                    }
            }
        }
    }
}
