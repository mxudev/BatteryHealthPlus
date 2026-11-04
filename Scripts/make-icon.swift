import AppKit
import SwiftUI

struct AppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 220).fill(
                LinearGradient(colors: [Color(red: 0.15, green: 0.21, blue: 0.21), Color(red: 0.04, green: 0.07, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 220).strokeBorder(.white.opacity(0.13), lineWidth: 4)
            Circle().stroke(.white.opacity(0.07), lineWidth: 35).frame(width: 660, height: 660)
            Circle().trim(from: 0, to: 0.86).stroke(
                AngularGradient(colors: [Color(red: 0.24, green: 0.55, blue: 0.48), Color(red: 0.53, green: 0.98, blue: 0.79)], center: .center),
                style: StrokeStyle(lineWidth: 35, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 660, height: 660)
            Image(systemName: "bolt.fill").font(.system(size: 330, weight: .medium)).foregroundStyle(Color(red: 0.55, green: 0.96, blue: 0.79))
        }.padding(40).frame(width: 1024, height: 1024)
    }
}

@MainActor func generate() throws {
    let directory = URL(fileURLWithPath: "Assets.xcassets/AppIcon.appiconset")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon-\(size)@\(scale)x.png"
            let renderer = ImageRenderer(content: AppIcon())
            renderer.scale = Double(size * scale) / 1024
            guard let image = renderer.cgImage else { continue }
            let bitmap = NSBitmapImageRep(cgImage: image)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
            images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
        }
    }
    let info: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("Contents.json"))
}
try MainActor.assumeIsolated { try generate() }
