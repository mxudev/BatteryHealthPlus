import AppKit
import SwiftUI

/// Explicit design fixtures, only reachable using --render-previews. Never used by live views.
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
        save(DashboardView(snapshot: snapshot, history: points).content.fixedSize(horizontal: false, vertical: true).frame(width: 880, height: 830, alignment: .top)
            .background(Palette.ink), to: directory.appendingPathComponent("overview.png"))
        save(WidgetFace(snapshot: snapshot, live: true).padding(25).frame(width: 354, height: 380)
            .background(Palette.ink).clipShape(RoundedRectangle(cornerRadius: 26)).preferredColorScheme(.dark),
             to: directory.appendingPathComponent("live-widget.png"))
        var desktop = PowerSnapshot()
        desktop.model = "Mac mini"; desktop.kind = .desktop
        desktop.device = .init(12.8, source: "AppleSMC.PSTR")
        save(WidgetFace(snapshot: desktop).padding(24).frame(width: 354, height: 340)
            .background(Palette.ink).clipShape(RoundedRectangle(cornerRadius: 26)).preferredColorScheme(.dark),
             to: directory.appendingPathComponent("desktop-widget.png"))
        for (name, size, width, height) in [("small", FaceSize.small, 170.0, 170.0), ("medium", .medium, 360.0, 170.0), ("large", .large, 360.0, 360.0)] {
            save(WidgetFace(snapshot: snapshot, size: size).padding(18).frame(width: width, height: height)
                .background(Palette.ink).clipShape(RoundedRectangle(cornerRadius: 22)).preferredColorScheme(.dark),
                 to: directory.appendingPathComponent("widget-\(name).png"))
        }
    }
    private static func save<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }
}
