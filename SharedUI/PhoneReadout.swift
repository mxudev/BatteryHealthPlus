import SwiftUI

struct PhoneReadout: View {
    static let height: CGFloat = 64
    let phone: PhoneSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "iphone").accessibilityHidden(true)
                Text("iPhone")
                Spacer()
                if let percent = phone.chargePercent {
                    Text("\(Display.decimal(percent, digits: 0))%").foregroundStyle(.secondary)
                }
            }.font(.system(size: 12, weight: .medium))
            if let message = phone.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    reading("Input", value: phone.input, color: .primary)
                    reading("Phone", value: phone.device, color: Palette.blue)
                    reading((phone.battery?.watts ?? 0) < -0.1 ? "Battery out" : "Battery in",
                            value: phone.battery, color: Palette.mint, magnitude: true)
                }
            }
        }.frame(height: Self.height, alignment: .top)
            .help("Power reported by the iPhone. Input is power reaching the phone, not necessarily power supplied by this Mac when using a powered hub.")
    }

    private func reading(_ title: String, value: PowerReading?, color: Color, magnitude: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(Display.watts(value, magnitude: magnitude))
                .font(.system(size: 15, weight: .medium)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}
