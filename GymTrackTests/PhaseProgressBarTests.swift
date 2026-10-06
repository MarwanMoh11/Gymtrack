import Testing
import SwiftUI
@testable import GymTrack

/// Protects `PhaseProgressBar`, the row of set ticks under the logger's header,
/// in the dock, on Today, on the wrist and on the Lock Screen, against the
/// values its animation hands it.
///
/// The bar is `Animatable`, so SwiftUI draws it at every count between the old
/// one and the new, and the spring it rides on carries it a little past the new
/// one before settling. Undoing the only logged set sends the count from one to
/// none, the spring dipped just below zero, and the tick loop trapped on a range
/// with a negative end (#2). These render the bar rather than read a property,
/// because the trap was in the drawing. No legacy `Tests/*.swift` counterpart.
@MainActor @Suite(.serialized)
struct PhaseProgressBarTests {

    /// The pixels of a three-set bar drawn at `progress` sets, the way SwiftUI
    /// draws one frame of the animation.
    private func pixels(at progress: Double) -> Data? {
        var bar = PhaseProgressBar(completed: 0, total: 3, phase: .working)
        bar.animatableData = progress
        let renderer = ImageRenderer(content: bar.frame(width: 120))
        guard let data = renderer.cgImage?.dataProvider?.data else { return nil }
        return data as Data
    }

    @Test func aLitTickChangesWhatIsDrawn() {
        // Without this the comparison below would also pass on two blank
        // images from a renderer that never ran the bar's drawing.
        let empty = pixels(at: 0)
        #expect(empty != nil)
        #expect(pixels(at: 1) != empty)
    }

    @Test(arguments: [-0.001, -0.05, -0.5])
    func aSpringDippingBelowZeroDrawsAnEmptyBar(progress: Double) {
        #expect(pixels(at: progress) == pixels(at: 0))
    }
}
