import SwiftUI
import Charts

struct DashboardView: View {
    let snapshot: PowerSnapshot
    let history: [PowerPoint]
    var onFloat: () -> Void = {}
    var onRefresh: () -> Void = {}
    @State private var showSources = false

    var body: some View {
        ScrollView {
            content
        }.background(Palette.ink)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showSources) { SourcesView(snapshot: snapshot) }
    }

    var content: some View {
            VStack(alignment: .leading, spacing: 20) {
                header
                HStack(alignment: .top, spacing: 16) {
                    if snapshot.kind != .desktop { healthCard.frame(width: 274) }
                    Surface {
                        VStack(alignment: .leading, spacing: 24) {
                            PowerFlowView(snapshot: snapshot)
                            if snapshot.batteryPresent { chargeBar }
                        }.frame(minHeight: 275, alignment: .top)
                    }
                }
                if snapshot.batteryPresent { metrics }
                historyCard
                footer
            }.padding(28)
            .background(Palette.ink)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.heart.fill").foregroundStyle(Palette.mint)
                    Text("BATTERYHEALTH").tracking(2).font(.system(size: 11, weight: .bold))
                    Text("++").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.mint).padding(.leading, -4)
                }
                Text(snapshot.kind == .desktop ? "A little power perspective." : "Know your battery.")
                    .font(.system(size: 28, weight: .medium, design: .rounded)).padding(.top, 4)
                Text("\(snapshot.model)  /  Apple Silicon")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onFloat) { Label("Float widget", systemImage: "rectangle.on.rectangle") }
                .buttonStyle(.bordered).controlSize(.small).tint(Palette.mint)
                .help("Keep a live widget above your other windows")
        }.padding(.bottom, 4)
    }

    private var healthCard: some View {
        Surface {
            VStack(spacing: 17) {
                HStack { Eyebrow(text: "Battery health"); Spacer(); Image(systemName: "leaf").foregroundStyle(Palette.mint).font(.system(size: 12)) }
                HealthRing(percent: snapshot.healthPercent, size: 139)
                VStack(spacing: 5) {
                    Text(snapshot.condition.map { $0 == "Good" ? "Normal condition" : $0 } ?? "Capacity retention")
                        .font(.system(size: 12, weight: .medium))
                    Text("Compared with original capacity").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.frame(minHeight: 275)
        }
    }

    private var chargeBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
            HStack {
                Label(snapshot.status, systemImage: snapshot.charging == true ? "bolt.fill" : "battery.75percent")
                    .foregroundStyle(Palette.mint)
                Spacer()
                Text("\(Display.decimal(snapshot.chargePercent, digits: 0))%")
            }.font(.system(size: 11, weight: .medium))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.06))
                    Capsule().fill(Palette.mint.opacity(0.8))
                        .frame(width: geometry.size.width * min(max((snapshot.chargePercent ?? 0) / 100, 0), 1))
                }
            }.frame(height: 4)
            Text(snapshot.charging == true || snapshot.externalPower == false ? Display.duration(snapshot.minutesRemaining) : "Connected to external power")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            metric("Full capacity", value: Display.capacity(snapshot.fullCapacityMAh), unit: "mAh", icon: "battery.100percent", tint: Palette.mint)
            metric("Original capacity", value: Display.capacity(snapshot.designCapacityMAh), unit: "mAh", icon: "sparkle", tint: .secondary)
            metric("Charge cycles", value: snapshot.cycles.map { $0.formatted() } ?? "—", unit: snapshot.designCycles.map { "/ \($0) design" } ?? "cycles", icon: "arrow.triangle.2.circlepath", tint: Palette.blue)
            metric("Temperature", value: Display.decimal(snapshot.temperatureC), unit: "°C", icon: "thermometer.medium", tint: Palette.amber)
        }
    }

    private func metric(_ title: String, value: String, unit: String, icon: String, tint: Color) -> some View {
        Surface(padding: 16) {
            VStack(alignment: .leading, spacing: 11) {
                HStack { Text(title).font(.system(size: 10)).foregroundStyle(.secondary); Spacer(minLength: 0); Image(systemName: icon).foregroundStyle(tint).font(.system(size: 11)) }
                Text(value).font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    private var historyCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Eyebrow(text: "Power over time")
                    Spacer()
                    legend("Charger", Palette.mint)
                    legend("Device", Palette.blue)
                    Text("10 MIN").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary).padding(.leading, 12)
                }
                if history.filter({ $0.device != nil || $0.input != nil }).count >= 2 {
                    Chart(history) { point in
                        if let input = point.input {
                            LineMark(x: .value("Time", point.date), y: .value("Watts", input), series: .value("Source", "Charger"))
                                .foregroundStyle(Palette.mint).lineStyle(StrokeStyle(lineWidth: 1.8)).interpolationMethod(.linear)
                        }
                        if let device = point.device {
                            LineMark(x: .value("Time", point.date), y: .value("Watts", device), series: .value("Source", "Device"))
                                .foregroundStyle(Palette.blue).lineStyle(StrokeStyle(lineWidth: 1.8)).interpolationMethod(.linear)
                        }
                    }
                    .chartXScale(domain: snapshot.date.addingTimeInterval(-600)...snapshot.date)
                    .chartYScale(domain: 0...max(20, (history.flatMap { [$0.input, $0.device].compactMap { $0 } }.max() ?? 20) * 1.2))
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .minute, count: 2)) { value in
                            AxisValueLabel(anchor: .top) {
                                if let date = value.as(Date.self) {
                                    Text(date, format: .dateTime.hour().minute()).font(.system(size: 9)).foregroundStyle(.gray)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine().foregroundStyle(.white.opacity(0.045))
                            AxisValueLabel { if let watts = value.as(Double.self) { Text("\(Int(watts)) W").font(.system(size: 9)).foregroundStyle(.secondary) } }
                        }
                    }.frame(height: 105)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path").font(.system(size: 25, weight: .light)).foregroundStyle(Palette.mint)
                        Text("Collecting your first readings…").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).frame(height: 105)
                }
            }
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 5, height: 5); Text(title).font(.system(size: 10)).foregroundStyle(.secondary) }
    }
    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(snapshot.isStale() ? Palette.amber : Palette.mint).frame(width: 5, height: 5)
            Text(snapshot.isStale() ? "Waiting for a fresh reading" : "Live · 5-second sampling")
            Text("·").foregroundStyle(.tertiary)
            Text("All data stays on this Mac")
            Spacer()
            Button("Readings & sources") { showSources = true }.buttonStyle(.plain).foregroundStyle(Palette.mint)
            Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).padding(.leading, 8).help("Refresh readings")
        }.font(.system(size: 10)).foregroundStyle(.secondary)
    }
}

struct SourcesView: View {
    let snapshot: PowerSnapshot
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text("Behind the readings").font(.system(size: 23, weight: .medium, design: .rounded))
            Text("Power is measured at the Mac. Charger input is different from wall-socket consumption and the connection’s advertised wattage.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach([("Charger input", snapshot.input), ("Device load", snapshot.device), ("Battery flow", snapshot.battery)], id: \.0) { label, reading in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(label).fontWeight(.medium); Spacer(); Text("\(Display.decimal(reading?.watts)) W") }
                    Text(reading?.source ?? "Sensor unavailable").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }.font(.system(size: 12))
            }
            Divider()
            Text("≈ marks calculated estimates. Sensor readings can have different sampling times, so the three power values may not add up exactly. Positive battery flow means charging; negative means discharging.")
            Text("Health is full-charge capacity ÷ design capacity. This can differ from the health estimate in System Settings. Desktop widgets show timestamped samples; macOS controls when they refresh. The floating widget updates every 5 seconds while awake.")
            ForEach(snapshot.notes, id: \.self) { Text($0).foregroundStyle(Palette.amber) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(28).frame(width: 470)
            .background(Palette.ink).preferredColorScheme(.dark)
    }
}
