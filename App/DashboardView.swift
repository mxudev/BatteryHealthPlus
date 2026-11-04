import SwiftUI
import Charts

struct DashboardView: View {
    // Content dimensions, excluding the native window title bar.
    static let minimumContentSize = NSSize(width: 520, height: 560)
    let snapshot: PowerSnapshot
    let history: [PowerPoint]
    var onFloat: () -> Void = {}
    @State private var showSources = false

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: Self.minimumContentSize.width, minHeight: Self.minimumContentSize.height,
                   alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.background)
            .sheet(isPresented: $showSources) { SourcesView(snapshot: snapshot) }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.kind == .desktop ? "Power" : "Battery").font(.system(size: 17, weight: .semibold))
                    Text(snapshot.model).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onFloat) { Label("Float", systemImage: "pip") }.controlSize(.small)
            }
            if snapshot.batteryPresent {
                HStack(alignment: .firstTextBaseline, spacing: 36) {
                    headline("Charge", value: Display.decimal(snapshot.chargePercent, digits: 0), unit: "%")
                    headline("Health", value: Display.decimal(snapshot.healthPercent, digits: 0), unit: "%")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(snapshot.status).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.mint)
                        Text(Display.remaining(snapshot)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                ChargeLine(percent: snapshot.chargePercent)
            } else {
                WattValue(value: snapshot.device?.watts, size: 36, estimated: snapshot.device?.estimated ?? false)
                Text("System draw").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            if snapshot.kind != .desktop {
                PowerFlowView(snapshot: snapshot)
                Divider()
            }
            if snapshot.batteryPresent {
                HStack(alignment: .top, spacing: 30) {
                    VStack(spacing: 3) {
                        MetricRow(label: "Full capacity", value: "\(Display.capacity(snapshot.fullCapacityMAh)) mAh")
                        MetricRow(label: "Design capacity", value: "\(Display.capacity(snapshot.designCapacityMAh)) mAh")
                        MetricRow(label: "Cycles", value: snapshot.cycles.map { $0.formatted() } ?? "—")
                    }
                    VStack(spacing: 3) {
                        MetricRow(label: "Temperature", value: "\(Display.decimal(snapshot.temperatureC)) °C")
                        MetricRow(label: "Voltage", value: "\(Display.decimal(snapshot.voltage, digits: 2)) V")
                        MetricRow(label: "Current", value: "\(Display.decimal(snapshot.currentAmps, digits: 2)) A")
                    }
                }
                Divider()
            }
            historyView
            HStack(spacing: 5) {
                Circle().fill(snapshot.isStale() ? Palette.amber : Palette.mint).frame(width: 4, height: 4)
                Text(snapshot.isStale() ? "Waiting for reading" : "Live")
                Spacer()
                Button("Readings & sources") { showSources = true }.buttonStyle(.plain)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(20).background(Palette.background)
    }

    private func headline(_ label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: label)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 34, weight: .medium)).tracking(-1)
                Text(unit).font(.system(size: 14)).foregroundStyle(.secondary)
            }.monospacedDigit()
        }
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Power · 10 min")
                Spacer()
                legend("Charger", Palette.mint)
                legend("Device", Palette.blue)
            }
            if history.filter({ $0.device != nil || $0.input != nil }).count >= 2 {
                Chart(history) { point in
                    if let input = point.input {
                        LineMark(x: .value("Time", point.date), y: .value("Watts", input), series: .value("Source", "Charger"))
                            .foregroundStyle(Palette.mint).lineStyle(StrokeStyle(lineWidth: 1.3))
                    }
                    if let device = point.device {
                        LineMark(x: .value("Time", point.date), y: .value("Watts", device), series: .value("Source", "Device"))
                            .foregroundStyle(Palette.blue).lineStyle(StrokeStyle(lineWidth: 1.3))
                    }
                }
                .chartXScale(domain: snapshot.date.addingTimeInterval(-600)...snapshot.date)
                .chartYScale(domain: 0...max(20, (history.flatMap { [$0.input, $0.device].compactMap { $0 } }.max() ?? 20) * 1.2))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .minute, count: 3)) { value in
                        AxisValueLabel(anchor: .top) {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.hour().minute()).font(.system(size: 8)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                        AxisValueLabel {
                            if let watts = value.as(Double.self) { Text("\(Int(watts)) W").font(.system(size: 8)).foregroundStyle(.secondary) }
                        }
                    }
                }.frame(height: 86)
            } else {
                Text("Collecting readings…").font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).frame(height: 86)
            }
        }
    }
    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

struct SourcesView: View {
    let snapshot: PowerSnapshot
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Readings & sources").font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
            Text("Power is measured inside the Mac. Charger input is separate from wall consumption and the connection limit.")
            ForEach([("Charger", snapshot.input), ("Device", snapshot.device), ("Battery", snapshot.battery)], id: \.0) { label, reading in
                VStack(alignment: .leading, spacing: 3) {
                    MetricRow(label: label, value: Display.watts(reading))
                    Text(reading?.source ?? "Sensor unavailable").font(.system(size: 9, design: .monospaced))
                }
            }
            Divider()
            Text("≈ indicates a calculated estimate. Sensors sample at different times, so readings may not add up exactly. Positive battery power means charging; negative means discharging.")
            Text("Health is full-charge capacity ÷ design capacity. It can differ from System Settings. The app shows live readings.")
            ForEach(snapshot.notes, id: \.self) { Text($0).foregroundStyle(Palette.amber) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).controlSize(.small) }
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(20).frame(width: 400)
            .background(Palette.background)
    }
}
