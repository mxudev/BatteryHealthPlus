import AppKit

/// A template image lets the native status button handle light/dark appearances
/// and selected-state contrast. The button retains its standard hit target.
@MainActor enum StatusIcon {
    static func battery(percent: Double?, charging: Bool) -> NSImage {
        let number = percent.flatMap { $0.isFinite ? Int(min(100, max(0, $0)).rounded()) : nil }
        let label = number.map(String.init) ?? "–"
        let image = NSImage(size: NSSize(width: 36, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let body = NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: 30, height: 14), xRadius: 3, yRadius: 3)
            body.lineWidth = 1.3
            body.stroke()
            NSBezierPath(roundedRect: NSRect(x: 32.5, y: 6, width: 2.2, height: 6), xRadius: 1, yRadius: 1).fill()

            if charging {
                let bolt = NSBezierPath()
                bolt.move(to: NSPoint(x: 7.5, y: 14))
                bolt.line(to: NSPoint(x: 3.5, y: 8))
                bolt.line(to: NSPoint(x: 6, y: 8))
                bolt.line(to: NSPoint(x: 5, y: 4))
                bolt.line(to: NSPoint(x: 9, y: 10))
                bolt.line(to: NSPoint(x: 6.5, y: 10))
                bolt.close()
                bolt.fill()
            }
            let text = NSAttributedString(string: label, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.black
            ])
            let size = text.size()
            let centerX: CGFloat = charging ? 19.5 : 16
            text.draw(at: NSPoint(x: centerX - size.width / 2, y: (18 - size.height) / 2))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = number.map { "Battery, \($0) percent" } ?? "Battery level unavailable"
        return image
    }
}
