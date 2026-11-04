import AppKit
import SwiftUI

enum Palette {
    static let mint = adaptive(light: NSColor(red: 0.04, green: 0.40, blue: 0.28, alpha: 1),
                               dark: NSColor(red: 0.48, green: 0.83, blue: 0.68, alpha: 1))
    static let blue = adaptive(light: NSColor(red: 0.29, green: 0.34, blue: 0.59, alpha: 1),
                               dark: NSColor(red: 0.65, green: 0.68, blue: 0.88, alpha: 1))
    static let amber = Color(nsColor: .systemOrange)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

enum Display {
    static func decimal(_ value: Double?, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }
    static func capacity(_ value: Double?) -> String { decimal(value, digits: 0) }
    static func watts(_ reading: PowerReading?, magnitude: Bool = false) -> String {
        guard let reading else { return "—" }
        return (reading.estimated ? "≈" : "") + decimal(magnitude ? abs(reading.watts) : reading.watts) + " W"
    }
    static func duration(_ minutes: Int?) -> String {
        guard let minutes else { return "Estimating time" }
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
    static func remaining(_ snapshot: PowerSnapshot) -> String {
        guard snapshot.charging == true || snapshot.externalPower == false else { return "External power" }
        guard snapshot.minutesRemaining != nil else { return "Estimating time" }
        return duration(snapshot.minutesRemaining) + (snapshot.charging == true ? " to full" : " remaining")
    }
}

struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9, weight: .medium)).tracking(0.8).foregroundStyle(.secondary)
    }
}

struct MetricRow: View {
    var label: String
    var value: String
    var tint: Color = .primary
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).monospacedDigit().foregroundStyle(tint)
        }.font(.system(size: 12)).frame(minHeight: 17)
            .accessibilityElement(children: .combine)
    }
}

struct ChargeLine: View {
    var percent: Double?
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.09))
                Capsule().fill(Palette.mint).frame(width: max(0, geometry.size.width) * min(max((percent ?? 0) / 100, 0), 1))
            }
        }.frame(height: 3).accessibilityHidden(true)
    }
}

struct WattValue: View {
    var value: Double?
    var size: CGFloat = 24
    var color: Color = .primary
    var estimated = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text((estimated && value != nil ? "≈" : "") + Display.decimal(value))
                .font(.system(size: size, weight: .medium)).monospacedDigit()
            Text("W").font(.system(size: 11)).foregroundStyle(.secondary)
        }.foregroundStyle(color)
    }
}
