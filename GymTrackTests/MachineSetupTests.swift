import Foundation
import SceneKit
import SwiftData
import Testing
import UIKit
@testable import GymTrack

// What this file protects: the machine an exercise is done on and the positions
// the lifter saved. Nothing is stored until the lifter taps something, a tapped
// position can be taken back without a trace, and a logged set keeps the setup
// it was done at even after the setup changes. The bundled models must hang
// together, because a rig that names a group or adjustment it doesn't have
// would draw a part in the wrong place and call it the lifter's setting.

@MainActor @Suite(.serialized)
struct MachineSetupTests {
    private let chestPress = "machine-chest-press"
    private let panatta = "panatta-chest-press"

    // MARK: The bundled machines

    @Test func everyBundledMachineDecodesAndHangsTogether() throws {
        let rigs = MachineCatalog.all
        #expect(rigs.map(\.id) == ["panatta-chest-press", "panatta-incline-press", "life-fitness-cable-crossover",
                                   "life-fitness-g7", "cybex-leg-press", "cybex-leg-extension"])
        let library = Set(ExerciseCatalog.shared.builtIn.map(\.id))
        for rig in rigs {
            let adjustments = Set(rig.adjustments.map(\.id))
            let groups = Set((rig.groups ?? []).map(\.id))
            #expect(!rig.parts.isEmpty && !rig.adjustments.isEmpty, "\(rig.id) draws or sets nothing")
            #expect(rig.exercises.allSatisfy(library.contains), "\(rig.id) names an exercise the library lacks")
            for a in rig.adjustments {
                #expect((a.options == nil) != (a.positions == nil), "\(rig.id).\(a.id) is neither pins nor a choice")
                #expect(a.range.contains(a.value), "\(rig.id).\(a.id) is drawn at a position it doesn't have")
            }
            for group in rig.groups ?? [] {
                if let drive = group.drive { #expect(adjustments.contains(drive.adj), "\(rig.id).\(group.id)") }
                if let parent = group.parent { #expect(groups.contains(parent), "\(rig.id).\(group.id)") }
            }
            for part in rig.parts {
                if let g = part.g { #expect(groups.contains(g), "\(rig.id) part in missing group \(g)") }
                if let hl = part.hl { #expect(adjustments.contains(hl), "\(rig.id) lights missing \(hl)") }
            }
            for station in rig.stations ?? [] {
                #expect(station.adjustments.allSatisfy(adjustments.contains), "\(rig.id) station \(station.name)")
            }
        }
    }

    @Test(arguments: [
        ("machine-chest-press", "panatta-chest-press"),
        ("incline-chest-press-machine", "panatta-incline-press"),
        ("cable-crossover", "life-fitness-cable-crossover"),
        ("cable-crossover", "life-fitness-g7"),
        ("pull-up", "life-fitness-cable-crossover"),
        ("leg-press", "cybex-leg-press"),
        ("leg-extension-machine", "cybex-leg-extension"),
    ])
    func offersTheMachineBuiltForTheMovementFirst(catalogID: String, rigID: String) {
        #expect(MachineCatalog.suited(to: catalogID).map(\.id).contains(rigID))
    }

    @Test(arguments: [("barbell-bench-press", false), ("plank-bodyweight", false),
                      ("machine-chest-press", true), ("seated-leg-curl-machine", true), ("cable-crunch", true)])
    func offersASetupOnlyWhereAMachineIsUsed(catalogID: String, offered: Bool) throws {
        let exercise = try #require(ExerciseCatalog.shared.exercise(id: catalogID))
        #expect(MachineCatalog.offersSetup(for: exercise) == offered)
    }

    // MARK: Settings

    @Test func settingsStoreOnlyWhatWasSetAndDropWhatTheMachineCannotHold() throws {
        let rig = try #require(MachineCatalog.rig(panatta))
        #expect(MachineSettings(raw: nil).isEmpty)
        #expect(MachineSettings(raw: "not json").isEmpty)
        let settings = MachineSettings(["grip": 1, "stop": 3])
        #expect(settings.raw == #"{"grip":1,"stop":3}"#)
        #expect(MachineSettings(raw: settings.raw) == settings)
        #expect(MachineSettings(["stop": 9, "grip": 2, "seat": 1]).valid(for: rig).isEmpty)
        #expect(settings.summary(for: rig) == "Stop 3 · Grip Neutral")
    }

    @Test func choosingAMachineSavesNothingUntilAPositionIsTapped() throws {
        let context = try TestStore.context()
        MachineSetups.choose(panatta, for: chestPress, context: context)
        let setup = try #require(MachineSetups.setup(for: chestPress, context: context))
        #expect(setup.machineID == panatta)
        #expect(setup.settings.isEmpty)
    }

    @Test func tappingAPositionSavesItAndTappingItBackLeavesNoKey() throws {
        let context = try TestStore.context()
        MachineSetups.choose(panatta, for: chestPress, context: context)
        MachineSetups.set("stop", to: 3, for: chestPress, context: context)
        MachineSetups.set("grip", to: 1, for: chestPress, context: context)
        #expect(MachineSetups.setup(for: chestPress, context: context)?.settings == MachineSettings(["stop": 3, "grip": 1]))
        MachineSetups.set("stop", to: nil, for: chestPress, context: context)
        let raw = try #require(MachineSetups.setup(for: chestPress, context: context)?.settingsRaw)
        #expect(raw == #"{"grip":1}"#)
    }

    @Test(arguments: [("stop", 0), ("stop", 5), ("grip", 2), ("seat", 1)])
    func aPositionTheMachineDoesNotHaveIsIgnored(adjustment: String, value: Int) throws {
        let context = try TestStore.context()
        MachineSetups.choose(panatta, for: chestPress, context: context)
        MachineSetups.set(adjustment, to: value, for: chestPress, context: context)
        #expect(MachineSetups.setup(for: chestPress, context: context)?.settings.isEmpty == true)
    }

    @Test func anotherMachineStartsCleanAndTheSameOneKeepsItsSetup() throws {
        let context = try TestStore.context()
        MachineSetups.choose(panatta, for: chestPress, context: context)
        MachineSetups.set("stop", to: 3, for: chestPress, context: context)
        MachineSetups.choose(panatta, for: chestPress, context: context)
        #expect(MachineSetups.setup(for: chestPress, context: context)?.settings == MachineSettings(["stop": 3]))
        MachineSetups.choose("panatta-incline-press", for: chestPress, context: context)
        let setup = try #require(MachineSetups.setup(for: chestPress, context: context))
        #expect(setup.machineID == "panatta-incline-press" && setup.settings.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<MachineSetupRecord>()) == 1)
    }

    @Test func noMachineLeavesNoRowBehind() throws {
        let context = try TestStore.context()
        MachineSetups.choose(panatta, for: chestPress, context: context)
        MachineSetups.set("stop", to: 2, for: chestPress, context: context)
        MachineSetups.clear(chestPress, context: context)
        #expect(try context.fetchCount(FetchDescriptor<MachineSetupRecord>()) == 0)
    }

    @Test func theGymIsLearntFromWhatWasPicked() throws {
        let context = try TestStore.context()
        MachineSetups.choose(panatta, for: chestPress, context: context, at: TestClock.at("2026-03-01T10:00:00"))
        MachineSetups.choose("cybex-leg-press", for: "leg-press", context: context, at: TestClock.at("2026-03-02T10:00:00"))
        MachineSetups.choose(panatta, for: "chest-press-iso-lateral", context: context, at: TestClock.at("2026-03-03T10:00:00"))
        let records = try context.fetch(FetchDescriptor<MachineSetupRecord>())
        #expect(MachineSetups.usedMachineIDs(in: records) == [panatta, "cybex-leg-press"])
    }

    // MARK: Logging

    @Test func aLoggedSetKeepsTheSetupItWasDoneAt() throws {
        try WorkoutBench.run { bench in
            let session = bench.session()
            let rows = bench.addRows(chestPress, to: session, count: 2)
            let workout = bench.open(session)
            MachineSetups.choose(panatta, for: chestPress, context: bench.context)
            MachineSetups.set("stop", to: 3, for: chestPress, context: bench.context)

            workout.complete(rows[0], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(60))
            MachineSetups.set("stop", to: 4, for: chestPress, context: bench.context)
            workout.complete(rows[1], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(240))

            #expect(rows[0].machineID == panatta && rows[0].machineSettingsRaw == #"{"stop":3}"#)
            #expect(rows[1].machineID == panatta && rows[1].machineSettingsRaw == #"{"stop":4}"#)
        }
    }

    @Test func takingASetBackTakesItsMachineWithIt() throws {
        try WorkoutBench.run { bench in
            let session = bench.session()
            let rows = bench.addRows(chestPress, to: session, count: 1)
            let workout = bench.open(session)
            MachineSetups.choose(panatta, for: chestPress, context: bench.context)
            MachineSetups.set("stop", to: 3, for: chestPress, context: bench.context)
            workout.complete(rows[0], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(60))

            rows[0].unlog()

            #expect(rows[0].machineID == nil && rows[0].machineSettingsRaw == nil)
        }
    }

    @Test func aSetWithNoMachineChosenCarriesNone() throws {
        try WorkoutBench.run { bench in
            let (_, rows, workout) = bench.standard()
            workout.complete(rows[0], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(60))
            #expect(rows[0].machineID == nil && rows[0].machineSettingsRaw == nil)
        }
    }

    @Test func aMachineWithNothingSetIsRecordedAlone() throws {
        try WorkoutBench.run { bench in
            let session = bench.session()
            let rows = bench.addRows(chestPress, to: session, count: 1)
            let workout = bench.open(session)
            MachineSetups.choose(panatta, for: chestPress, context: bench.context)
            workout.complete(rows[0], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(60))
            #expect(rows[0].machineID == panatta && rows[0].machineSettingsRaw == nil)
        }
    }

    // MARK: Drawing

    @Test func theModelMovesWithTheSettings() throws {
        let rig = try #require(MachineCatalog.rig(panatta))
        // The levers were modelled at stop 2; each hole tilts them 4 degrees.
        let atBase = MachineScene(rig: rig, settings: MachineSettings(["stop": 2]))
        let raised = MachineScene(rig: rig, settings: MachineSettings(["stop": 4]))
        let baseAngle = try #require(atBase.groupNode("arms")).simdEulerAngles.z
        let raisedAngle = try #require(raised.groupNode("arms")).simdEulerAngles.z
        #expect(abs(baseAngle) < 1e-5)
        #expect(abs(raisedAngle - 8 * .pi / 180) < 1e-4)

        atBase.set("stop", to: 4, animated: true)
        var frames = 0
        while atBase.step(1.0 / 60) && frames < 600 { frames += 1 }
        #expect(frames < 600, "the spring never settled")
        #expect(abs(try #require(atBase.groupNode("arms")).simdEulerAngles.z - raisedAngle) < 1e-4)
    }

    /// Every machine draws something you can see. Set `GT_MACHINE_RENDERS` to
    /// a folder (as `TEST_RUNNER_GT_MACHINE_RENDERS` for `xcodebuild test`) to
    /// keep the pictures for a look at the models.
    @Test func everyMachineDraws() throws {
        let folder = ProcessInfo.processInfo.environment["GT_MACHINE_RENDERS"].map { URL(fileURLWithPath: $0) }
        for rig in MachineCatalog.all {
            let image = try #require(MachineSnapshots.image(for: rig, side: 160), "\(rig.id) did not render")
            #expect(Self.coverage(of: image) > 0.08, "\(rig.id) rendered next to nothing")
            if let folder, let png = image.pngData() {
                try png.write(to: folder.appendingPathComponent("\(rig.id).png"))
            }
        }
    }

    /// The share of pixels that aren't transparent.
    private static func coverage(of image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        var opaque = 0
        for i in stride(from: 3, to: pixels.count, by: 4) where pixels[i] > 16 { opaque += 1 }
        return Double(opaque) / Double(width * height)
    }
}
