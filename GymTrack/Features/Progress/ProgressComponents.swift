import SwiftUI

// MARK: - Entrance

/// Cards lift into place in sequence when the screen appears. It costs nothing
/// and turns a wall of panels into something that feels assembled for you.
private struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 22)
            .onAppear {
                withAnimation(.spring(response: 0.62, dampingFraction: 0.86)
                    .delay(Double(index) * 0.055)) {
                    shown = true
                }
            }
    }
}

extension View {
    func riseIn(_ index: Int) -> some View { modifier(RiseIn(index: index)) }
}

// MARK: - Numbers

/// A number that counts up to its value. `Animatable` on the view means SwiftUI
/// interpolates the value itself, so the digits actually roll.
struct RollingNumber: View, Animatable {
    var value: Double
    var format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
            .monospacedDigit()
    }
}

/// Percentage change against the previous, equally long window.
struct DeltaBadge: View {
    let change: Double?

    var body: some View {
        if let change, abs(change) >= 0.005 {
            let up = change > 0
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .black))
                Text("\(abs(change * 100), specifier: "%.0f")%")
                    .font(Theme.number(10, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(up ? Theme.positive : Theme.negative)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill((up ? Theme.positive : Theme.negative).opacity(0.14)))
        } else {
            Text("—")
                .font(Theme.number(11, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Sparkline

/// A tiny trend line. No axes, no labels — its only job is the shape.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            let path = linePath(in: geo.size)
            ZStack {
                path
                    .strokedPath(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(tint)
                areaPath(in: geo.size)
                    .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let peak = max(values.max() ?? 1, 0.0001)
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step,
                    y: size.height - CGFloat(value / peak) * (size.height - 2) - 1)
        }
    }

    private func linePath(in size: CGSize) -> Path {
        let pts = points(in: size)
        guard let first = pts.first else { return Path() }
        var path = Path()
        path.move(to: first)
        for point in pts.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func areaPath(in size: CGSize) -> Path {
        let pts = points(in: size)
        guard let first = pts.first, let last = pts.last else { return Path() }
        var path = linePath(in: size)
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Segmented pills

/// The stock segmented control is grey plastic; this matches the rest of the
/// app and slides its selection.
struct SegmentedPills<Value: Hashable & Identifiable>: View {
    let values: [Value]
    @Binding var selection: Value
    var title: (Value) -> String
    var namespaceID: String = "segment"

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(values) { value in
                Button {
                    guard selection != value else { return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { selection = value }
                    Haptics.tick()
                } label: {
                    Text(title(value))
                        .font(Theme.rounded(13, weight: .bold))
                        .foregroundStyle(selection == value ? Color.black : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if selection == value {
                                Capsule()
                                    .fill(Theme.accent)
                                    .matchedGeometryEffect(id: namespaceID, in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Metric tile

/// A headline number with its trend and its change against the previous window.
struct MetricTile: View {
    let value: Double
    let label: String
    var caption: String?
    var change: Double?
    var trend: [Double] = []
    var tint: Color = Theme.textPrimary
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    @State private var shown: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                RollingNumber(value: shown, format: format)
                    .font(Theme.number(26))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Spacer(minLength: 0)
                if change != nil {
                    DeltaBadge(change: change)
                        .fixedSize()
                }
            }

            Text(label.uppercased())
                .font(Theme.eyebrow)
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if trend.count > 1 {
                Sparkline(values: trend, tint: tint == Theme.textPrimary ? Theme.accent : tint)
                    .frame(height: 18)
                    .padding(.top, 2)
            } else if let caption {
                Text(caption)
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { shown = value }
        }
        .onChange(of: value) { _, new in
            withAnimation(.easeOut(duration: 0.45)) { shown = new }
        }
    }
}

// MARK: - Consistency calendar

/// GitHub-style grid, but shaded by how hard the day was rather than by whether
/// it happened — a 40-minute accessory day and a two-hour squat session should
/// not look identical.
struct ConsistencyGrid: View {
    let volumeByDay: [Date: Double]
    let weeks: Int
    @Binding var selectedDay: Date?

    private let calendar = Calendar.current
    private let cell: CGFloat = 13
    private let gap: CGFloat = 3.5

    private var today: Date { calendar.startOfDay(for: .now) }

    private var firstDay: Date {
        let offset = calendar.component(.weekday, from: today) - 1
        let lastColumnStart = calendar.date(byAdding: .day, value: -offset, to: today)!
        return calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: lastColumnStart)!
    }

    private var peak: Double {
        max(volumeByDay.values.max() ?? 1, 0.0001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                weekdayLabels
                VStack(alignment: .leading, spacing: 4) {
                    monthLabels
                    grid
                }
            }
        }
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: gap) {
            Color.clear.frame(height: 11)      // aligns with the month row
            ForEach(0..<7, id: \.self) { index in
                Text(index % 2 == 1 ? String(calendar.veryShortWeekdaySymbols[index]) : " ")
                    .font(Theme.rounded(8, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(height: cell)
            }
        }
    }

    /// Month names are pinned above the column where the month starts and left
    /// to overflow to the right — clipping them to a 13pt column turned "May"
    /// into two stacked letters.
    private var monthLabels: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: 11)
            ForEach(monthStarts, id: \.column) { start in
                Text(start.name)
                    .font(Theme.rounded(9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize()
                    .offset(x: CGFloat(start.column) * (cell + gap))
            }
        }
        .frame(height: 11, alignment: .topLeading)
    }

    private var monthStarts: [(column: Int, name: String)] {
        (0..<weeks).compactMap { week in
            let start = calendar.date(byAdding: .day, value: week * 7, to: firstDay)!
            guard let first = (0..<7).compactMap({ offset -> Date? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                return calendar.component(.day, from: date) == 1 ? date : nil
            }).first else { return nil }
            return (week, first.formatted(.dateTime.month(.abbreviated)))
        }
    }

    private var grid: some View {
        HStack(spacing: gap) {
            ForEach(0..<weeks, id: \.self) { week in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { weekday in
                        let date = calendar.date(byAdding: .day, value: week * 7 + weekday, to: firstDay)!
                        cellView(date)
                    }
                }
            }
        }
    }

    private func cellView(_ date: Date) -> some View {
        let isFuture = date > today
        let volume = volumeByDay[date] ?? 0
        let isSelected = selectedDay == date

        return RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(fill(volume: volume, isFuture: isFuture))
            .frame(width: cell, height: cell)
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : .clear, lineWidth: 1.4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(date == today ? Theme.accent.opacity(0.9) : .clear, lineWidth: 1.2)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isFuture else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedDay = isSelected ? nil : date
                }
                Haptics.tick()
            }
    }

    private func fill(volume: Double, isFuture: Bool) -> Color {
        if isFuture { return Color.white.opacity(0.02) }
        guard volume > 0 else { return Color.white.opacity(0.06) }
        let share = min(volume / peak, 1)
        return Theme.accent.opacity(0.34 + 0.66 * share)
    }

}

// MARK: - Region balance

/// Four bars answering the question the figure poses: is the week balanced?
struct RegionBalanceRow: View {
    let region: Muscle.Region
    let coverage: Double
    var animate: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(region.rawValue)
                .font(Theme.rounded(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 78, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [MuscleHeat.color(max(coverage, 0.2)).opacity(0.75),
                                     MuscleHeat.color(max(coverage, 0.2))],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * (animate ? min(coverage, 1) : 0))
                }
            }
            .frame(height: 8)

            Text("\(Int((coverage * 100).rounded()))%")
                .font(Theme.number(12, weight: .bold))
                .foregroundStyle(coverage >= 0.85 ? Theme.accent : Theme.textSecondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}
