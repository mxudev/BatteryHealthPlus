import AppKit
import Combine
import SwiftUI
import ServiceManagement

/// AppKit owns presentation: launching/restoring never creates an overview window.
@main @MainActor enum BatteryHealthApp {
    static func main() {
        let application = NSApplication.shared
        if CommandLine.arguments.contains("--diagnose") {
            let sample = PowerReader.read()
            print("Hardware: \(sample.model); battery: \(sample.batteryPresent); device power: \(Display.decimal(sample.device?.watts)) W")
            print("SMC system power: \(Display.decimal(SMCReader().systemPower())) W")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 1 {
            PreviewRenderer.render(to: CommandLine.arguments[index + 1])
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var monitor = Monitor()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var subscription: AnyCancellable?
    private var overview: NSWindow?
    private var settings: NSWindow?
    private var openedFromURL = false
    private var initialPresentation: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "BatteryHealthStatus"
        item.button?.target = self
        item.button?.action = #selector(toggleMenu)
        item.button?.setAccessibilityLabel("BatteryHealth++")
        statusItem = item
        subscription = monitor.$snapshot.sink { [weak self] sample in
            guard let button = self?.statusItem?.button else { return }
            let image = NSImage(systemSymbolName: sample.kind == .desktop ? "bolt" : "battery.75percent", accessibilityDescription: "BatteryHealth++")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            button.title = " " + (sample.batteryPresent ? "\(Display.decimal(sample.chargePercent, digits: 0))%" : "\(Display.decimal(sample.device?.watts)) W")
            button.toolTip = "BatteryHealth++ · \(sample.status)"
        }
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: MenuPanel(monitor: monitor,
            onOpen: { [weak self] in self?.showOverview() }, onFloat: { [weak self] in self?.showFloating() },
            onSettings: { [weak self] in self?.showSettings() }))
        // Launch Services and the status bar finish installing/activating asynchronously.
        // Present after that transition, otherwise a transient popover can dismiss at launch.
        initialPresentation = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !self.openedFromURL, !Task.isCancelled else { return }
            self.showMenu()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        initialPresentation?.cancel()
        showMenu()
        return false
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "batteryhealthplus" && $0.host == "overview" }) else { return }
        openedFromURL = true
        initialPresentation?.cancel()
        showOverview()
    }

    @objc private func toggleMenu() {
        if popover.isShown { popover.performClose(nil) } else { showMenu() }
    }
    private func showMenu() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        // Position using the final SwiftUI size. Otherwise NSPopover uses its
        // default 320pt height, then grows upward after presentation and clips
        // the header behind the menu bar.
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            popover.contentSize = view.fittingSize
        }
        // AppKit interprets the edge in the button's coordinate system. A flipped
        // status button's lower edge is maxY, not minY.
        let bounds = button.bounds
        let anchor = NSRect(x: bounds.minX, y: button.isFlipped ? bounds.maxY - 1 : bounds.minY,
                            width: bounds.width, height: 1)
        popover.show(relativeTo: anchor, of: button, preferredEdge: button.isFlipped ? .maxY : .minY)
        if let window = popover.contentViewController?.view.window {
            window.makeKey()
            monitor.viewOpened(in: window)
        }
    }
    @objc private func showOverview() {
        popover.performClose(nil)
        if overview == nil {
            let size = DashboardView.minimumContentSize
            let window = makeWindow(title: "BatteryHealth++", size: size, resizable: true)
            window.contentView = NSHostingView(rootView: OverviewContent(monitor: monitor, onFloat: { [weak self] in self?.showFloating() }))
            window.contentMinSize = size
            window.setFrameAutosaveName("CompactOverview")
            // Clamp any previously saved frame from the smaller, scrolling layout.
            let contentSize = window.contentLayoutRect.size
            if contentSize.width < size.width || contentSize.height < size.height {
                window.setContentSize(NSSize(width: max(contentSize.width, size.width),
                                             height: max(contentSize.height, size.height)))
            }
            overview = window
        }
        overview?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let overview { monitor.viewOpened(in: overview) }
    }
    @objc private func showFloating() {
        popover.performClose(nil)
        FloatingPanel.shared.show(monitor: monitor)
    }
    @objc private func showSettings() {
        popover.performClose(nil)
        if settings == nil {
            let window = makeWindow(title: "Settings", size: NSSize(width: 360, height: 140))
            window.contentView = NSHostingView(rootView: SettingsView().padding(20).frame(width: 360))
            settings = window
        }
        settings?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func closeSurface() {
        if popover.isShown { popover.performClose(nil) }
        else if let window = NSApp.keyWindow, window === overview || window === settings || window is LivePanel {
            window.performClose(nil)
        }
    }
    private func makeWindow(title: String, size: NSSize, resizable: Bool = false) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        return window
    }
    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let menu = NSMenu(title: "BatteryHealth++")
        for (title, action, key) in [("Open Window", #selector(showOverview), "o"),
                                     ("Float", #selector(showFloating), "f"),
                                     ("Settings…", #selector(showSettings), ",")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            if title == "Float" { item.keyEquivalentModifierMask = [.command, .shift] }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit BatteryHealth++", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = menu
        main.addItem(appItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let close = NSMenuItem(title: "Close Window", action: #selector(closeSurface), keyEquivalent: "w")
        close.target = self
        windowMenu.addItem(close)
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }
}

private struct OverviewContent: View {
    @ObservedObject var monitor: Monitor
    var onFloat: () -> Void
    var body: some View {
        DashboardView(snapshot: monitor.snapshot, history: monitor.history, onFloat: onFloat)
    }
}

struct MenuPanel: View {
    @ObservedObject var monitor: Monitor
    var onOpen: () -> Void
    var onFloat: () -> Void
    var onSettings: () -> Void
    var body: some View {
        MenuCard(snapshot: monitor.snapshot, onOpen: onOpen, onFloat: onFloat, onSettings: onSettings)
    }
}

struct MenuCard: View {
    let snapshot: PowerSnapshot
    var onOpen: () -> Void = {}
    var onFloat: () -> Void = {}
    var onSettings: () -> Void = {}
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("BatteryHealth++").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(snapshot.isStale() ? "Waiting" : "Live").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                TelemetryReadout(snapshot: snapshot)
            }.padding(10)
            Divider().padding(.horizontal, 7)
            VStack(spacing: 0) {
                MenuAction(title: "Open Window", symbol: "macwindow", shortcut: "⌘O", action: onOpen)
                MenuAction(title: "Float", symbol: "pip", shortcut: "⇧⌘F", action: onFloat)
                MenuAction(title: "Settings…", symbol: "slider.horizontal.3", shortcut: "⌘,", action: onSettings)
                Divider().padding(.vertical, 3)
                MenuAction(title: "Quit", symbol: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
            }.padding(5)
        }.frame(width: 260).fixedSize(horizontal: false, vertical: true)
    }
}

private struct MenuAction: View {
    var title: String
    var symbol: String
    var shortcut: String
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 11)).frame(width: 14)
                Text(title)
                Spacer()
                Text(shortcut).foregroundStyle(hovering ? Color.white.opacity(0.7) : Color.secondary)
            }.font(.system(size: 13)).padding(.horizontal, 8).frame(height: 24)
                .foregroundStyle(hovering ? Color.white : Color.primary)
                .background(hovering ? Color(nsColor: .selectedContentBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
    }
}

