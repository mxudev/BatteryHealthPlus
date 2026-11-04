import SwiftUI

/// A shared dense readout for the dropdown, floating panel and large widget.
struct TelemetryReadout: View {
    let snapshot: PowerSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if snapshot.batteryPresent {
                HStack {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(Display.decimal(snapshot.chargePercent, digits: 0))
                            .font(.system(size: 30, weight: .medium)).tracking(-1)
                        Text("%").font(.system(size: 14)).foregroundStyle(.secondary)
                    }.monospacedDigit().accessibilityElement(children: .ignore)
                        .accessibilityLabel("Charge, \(Display.decimal(snapshot.chargePercent, digits: 0)) percent")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(snapshot.status).foregroundStyle(snapshot.charging == true ? Palette.mint : .primary)
                            .font(.system(size: 11, weight: .medium))
                        Text(Display.remaining(snapshot)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                ChargeLine(percent: snapshot.chargePercent)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    WattValue(value: snapshot.device?.watts, size: 30, estimated: snapshot.device?.estimated ?? false)
                    Spacer()
                    Text("System draw").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if snapshot.kind != .desktop {
                Divider()
                PowerFlowView(snapshot: snapshot)
            }
            if snapshot.batteryPresent {
                Divider()
                VStack(spacing: 1) {
                    MetricRow(label: "Health", value: "\(Display.decimal(snapshot.healthPercent, digits: 0))%")
                    MetricRow(label: "Full capacity", value: "\(Display.capacity(snapshot.fullCapacityMAh)) mAh")
                    MetricRow(label: "Design capacity", value: "\(Display.capacity(snapshot.designCapacityMAh)) mAh")
                    MetricRow(label: "Cycles", value: snapshot.cycles.map { $0.formatted() } ?? "—")
                }
                HStack(spacing: 0) {
                    Text("\(Display.decimal(snapshot.temperatureC)) °C")
                    Spacer()
                    Text("\(Display.decimal(snapshot.voltage, digits: 2)) V")
                    Spacer()
                    Text("\(Display.decimal(snapshot.currentAmps, digits: 2)) A")
                }.font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Temperature \(Display.decimal(snapshot.temperatureC)) Celsius, voltage \(Display.decimal(snapshot.voltage, digits: 2)) volts, current \(Display.decimal(snapshot.currentAmps, digits: 2)) amps")
            } else if snapshot.device == nil {
                Text("Power sensor unavailable").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
