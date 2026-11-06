import Foundation

/// Registry reads are fresh copies of cached sensors, not new hardware samples.
/// Avoid presenting the previous source's flow while a connection change settles.
public struct PowerTransitionFilter {
    private var previous: PowerSnapshot?
    private var transition: PowerSnapshot?
    private static let maximumWait: TimeInterval = 90

    public init() {}

    public mutating func process(_ sample: PowerSnapshot) -> PowerSnapshot {
        defer { previous = sample }
        // Direct SMC flow does not depend on the battery driver's cache clock.
        if sample.hasDirectPowerFlow {
            transition = nil
            return sample
        }
        guard sample.batteryPresent, let connected = sample.externalPower else {
            transition = nil
            return sample
        }
        let changed = previous?.externalPower.map { $0 != connected } ?? false
        let looksLikeOldDischarge = connected && (sample.input?.watts ?? 0) <= 0.5 &&
            (sample.battery?.watts ?? 0) < -0.5
        // Also cover launching the app in the middle of the connection change.
        if changed || (previous?.externalPower == nil && looksLikeOldDischarge) { transition = sample }
        guard let initial = transition else { return sample }

        let elapsed = sample.date.timeIntervalSince(initial.date)
        let batteryUpdated: Bool
        if let initialDate = initial.batterySampleDate, let date = sample.batterySampleDate {
            batteryUpdated = date > initialDate
        } else {
            // Older drivers may not expose a timestamp. A changing electrical
            // measurement is evidence of a new sample; app polling alone isn't.
            batteryUpdated = sample.currentAmps != initial.currentAmps || sample.voltage != initial.voltage
        }
        let sourceHasPower = connected && (sample.input?.watts ?? 0) > 0.5 && (sample.battery?.watts ?? 0) > 0.5
        let batteryHasTakenOver = !connected && (sample.battery?.watts ?? 0) < -0.5
        if sourceHasPower || batteryHasTakenOver || batteryUpdated || elapsed >= Self.maximumWait {
            transition = nil
            return sample
        }

        var result = sample
        result.powerFlowSettling = true
        result.battery = nil
        result.currentAmps = nil
        result.minutesRemaining = nil
        if connected && (result.input?.watts ?? 0) <= 0.5 { result.input = nil }
        // A measured system-load sensor remains useful; a calculation based on
        // the stale battery current does not.
        if result.device?.estimated == true { result.device = nil }
        result.notes.append("Power readings are updating after a power-source change.")
        return result
    }
}
