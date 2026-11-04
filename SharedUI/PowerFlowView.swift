import SwiftUI

struct PowerFlowView: View {
    let snapshot: PowerSnapshot
    var compact = false

    private var discharging: Bool { (snapshot.battery?.watts ?? 0) < -0.1 }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 24) {
            HStack {
                Eyebrow(text: snapshot.kind == .desktop ? "System power" : "Power flow")
                Spacer()
                if let rating = snapshot.adapterRatingWatts {
                    Text("\(Display.decimal(rating, digits: 0)) W connection")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            if snapshot.kind == .desktop {
                HStack(spacing: 18) {
                    Image(systemName: "desktopcomputer").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(Palette.mint)
                    VStack(alignment: .leading, spacing: 5) {
                        WattValue(value: snapshot.device?.watts, size: compact ? 36 : 48, color: Palette.mint,
                                  estimated: snapshot.device?.estimated ?? false)
                        Text("Total system draw").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                Text(snapshot.device == nil ? "Power sensor unavailable on this Mac." : "Measured at the system. Wall consumption may differ.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: compact ? 10 : 16) {
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: snapshot.externalPower == false ? "battery.75percent" : "powerplug")
                            .font(.system(size: compact ? 22 : 26, weight: .light)).foregroundStyle(Palette.mint)
                        Text(snapshot.externalPower == false ? "From battery" : "From charger")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        WattValue(value: snapshot.externalPower == false ? snapshot.battery.map { abs($0.watts) } : snapshot.input?.watts,
                                  size: compact ? 26 : 34, color: Palette.mint,
                                  estimated: snapshot.externalPower == false ? snapshot.battery?.estimated ?? false : snapshot.input?.estimated ?? false)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if snapshot.externalPower == false {
                        Image(systemName: "arrow.right").foregroundStyle(Palette.mint.opacity(0.6))
                            .frame(width: compact ? 30 : 46).accessibilityHidden(true)
                    } else {
                        FlowBranch(batteryOut: discharging).stroke(Palette.mint.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .frame(width: compact ? 30 : 46, height: compact ? 76 : 88)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: compact ? 14 : 22) {
                        destination("Mac", icon: "laptopcomputer", reading: snapshot.device, color: Palette.blue)
                        if snapshot.externalPower != false {
                            destination(discharging ? "Battery out" : "Battery in", icon: discharging ? "battery.50percent" : "battery.75percent",
                                    reading: snapshot.battery.map { .init(abs($0.watts), source: $0.source, estimated: $0.estimated) }, color: Palette.mint)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if !compact {
                    Text(snapshot.externalPower == false ? "Your battery is supplying the Mac." :
                            discharging ? "The battery is supplementing the charger." : "Power delivered to your Mac and battery.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func destination(_ name: String, icon: String, reading: PowerReading?, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15, weight: .regular)).foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                WattValue(value: reading?.watts, size: compact ? 22 : 26, estimated: reading?.estimated ?? false)
            }
        }
    }
}

private struct FlowBranch: Shape {
    var batteryOut = false
    func path(in r: CGRect) -> Path {
        Path { p in
            let mid = r.midX
            p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: mid - 8, y: r.midY))
            p.addQuadCurve(to: CGPoint(x: mid, y: r.midY - 8), control: CGPoint(x: mid, y: r.midY))
            p.addLine(to: CGPoint(x: mid, y: 8))
            p.addQuadCurve(to: CGPoint(x: mid + 8, y: 0), control: CGPoint(x: mid, y: 0))
            p.addLine(to: CGPoint(x: r.maxX, y: 0))
            p.move(to: CGPoint(x: mid, y: r.midY - 8)); p.addLine(to: CGPoint(x: mid, y: r.maxY - 8))
            p.addQuadCurve(to: CGPoint(x: mid + 8, y: r.maxY), control: CGPoint(x: mid, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.move(to: CGPoint(x: r.maxX - 4, y: -3)); p.addLine(to: CGPoint(x: r.maxX, y: 0)); p.addLine(to: CGPoint(x: r.maxX - 4, y: 3))
            let x = batteryOut ? mid + 8 : r.maxX
            let dx: CGFloat = batteryOut ? 4 : -4
            p.move(to: CGPoint(x: x + dx, y: r.maxY - 3)); p.addLine(to: CGPoint(x: x, y: r.maxY)); p.addLine(to: CGPoint(x: x + dx, y: r.maxY + 3))
        }
    }
}
