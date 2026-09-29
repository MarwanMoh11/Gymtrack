/// Stands in for `GymTrack/DesignSystem/Haptics.swift`, which drives UIKit
/// feedback generators and cannot be built for the Mac. `RestTimer.swift` is
/// compiled as it ships, and only needs the two calls it makes.
enum Haptics {
    static func tick() {}
    static func success() {}
}
