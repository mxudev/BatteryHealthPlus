import SwiftUI

enum FaceSize { case small, medium, large }

struct WidgetFace: View {
    let snapshot: PowerSnapshot
    var size: FaceSize = .large
    var live = false

    var body: some View {
        VStack(alignment: .leading, spacing: size == .small ? 10 : 18) {
            HStack(spacing: 7) {
                Image(systemName: "bolt.heart.fill").foregroundStyle(Palette.mint)
                Text("BatteryHealth").font(.system(size: 11, weight: .semibold))
                Text("++").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.mint).padding(.leading, -5)
                Spacer(minLength: 0)
                if live { Circle().fill(Palette.mint).frame(width: 5, height: 5) }
            }
            if size == .small {
                smallContent
            } else if size == .medium {
                HStack(spacing: 20) {
                    if snapshot.batteryPresent { HealthRing(percent: snapshot.healthPercent, size: 88, line: 5) }
                    VStack(alignment: .leading, spacing: 8) {
                        WattValue(value: snapshot.device?.watts, size: 30, estimated: snapshot.device?.estimated ?? false)
                        Text("Device power").font(.system(size: 10)).foregroundStyle(.secondary)
                        if snapshot.batteryPresent {
                            Text("\(Display.decimal(snapshot.chargePercent, digits: 0))% charged · \(snapshot.cycles.map(String.init) ?? "—") cycles")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxHeight: .infinity)
            } else {
                if snapshot.batteryPresent {
                    HStack(spacing: 23) {
                        HealthRing(percent: snapshot.healthPercent, size: 105, line: 6)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(snapshot.status).font(.system(size: 17, weight: .medium))
                            Text("\(Display.decimal(snapshot.chargePercent, digits: 0))% charged")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            Text("\(snapshot.cycles.map(String.init) ?? "—") cycles")
                                .font(.system(size: 11, design: .rounded)).foregroundStyle(Palette.mint)
                        }
                    }.frame(maxWidth: .infinity, alignment: .center)
                    Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
                }
                PowerFlowView(snapshot: snapshot, compact: true)
                if !snapshot.batteryPresent { Spacer(minLength: 0) }
            }
            HStack(spacing: 4) {
                if live {
                    Text("Live · updates every 5s")
                } else {
                    Text("Sampled")
                    Text(snapshot.date, style: .time)
                }
                Spacer(minLength: 0)
                if !live { Image(systemName: "arrow.up.right") }
            }.font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var smallContent: some View {
        if snapshot.batteryPresent {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(Display.decimal(snapshot.healthPercent, digits: 0)).font(.system(size: 42, weight: .medium, design: .rounded))
                Text("%").font(.system(size: 18)).foregroundStyle(Palette.mint)
            }.monospacedDigit()
            Text("Battery health").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("\(Display.decimal(snapshot.chargePercent, digits: 0))% charged").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.mint)
        } else {
            Spacer(minLength: 0)
            WattValue(value: snapshot.device?.watts, size: 39, color: Palette.mint,
                      estimated: snapshot.device?.estimated ?? false)
            Text("System power").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
