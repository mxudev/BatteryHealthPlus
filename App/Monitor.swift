import AppKit
import IOKit.ps
import SwiftUI

@MainActor final class Monitor: ObservableObject {
    @Published private(set) var snapshot = PowerSnapshot()
    @Published private(set) var history: [PowerPoint] = []
    private var timer: Timer?
    private let liveWindows = NSHashTable<NSWindow>.weakObjects()
    private var hasVisibleLiveView = false
    private var powerSource: CFRunLoopSource?
    private var sleeping = false
    private var isRefreshing = false
    private var refreshPending = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        observe(NSWorkspace.willSleepNotification, center: NSWorkspace.shared.notificationCenter) { monitor in
            monitor.sleeping = true
            monitor.timer?.invalidate()
        }
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter) { monitor in
            monitor.sleeping = false
            monitor.requestRefresh()
        }
        // Occlusion also covers hiding, other Spaces, and covered windows. Only
        // registered telemetry windows count; Settings and the status item don't.
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observe(name) { $0.updateVisibility() }
        }
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<Monitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.requestRefresh() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        requestRefresh()
    }

    deinit {
        timer?.invalidate()
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        for (center, token) in observers { center.removeObserver(token) }
    }

    /// Called after presentation, including when a retained window is reopened.
    func viewOpened(in window: NSWindow) {
        liveWindows.add(window)
        updateVisibility(refreshOnReveal: false)
        requestRefresh()
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter = .default,
                         action: @escaping @MainActor (Monitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            // Read state after AppKit finishes the close/hide/minimize operation.
            Task { @MainActor [weak self] in
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    private func updateVisibility(refreshOnReveal: Bool = true) {
        let visible = !NSApp.isHidden && liveWindows.allObjects.contains {
            $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        }
        guard visible != hasVisibleLiveView else { return }
        hasVisibleLiveView = visible
        if visible && refreshOnReveal { requestRefresh() }
        else if !isRefreshing { scheduleNextRefresh() }
    }

    private func requestRefresh() {
        timer?.invalidate()
        Task { @MainActor [weak self] in await self?.refresh() }
    }

    private func scheduleNextRefresh() {
        timer?.invalidate()
        guard !sleeping else { return }
        let timer = Timer(timeInterval: hasVisibleLiveView ? 1 : 5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        timer.tolerance = hasVisibleLiveView ? 0.1 : 0.5
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func refresh() async {
        guard !sleeping else { return }
        // Preserve a power/visibility event arriving during a sensor read, without
        // starting concurrent reads or creating multiple sampling loops.
        guard !isRefreshing else { refreshPending = true; return }
        timer?.invalidate()
        isRefreshing = true
        repeat {
            refreshPending = false
            let sample = await Task.detached(priority: .utility) { PowerReader.read() }.value
            guard !sleeping else { break }
            snapshot = sample
            history.append(PowerPoint(sample))
            history.removeAll { $0.date < sample.date.addingTimeInterval(-600) }

        } while refreshPending
        isRefreshing = false
        scheduleNextRefresh()
    }
}
