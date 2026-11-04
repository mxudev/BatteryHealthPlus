import AppKit
import SwiftUI
import ServiceManagement

@main struct BatteryHealthApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var monitor = Monitor()

    init() {
        if CommandLine.arguments.contains("--diagnose") {
            let sample = PowerReader.read()
            print("Hardware: \(sample.model); battery: \(sample.batteryPresent); device power: \(Display.decimal(sample.device?.watts)) W")
            print("SMC system power: \(Display.decimal(SMCReader().systemPower())) W")
            print("Desktop widget samples independently; no App Group required.")
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
           CommandLine.arguments.count > index + 1 {
            PreviewRenderer.render(to: CommandLine.arguments[index + 1])
            exit(0)
        }
    }

    var body: some Scene {
        Window("BatteryHealth++", id: "dashboard") {
            DashboardView(snapshot: monitor.snapshot, history: monitor.history,
                          onFloat: { FloatingPanel.shared.show(monitor: monitor) },
                          onRefresh: { Task { await monitor.refresh() } })
                .frame(minWidth: 800, minHeight: 690)
        }
        .defaultSize(width: 880, height: 830)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Show Floating Widget") { FloatingPanel.shared.show(monitor: monitor) }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra {
            MenuPanel(monitor: monitor)
        } label: {
            Image(systemName: monitor.snapshot.kind == .desktop ? "bolt.circle" : "battery.75percent")
            Text(monitor.snapshot.batteryPresent ? "\(Display.decimal(monitor.snapshot.chargePercent, digits: 0))%" :
                    "\(Display.decimal(monitor.snapshot.device?.watts)) W")
        }.menuBarExtraStyle(.window)
        Settings { SettingsView().frame(width: 420).padding(26) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct MenuPanel: View {
    @ObservedObject var monitor: Monitor
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing: 18) {
            WidgetFace(snapshot: monitor.snapshot, live: true)
            Divider().opacity(0.5)
            HStack {
                Button("Overview") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
                Button { FloatingPanel.shared.show(monitor: monitor) } label: { Image(systemName: "rectangle.on.rectangle") }
                    .help("Show floating widget")
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit BatteryHealth++")
            }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
        }.padding(23).frame(width: 354).background(Palette.ink).preferredColorScheme(.dark)
    }
}

@MainActor final class FloatingPanel {
    static let shared = FloatingPanel()
    private var panel: NSPanel?

    func show(monitor: Monitor) {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        let panel = LivePanel(contentRect: NSRect(x: 0, y: 0, width: 354, height: 380),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.title = "Live power widget"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: FloatingContent(monitor: monitor, close: { [weak self] in self?.panel?.orderOut(nil) }))
        panel.setFrameAutosaveName("LivePowerWidget")
        if !panel.setFrameUsingName("LivePowerWidget"), let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 380, y: screen.visibleFrame.maxY - 420))
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }
}

private final class LivePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct FloatingContent: View {
    @ObservedObject var monitor: Monitor
    var close: () -> Void
    @State private var hovering = false
    var body: some View {
        WidgetFace(snapshot: monitor.snapshot, live: true)
            .padding(25).frame(width: 354, height: 380)
            .background(Palette.ink.opacity(0.97), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.10), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).padding(8).opacity(hovering ? 1 : 0)
                    .accessibilityLabel("Close floating widget")
            }
            .onHover { hovering = $0 }.preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Make yourself at home.").font(.system(size: 23, weight: .medium, design: .rounded))
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Divider()
            Text("Add a desktop widget").font(.headline)
            Text("Open BatteryHealth++ once, then right-click your desktop, choose Edit Widgets, and search for BatteryHealth. Choose a small, medium, or large widget.")
            Text("Desktop widgets show the time of their latest sample. For live readings, use Float widget or the menu bar panel.")
            Text("Built for Apple Silicon · macOS 14 or later").foregroundStyle(.tertiary)
            if let error { Text(error).foregroundStyle(.orange) }
        }.font(.system(size: 12)).textSelection(.enabled)
    }
}
