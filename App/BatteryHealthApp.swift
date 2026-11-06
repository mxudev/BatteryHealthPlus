import AppKit
import Combine
import SwiftUI
import ServiceManagement

/// AppKit owns presentation: launching/restoring never creates an overview window.
@main @MainActor enum BatteryHealthApp {
    static func main() {
        if CommandLine.arguments.contains("--diagnose-iphone"), let executable = Bundle.main.executableURL {
            if let phone = PhoneSampler.read(executable: executable), let data = try? JSONEncoder().encode(phone) {
                FileHandle.standardOutput.write(data)
            }
            return
        }
        if CommandLine.arguments.contains("--read-iphone") {
            if let phone = PhoneReader.read(), let data = try? JSONEncoder().encode(phone) {
                FileHandle.standardOutput.write(data)
            }
            return
        }
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

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var monitor = Monitor()
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu(title: "BatteryHealth++")
    private var menuReadout: NSHostingView<MenuCard>?
    private var menuOpen = false
    private var subscription: AnyCancellable?
    private var overview: NSWindow?
    private var settings: NSWindow?
    private var openedFromURL = false
    private var initialPresentation: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "BatteryHealthStatus"
        item.button?.setAccessibilityLabel("BatteryHealth++")
        statusItem = item
        configureStatusMenu()
        item.menu = statusMenu
        subscription = monitor.$snapshot.sink { [weak self] sample in
            self?.updateStatusItem(sample)
            self?.updateMenuReadout(sample)
            self?.updateWindowSizes(sample)
        }
        // Wait for the status item to enter the menu bar before opening its native menu.
        // No application activation or key window is needed.
        if !openedFromURL { scheduleMenuPresentation(after: 0.3) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        scheduleMenuPresentation()
        return false
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "batteryhealthplus" && $0.host == "overview" }) else { return }
        openedFromURL = true
        initialPresentation?.invalidate()
        showOverview()
    }

    private func scheduleMenuPresentation(after delay: TimeInterval = 0.01) {
        initialPresentation?.invalidate()
        guard !menuOpen else { return }
        // NSMenu tracks synchronously. Enter it from a run-loop timer, not a
        // Swift Task / dispatch block or an open-application event handler, so
        // main-queue sampling and Launch Services replies continue to run.
        let timer = Timer(timeInterval: delay, target: self, selector: #selector(showMenu), userInfo: nil, repeats: false)
        initialPresentation = timer
        RunLoop.main.add(timer, forMode: .default)
    }

    @objc private func showMenu() {
        guard !menuOpen else { return }
        // With a menu assigned, the native status button owns tracking and focus.
        statusItem?.button?.performClick(nil)
    }

    private func configureStatusMenu() {
        statusMenu.delegate = self
        statusMenu.autoenablesItems = false
        let readout = NSMenuItem(title: "Battery and power readings", action: nil, keyEquivalent: "")
        let view = NSHostingView(rootView: MenuCard(snapshot: monitor.snapshot))
        view.setFrameSize(view.fittingSize)
        readout.view = view
        readout.isEnabled = false
        menuReadout = view
        statusMenu.addItem(readout)
        statusMenu.addItem(.separator())
        addCommands(to: statusMenu)
    }

    private func updateStatusItem(_ sample: PowerSnapshot) {
        guard let button = statusItem?.button else { return }
        if sample.kind == .desktop {
            button.image = NSImage(systemSymbolName: "bolt", accessibilityDescription: nil)
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            button.title = " " + Display.watts(sample.device)
            button.setAccessibilityValue("System draw, \(Display.watts(sample.device))")
        } else {
            button.image = StatusIcon.battery(percent: sample.chargePercent, charging: sample.charging == true)
            button.imagePosition = .imageOnly
            button.title = ""
            button.setAccessibilityValue("\(Display.decimal(sample.chargePercent, digits: 0)) percent, \(sample.status)")
        }
        button.toolTip = sample.kind == .desktop ? "BatteryHealth++ · \(Display.watts(sample.device))" :
            "BatteryHealth++ · \(Display.decimal(sample.chargePercent, digits: 0))% · \(sample.status)"
    }

    private func updateMenuReadout(_ sample: PowerSnapshot) {
        guard let view = menuReadout else { return }
        view.rootView = MenuCard(snapshot: sample)
        view.layoutSubtreeIfNeeded()
        // NSMenuItem uses the view's explicit frame and repositions itself when
        // its size changes. Never manipulate the menu's AppKit-owned window.
        let size = view.fittingSize
        if view.frame.size != size { view.setFrameSize(size) }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        menuOpen = true
        initialPresentation?.invalidate()
        updateMenuReadout(monitor.snapshot)
        monitor.setMenuVisible(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        menuOpen = false
        monitor.setMenuVisible(false)
    }

    private func updateWindowSizes(_ sample: PowerSnapshot) {
        if let overview {
            let minimum = DashboardView.minimumSize(for: sample)
            overview.contentMinSize = minimum
            let current = overview.contentLayoutRect.size
            if current.height < minimum.height {
                overview.setContentSize(NSSize(width: max(current.width, minimum.width), height: minimum.height))
            }
        }
        DispatchQueue.main.async { FloatingPanel.shared.resizeToFit() }
    }

    @objc private func showOverview() {
        statusMenu.cancelTracking()
        if overview == nil {
            let size = DashboardView.minimumSize(for: monitor.snapshot)
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
        statusMenu.cancelTracking()
        FloatingPanel.shared.show(monitor: monitor)
    }
    @objc private func showSettings() {
        statusMenu.cancelTracking()
        if settings == nil {
            let window = makeWindow(title: "Settings", size: NSSize(width: 360, height: 140))
            window.contentView = NSHostingView(rootView: SettingsView().padding(20).frame(width: 360))
            settings = window
        }
        settings?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func closeSurface() {
        statusMenu.cancelTracking()
        if let window = NSApp.keyWindow, window === overview || window === settings || window is LivePanel {
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
        addCommands(to: menu)
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
    private func addCommands(to menu: NSMenu) {
        for (title, action, key) in [("Open Window", #selector(showOverview), "o"),
                                     ("Float", #selector(showFloating), "f"),
                                     ("Settings…", #selector(showSettings), ",")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            if title == "Float" { item.keyEquivalentModifierMask = [.command, .shift] }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit BatteryHealth++", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
    }

}

private struct OverviewContent: View {
    @ObservedObject var monitor: Monitor
    var onFloat: () -> Void
    var body: some View {
        DashboardView(snapshot: monitor.snapshot, history: monitor.history, onFloat: onFloat)
    }
}

/// Read-only content inside a native NSMenuItem; commands are regular NSMenuItems.
struct MenuCard: View {
    let snapshot: PowerSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BatteryHealth++").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(snapshot.isStale() ? "Waiting" : "Live").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            TelemetryReadout(snapshot: snapshot)
        }.padding(12).frame(width: 260).fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor final class FloatingPanel {
    static let shared = FloatingPanel()
    private var panel: NSPanel?
    func resizeToFit() {
        guard let panel, let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        guard size.height > 0, abs(panel.frame.height - size.height) > 0.5 else { return }
        let top = panel.frame.maxY
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - panel.frame.height))
    }

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
