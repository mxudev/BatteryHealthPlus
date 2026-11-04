import SwiftUI

enum Palette {
    static let mint = Color(red: 0.45, green: 0.88, blue: 0.72)
    static let blue = Color(red: 0.54, green: 0.72, blue: 0.98)
    static let amber = Color(red: 0.96, green: 0.75, blue: 0.44)
    static let ink = Color(red: 0.055, green: 0.07, blue: 0.075)
    static let surface = Color(red: 0.09, green: 0.11, blue: 0.115)
}

enum Display {
    static func decimal(_ value: Double?, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }
    static func capacity(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
    static func duration(_ minutes: Int?) -> String {
        guard let minutes else { return "Calculating time remaining" }
        if minutes < 60 { return "About \(minutes) min remaining" }
        return "About \(minutes / 60)h \(minutes % 60)m remaining"
    }
}

struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.7)
            .foregroundStyle(.secondary)
    }
}

struct Surface<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 22
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Palette.surface : Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.055), lineWidth: 1))
    }
}

struct HealthRing: View {
    var percent: Double?
    var size: CGFloat = 146
    var line: CGFloat = 8
    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.07), lineWidth: line)
            Circle().trim(from: 0, to: min(max((percent ?? 0) / 100, 0), 1))
                .stroke(AngularGradient(colors: [Palette.mint.opacity(0.4), Palette.mint], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(Display.decimal(percent, digits: 0)).font(.system(size: size * 0.29, weight: .medium, design: .rounded))
                    Text("%").font(.system(size: size * 0.13, weight: .medium)).foregroundStyle(.secondary)
                }.monospacedDigit()
                Text("HEALTH").font(.system(size: size * 0.065, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
            }
        }.frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Battery health, \(Display.decimal(percent, digits: 0)) percent")
    }
}

struct WattValue: View {
    var value: Double?
    var size: CGFloat = 29
    var color: Color = .primary
    var estimated = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text((estimated && value != nil ? "≈" : "") + Display.decimal(value))
                .font(.system(size: size, weight: .medium, design: .rounded)).monospacedDigit()
            Text("W").font(.system(size: max(11, size * 0.4), weight: .medium)).foregroundStyle(.secondary)
        }.foregroundStyle(color)
    }
}
