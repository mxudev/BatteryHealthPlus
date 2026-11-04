import SwiftUI

enum FaceSize { case small, medium, large }

struct WidgetFace: View {
    let snapshot: PowerSnapshot
    var size: FaceSize = .large

    var body: some View {
        VStack(alignment: .leading, spacing: size == .small ? 5 : 10) {
            HStack {
                Text("BatteryHealth++").font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: snapshot.kind == .desktop ? "bolt" : "battery.75percent")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if size == .large {
                TelemetryReadout(snapshot: snapshot)
            } else if size == .medium {
                HStack(alignment: .top, spacing: 24) {
                    primary.frame(width: 105, alignment: .leading)
                    VStack(spacing: 2) {
                        if snapshot.batteryPresent {
                            MetricRow(label: "Health", value: "\(Display.decimal(snapshot.healthPercent, digits: 0))%")
                            MetricRow(label: "Charger", value: Display.watts(snapshot.input))
                            MetricRow(label: "Battery", value: Display.watts(snapshot.battery))
                        }
                        MetricRow(label: "Device", value: Display.watts(snapshot.device))
                    }
                }
            } else {
                primary
                if snapshot.batteryPresent {
                    MetricRow(label: "Health", value: "\(Display.decimal(snapshot.healthPercent, digits: 0))%")
                    MetricRow(label: "Device", value: Display.watts(snapshot.device))
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                Text("Sampled")
                Text(snapshot.date, style: .time)
                Spacer(minLength: 0)
            }.font(.system(size: 8)).foregroundStyle(.secondary)
        }.accessibilityElement(children: .contain)
    }

    private var primary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if snapshot.batteryPresent {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(Display.decimal(snapshot.chargePercent, digits: 0)).font(.system(size: 30, weight: .medium)).tracking(-1)
                    Text("%").font(.system(size: 13)).foregroundStyle(.secondary)
                }.monospacedDigit()
                Text(snapshot.status).font(.system(size: 10)).foregroundStyle(Palette.mint)
            } else {
                WattValue(value: snapshot.device?.watts, size: 30, estimated: snapshot.device?.estimated ?? false)
                Text("System draw").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
