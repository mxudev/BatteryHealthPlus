import SwiftUI
import WidgetKit

struct PowerEntry: TimelineEntry {
    let date: Date
    let snapshot: PowerSnapshot
}

struct PowerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PowerEntry { .init(date: Date(), snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (PowerEntry) -> Void) {
        completion(.init(date: Date(), snapshot: context.isPreview ? .preview : sample()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PowerEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [.init(date: now, snapshot: sample())], policy: .after(now.addingTimeInterval(900))))
    }
    private func sample() -> PowerSnapshot {
        // The widget sandbox grants access only to the AppleSMCClient user client.
        // Sample independently so the host app and a provisioned App Group aren't required.
        PowerReader.read()
    }
}

struct PowerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PowerEntry
    var body: some View {
        WidgetFace(snapshot: entry.snapshot, size: family == .systemSmall ? .small : family == .systemMedium ? .medium : .large)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Palette.surface, Palette.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .environment(\.colorScheme, .dark)
            .widgetURL(URL(string: "batteryhealthplus://overview"))
    }
}

@main struct BatteryHealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PowerSnapshot.widgetKind, provider: PowerProvider()) { PowerWidgetView(entry: $0) }
            .configurationDisplayName("BatteryHealth++")
            .description("Battery health and power flow, at a glance. Desktop Macs show system power.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
