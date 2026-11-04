import AppKit
import SwiftUI

/// Explicit fixtures used only by --render-previews; live views never use sample data.
@MainActor enum PreviewRenderer {
    static func render(to path: String) {
        let directory = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshot = PowerSnapshot.preview
        let points = (0..<120).map { index -> PowerPoint in
            var sample = snapshot
            sample.date = snapshot.date.addingTimeInterval(Double(index - 119) * 5)
            sample.input?.watts = 48.2 + sin(Double(index) * 0.12) * 1.4
            sample.device?.watts = 16.2 + sin(Double(index) * 0.19) * 2.1 + (index > 65 && index < 82 ? 9 : 0)
            return PowerPoint(sample)
        }
        var desktop = PowerSnapshot()
        desktop.model = "Mac mini"; desktop.kind = .desktop
        desktop.device = .init(12.8, source: "AppleSMC.PSTR")
        var unplugged = snapshot
        unplugged.externalPower = false; unplugged.charging = false
        unplugged.input = .init(0, source: "Preview"); unplugged.battery = .init(-16.2, source: "Preview")
        var assisting = snapshot
        assisting.charging = false; assisting.input = .init(12, source: "Preview")
        assisting.battery = .init(-4.2, source: "Preview")
        var idle = snapshot
        idle.charging = false; idle.input = idle.device; idle.battery = .init(0, source: "Preview")
        var unavailable = snapshot
        unavailable.input = nil; unavailable.device = nil; unavailable.battery = nil
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            func save<V: View>(_ view: V, name: String) {
                render(view, scheme: scheme, to: directory.appendingPathComponent("\(name)-\(suffix).png"))
            }
            save(MenuCard(snapshot: snapshot).background(Palette.background)
                .clipShape(RoundedRectangle(cornerRadius: 10)), name: "menu")
            save(VStack(spacing: 16) {
                ForEach(Array([snapshot, unplugged, assisting, idle, unavailable].enumerated()), id: \.offset) { _, sample in
                    PowerFlowView(snapshot: sample)
                    Divider()
                }
            }.padding(10).frame(width: 260).background(Palette.background), name: "power-flow-states")
            save(FloatingCard(snapshot: snapshot), name: "live-widget")
            save(DashboardView(snapshot: snapshot, history: points)
                .frame(width: DashboardView.minimumContentSize.width,
                       height: DashboardView.minimumContentSize.height), name: "overview")
            save(MenuCard(snapshot: desktop).background(Palette.background)
                .clipShape(RoundedRectangle(cornerRadius: 10)), name: "desktop-menu")
            save(WidgetFace(snapshot: desktop).padding(16).frame(width: 360, height: 360)
                .background(Palette.background).clipShape(RoundedRectangle(cornerRadius: 18)), name: "desktop-widget")
            for (name, size, width, height) in [("small", FaceSize.small, 170.0, 170.0), ("medium", .medium, 360.0, 170.0), ("large", .large, 360.0, 360.0)] {
                save(WidgetFace(snapshot: snapshot, size: size).padding(16).frame(width: width, height: height)
                    .background(Palette.background).clipShape(RoundedRectangle(cornerRadius: 18)), name: "widget-\(name)")
            }
        }
        // Keep existing README links pointing to the current design.
        for name in ["overview", "live-widget", "desktop-widget", "widget-small", "widget-medium", "widget-large"] {
            if let data = try? Data(contentsOf: directory.appendingPathComponent("\(name)-dark.png")) {
                try? data.write(to: directory.appendingPathComponent("\(name).png"))
            }
        }
    }

    private static func render<V: View>(_ view: V, scheme: ColorScheme, to url: URL) {
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
            renderer.scale = 2
            guard let image = renderer.cgImage else { return }
            if let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
        }
    }
}
