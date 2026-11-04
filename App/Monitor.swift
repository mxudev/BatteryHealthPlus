import AppKit
import SwiftUI
import WidgetKit

@MainActor final class Monitor: ObservableObject {
    @Published private(set) var snapshot = PowerSnapshot()
    @Published private(set) var history: [PowerPoint] = []
    private var task: Task<Void, Never>?
    private var lastReload = Date.distantPast
    private var lastExternalPower: Bool?
    private var sleeping = false
    private var isRefreshing = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; await self?.refresh() }
        })
        task = Task { [weak self] in
            while !Task.isCancelled {
                if let self, !self.sleeping { await self.refresh() }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let sample = await Task.detached(priority: .utility) { PowerReader.read() }.value
        snapshot = sample
        history.append(PowerPoint(sample))
        history.removeAll { $0.date < sample.date.addingTimeInterval(-600) }
        let changedSource = lastExternalPower != sample.externalPower
        // Do not ask chronod to redraw at the live panel's sampling frequency.
        if sample.date.timeIntervalSince(lastReload) >= 900 ||
            (changedSource && sample.date.timeIntervalSince(lastReload) >= 60) {
            WidgetCenter.shared.reloadTimelines(ofKind: PowerSnapshot.widgetKind)
            lastReload = sample.date
        }
        lastExternalPower = sample.externalPower
    }
}