@MainActor final class FloatingPanel {
    static let shared = FloatingPanel()
    private var panel: NSPanel?
    func show(monitor: Monitor) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            monitor.viewOpened(in: panel)
            return
        }
        let panel = LivePanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 320),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Live power"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: FloatingContent(monitor: monitor, close: { [weak self] in self?.panel?.orderOut(nil) }))
        panel.contentView = view
        panel.setContentSize(view.fittingSize)
        panel.setFrameAutosaveName("CompactLiveWidget")
        if !panel.setFrameUsingName("CompactLiveWidget"), let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 280, y: screen.visibleFrame.maxY - panel.frame.height - 20))
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        monitor.viewOpened(in: panel)
    }
}

private final class LivePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func performClose(_ sender: Any?) { orderOut(sender) }
}

private struct FloatingContent: View {
    @ObservedObject var monitor: Monitor
    var close: () -> Void
    var body: some View { FloatingCard(snapshot: monitor.snapshot, close: close) }
}

struct FloatingCard: View {
    let snapshot: PowerSnapshot
    var close: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BatteryHealth++").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Close floating panel").accessibilityLabel("Close floating panel")
            }
            TelemetryReadout(snapshot: snapshot)
            Text(snapshot.isStale() ? "Waiting for a reading" : "Live").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(12).frame(width: 260).fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.10), lineWidth: 0.5))
    }
}

struct SettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            MetricRow(label: "Appearance", value: "System")
            if let error { Text(error).foregroundStyle(.orange) }
        }.font(.system(size: 11)).textSelection(.enabled)
    }
}
