import SwiftUI
import SwiftData

/// Tape measurements, kept as occasional check-ins rather than a daily log.
///
/// This is where the numbers come from that tell the coach whether a plan
/// change did anything the barbell doesn't show, such as a waist that held
/// while the weight rose. Nothing here asks to be used: the empty card is one
/// quiet line, there is no reminder and no badge, and a month with no check-in
/// leaves a gap the coach reads as absent rather than as a miss.
///
/// A wrong check-in is deleted from the history sheet and leaves nothing
/// behind. It is never edited, because an edited reading would claim a
/// measurement that was never taken.
struct MeasurementsCard: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var checkIns: [BodyMeasurement]

    @State private var isCheckingIn = false
    @State private var isReviewing = false
    @State private var settings = AppSettings.shared

    private var unit: WeightUnit { settings.weightUnit }
    private var readings: [MeasurementReading] { MeasurementTrend.readings(in: checkIns) }

    /// Offered only once there is something to look back at, so the first
    /// thing the card shows is the one line and its button.
    private var historyAction: (label: String, perform: () -> Void)? {
        guard !checkIns.isEmpty else { return nil }
        return (label: "History", perform: { isReviewing = true })
    }

    var body: some View {
        VStack(spacing: 8) {
            SectionHeader("Measurements", action: historyAction)
            content.gtCard()
        }
        .sheet(isPresented: $isCheckingIn) {
            MeasurementCheckInSheet { date, parts in try record(parts, on: date) }
        }
        .sheet(isPresented: $isReviewing) {
            PastCheckInsSheet { delete($0) }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var content: some View {
        if readings.isEmpty {
            emptyLine
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(readings) { reading in row(reading) }
                checkInButton
            }
        }
    }

    private var emptyLine: some View {
        HStack(spacing: 12) {
            Text("No tape measurements yet.")
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Button("Check in") {
                Haptics.tick()
                isCheckingIn = true
            }
            .font(Theme.rounded(13, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
    }

    private var checkInButton: some View {
        Button {
            Haptics.tick()
            isCheckingIn = true
        } label: {
            Label("Check in", systemImage: "plus")
                .font(Theme.rounded(13, weight: .bold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    private func row(_ reading: MeasurementReading) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(reading.part.title)
                .font(Theme.rounded(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text(MeasurementTrend.length(reading.cm, unit: unit))
                    .font(Theme.number(18))
                    .foregroundStyle(Theme.textPrimary)
                Text(caption(for: reading))
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The change since the part was last measured, with the date it is
    /// measured against: a bare "+1.0 cm" reads the same whether it took a
    /// week or four months. Neither direction is coloured, because whether a
    /// smaller waist is good depends on what the plan is for.
    private func caption(for reading: MeasurementReading) -> String {
        guard let change = reading.changeCm, let previous = reading.previousDate else {
            return "first reading"
        }
        let since = previous.formatted(.dateTime.month(.abbreviated).day())
        return "\(MeasurementTrend.change(change, unit: unit)) since \(since)"
    }

    // MARK: - Writing

    /// Only the parts that were measured arrive here, so a blank field has
    /// nothing to store and a skipped part keeps no value.
    private func record(_ parts: [BodyMeasurement.Part: Double], on date: Date) throws {
        let check = BodyMeasurement(date: date)
        for (part, cm) in parts { check.set(cm, for: part) }
        guard check.hasAnyPart else { return }
        context.insert(check)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        Haptics.success()
    }

    /// A hard delete: a mis-taken or mistyped check-in is not data, and a
    /// copy left anywhere would still reach the coach.
    private func delete(_ check: BodyMeasurement) {
        context.delete(check)
        do {
            try context.save()
        } catch {
            // The row stays on screen, which says plainly that it wasn't
            // deleted; there is nothing else to tell.
            context.rollback()
            return
        }
        Haptics.tick()
    }
}

// MARK: - Past check-ins

/// Every check-in, newest first, so one that was mistyped or dated wrongly
/// can be swiped away. Check-ins are monthly at most, so the list is short and
/// carries no limit.
private struct PastCheckInsSheet: View {
    let onDelete: (BodyMeasurement) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var checkIns: [BodyMeasurement]
    @State private var settings = AppSettings.shared

    private var unit: WeightUnit { settings.weightUnit }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(checkIns) { check in
                        row(check)
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { checkIns[$0] }
                        for check in doomed { onDelete(check) }
                    }
                } footer: {
                    Text("Swipe one away to delete it. Nothing of it is kept.")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .gtScreenBackground()
            .navigationTitle("Check-ins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .gtSheetBackground()
    }

    private func row(_ check: BodyMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(check.date.formatted(date: .abbreviated, time: .omitted))
                .font(Theme.rounded(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(summary(of: check))
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private func summary(of check: BodyMeasurement) -> String {
        let measured = BodyMeasurement.Part.allCases.compactMap { part in
            check.value(for: part).map { "\(part.title) \(MeasurementTrend.length($0, unit: unit))" }
        }
        return measured.joined(separator: " · ")
    }
}

// MARK: - Check-in sheet

/// The check-in: a date and up to five girths, each optional. Save waits for
/// at least one, and a blank field stores nothing.
///
/// Each field says where the tape goes, because a girth only means something
/// against the last one if it was taken the same way. Fields are text rather
/// than steppers: these are values read off a tape, not a load to nudge, and
/// a stepper would start every field at a number nobody measured.
private struct MeasurementCheckInSheet: View {
    let onSave: (Date, [BodyMeasurement.Part: Double]) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date = .now
    @State private var texts: [BodyMeasurement.Part: String] = [:]
    @State private var settings = AppSettings.shared
    @State private var saveError: String?
    @FocusState private var focused: BodyMeasurement.Part?

    private var unit: WeightUnit { settings.weightUnit }

    private func entry(_ part: BodyMeasurement.Part) -> MeasurementEntry {
        MeasurementEntry.parse(texts[part] ?? "", unit: unit)
    }

    /// The parts with a usable value, in centimetres.
    private var measured: [BodyMeasurement.Part: Double] {
        var parts: [BodyMeasurement.Part: Double] = [:]
        for part in BodyMeasurement.Part.allCases {
            if case .cm(let cm) = entry(part) { parts[part] = cm }
        }
        return parts
    }

    /// A field with something typed that isn't a length. Save is held back
    /// rather than the field skipped, so a slip is seen, not silently lost.
    private var hasInvalidField: Bool {
        BodyMeasurement.Part.allCases.contains { entry($0) == .invalid }
    }

    private var canSave: Bool { !measured.isEmpty && !hasInvalidField }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(Theme.accent)
                }
                .listRowBackground(Theme.surface)

                Section {
                    ForEach(BodyMeasurement.Part.allCases) { part in
                        field(part)
                    }
                } footer: {
                    Text("Fill in only what you measured.")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .gtScreenBackground()
            .navigationTitle("Check in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
        }
        .gtSheetBackground()
        .alert("Couldn't save check-in", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }

    private func binding(for part: BodyMeasurement.Part) -> Binding<String> {
        Binding(get: { texts[part] ?? "" }, set: { texts[part] = $0 })
    }

    private func valueColor(for part: BodyMeasurement.Part) -> Color {
        entry(part) == .invalid ? Theme.negative : Theme.textPrimary
    }

    private func field(_ part: BodyMeasurement.Part) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(part.title)
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                TextField("", text: binding(for: part), prompt: Text("—").foregroundStyle(Theme.textTertiary))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.number(17))
                    .foregroundStyle(valueColor(for: part))
                    .frame(maxWidth: 90)
                    .focused($focused, equals: part)
                Text(unit.lengthShort)
                    .font(Theme.rounded(13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(part.hint)
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 2)
    }

    private func save() {
        do {
            try onSave(date, measured)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
