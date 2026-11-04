import SwiftUI

/// A compact directional diagram. Line widths are decorative, not wattage scales.
struct PowerFlowView: View {
    let snapshot: PowerSnapshot
    private static let nodeHeight: CGFloat = 40
    private static let nodeGap: CGFloat = 10
    private static let diagramHeight = nodeHeight * 2 + nodeGap
    private var onBattery: Bool { snapshot.externalPower == false }
    private var batteryOut: Bool { (snapshot.battery?.watts ?? 0) < -0.1 }
    private var batteryIdle: Bool { snapshot.battery.map { abs($0.watts) <= 0.1 } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Power flow")
                Spacer(minLength: 4)
                if !onBattery, let rating = snapshot.adapterRatingWatts {
                    Text("\(Display.decimal(rating, digits: 0)) W limit")
                }
            }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)

            // Equal columns keep the connector centered, independently of label
            // lengths and the heading. Identical nodes keep one-to-one baselines aligned.
            HStack(spacing: 8) {
                reading(onBattery ? "Battery" : "Charger", icon: onBattery ? "battery.75percent" : "powerplug",
                        value: onBattery ? snapshot.battery : snapshot.input,
                        color: .primary, magnitude: onBattery)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                flow.frame(width: 40, height: Self.diagramHeight).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Self.nodeGap) {
                    reading("Device", icon: "laptopcomputer", value: snapshot.device, color: Palette.blue)
                    if !onBattery {
                        reading(snapshot.battery == nil ? "Battery" : batteryOut ? "Battery out" : batteryIdle ? "Battery idle" : "Battery in",
                                icon: "battery.75percent", value: snapshot.battery, color: Palette.mint, magnitude: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: 300).frame(height: Self.diagramHeight)
                .frame(maxWidth: .infinity, alignment: .center)
        }.accessibilityElement(children: .combine)
    }

    private func reading(_ name: String, icon: String, value: PowerReading?, color: Color, magnitude: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .regular))
                    .frame(width: 15).accessibilityHidden(true)
                Text(name).font(.system(size: 10))
            }.foregroundStyle(.secondary).frame(height: 13).lineLimit(1)
            Text(Display.watts(value, magnitude: magnitude))
                .font(.system(size: 17, weight: .medium)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.85)
        }.frame(height: Self.nodeHeight)
    }

    private var flow: some View {
        Canvas { context, size in
            let centerY = size.height / 2
            let junctionX = size.width / 2
            let stroke = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            let muted = Color.secondary.opacity(0.25)

            func arrow(at tip: CGPoint, pointingRight: Bool, color: Color) {
                let tailX = tip.x + (pointingRight ? -4 : 4)
                var head = Path()
                head.move(to: CGPoint(x: tailX, y: tip.y - 3))
                head.addLine(to: tip)
                head.addLine(to: CGPoint(x: tailX, y: tip.y + 3))
                context.stroke(head, with: .color(color), style: stroke)
            }

            if onBattery {
                // A straight connector at the shared node center: no curved stub
                // or off-center arrowhead in the one-to-one layout.
                let active = (snapshot.device?.watts ?? 0) > 0.1
                let color = active ? Palette.blue.opacity(0.75) : muted
                var line = Path()
                line.move(to: CGPoint(x: 1, y: centerY))
                line.addLine(to: CGPoint(x: size.width - 1, y: centerY))
                context.stroke(line, with: .color(color), style: stroke)
                if active { arrow(at: CGPoint(x: size.width - 1, y: centerY), pointingRight: true, color: color) }
            } else {
                var stem = Path()
                stem.move(to: CGPoint(x: 1, y: centerY))
                stem.addLine(to: CGPoint(x: junctionX, y: centerY))
                context.stroke(stem, with: .color(.secondary.opacity(0.4)), style: stroke)

                func branch(y: CGFloat, color: Color, active: Bool, reverse: Bool = false) {
                    let ink = active ? color.opacity(0.75) : muted
                    let radius: CGFloat = 6
                    let approachY = y + (y < centerY ? radius : -radius)
                    var line = Path()
                    line.move(to: CGPoint(x: junctionX, y: centerY))
                    line.addLine(to: CGPoint(x: junctionX, y: approachY))
                    line.addQuadCurve(to: CGPoint(x: junctionX + radius, y: y),
                                      control: CGPoint(x: junctionX, y: y))
                    line.addLine(to: CGPoint(x: size.width - 1, y: y))
                    context.stroke(line, with: .color(ink), style: stroke)
                    if active {
                        // A reverse arrow stays on the horizontal branch and
                        // points back toward the junction when the battery assists.
                        let x = reverse ? junctionX + radius + 3 : size.width - 1
                        arrow(at: CGPoint(x: x, y: y), pointingRight: !reverse, color: ink)
                    }
                }
                // Endpoints come from the same node geometry used by the layout,
                // rather than attaching arrows to the top/bottom of a guessed frame.
                branch(y: Self.nodeHeight / 2, color: Palette.blue,
                       active: (snapshot.device?.watts ?? 0) > 0.1)
                branch(y: size.height - Self.nodeHeight / 2, color: Palette.mint,
                       active: snapshot.battery != nil && !batteryIdle, reverse: batteryOut)
            }
        }
    }
}
