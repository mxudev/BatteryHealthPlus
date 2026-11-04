import SwiftUI

/// A compact directional diagram. Line widths are decorative, not wattage scales.
struct PowerFlowView: View {
    let snapshot: PowerSnapshot
    private var onBattery: Bool { snapshot.externalPower == false }
    private var batteryOut: Bool { (snapshot.battery?.watts ?? 0) < -0.1 }
    private var batteryIdle: Bool { snapshot.battery.map { abs($0.watts) <= 0.1 } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(onBattery ? "Battery" : "Charger", systemImage: onBattery ? "battery.75percent" : "powerplug")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    WattValue(value: onBattery ? snapshot.battery.map { abs($0.watts) } : snapshot.input?.watts,
                              size: 21, estimated: (onBattery ? snapshot.battery : snapshot.input)?.estimated ?? false)
                }.frame(maxWidth: .infinity, alignment: .leading)
                flow.frame(width: 34, height: 44).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 12) {
                    destination("Device", reading: snapshot.device, color: Palette.blue)
                    if !onBattery {
                        destination(snapshot.battery == nil ? "Battery" : batteryOut ? "Battery out" : batteryIdle ? "Battery idle" : "Battery in",
                                    reading: snapshot.battery, color: Palette.mint, magnitude: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 72)
            HStack {
                Text("Power flow")
                Spacer(minLength: 4)
                if !onBattery, let rating = snapshot.adapterRatingWatts {
                    Text("\(Display.decimal(rating, digits: 0)) W limit")
                }
            }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }.accessibilityElement(children: .combine)
    }

    private func destination(_ name: String, reading: PowerReading?, color: Color, magnitude: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(Display.watts(reading, magnitude: magnitude))
                .font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(color)
        }
    }

    private var flow: some View {
        Canvas { context, size in
            let middle = CGPoint(x: size.width * 0.42, y: size.height / 2)
            func route(to end: CGPoint, color: Color, active: Bool, reverse: Bool = false) {
                var path = Path()
                path.move(to: middle)
                path.addCurve(to: end,
                              control1: CGPoint(x: middle.x, y: end.y),
                              control2: CGPoint(x: middle.x + 6, y: end.y))
                context.stroke(path, with: .color(active ? color.opacity(0.65) : .secondary.opacity(0.25)),
                               style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                guard active else { return }
                let tip = reverse ? CGPoint(x: end.x - 10, y: end.y) : end
                let tail = reverse ? tip.x + 3 : tip.x - 3
                var arrow = Path()
                arrow.move(to: CGPoint(x: tail, y: tip.y - 2.5))
                arrow.addLine(to: tip)
                arrow.addLine(to: CGPoint(x: tail, y: tip.y + 2.5))
                context.stroke(arrow, with: .color(color.opacity(0.8)),
                               style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            }
            var stem = Path()
            stem.move(to: CGPoint(x: 0, y: middle.y)); stem.addLine(to: middle)
            context.stroke(stem, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            route(to: CGPoint(x: size.width, y: onBattery ? middle.y : 0), color: Palette.blue,
                  active: (snapshot.device?.watts ?? 0) > 0.1)
            if !onBattery {
                route(to: CGPoint(x: size.width, y: size.height), color: Palette.mint,
                      active: snapshot.battery != nil && !batteryIdle, reverse: batteryOut)
            }
        }
    }
}
