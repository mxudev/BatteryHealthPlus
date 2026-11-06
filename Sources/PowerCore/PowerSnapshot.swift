import Foundation

public enum MacKind: String, Codable, Sendable {
    case portable, desktop, unknown
}

public struct PowerReading: Codable, Equatable, Sendable {
    public var watts: Double
    public var source: String
    public var estimated: Bool

    public init(_ watts: Double, source: String, estimated: Bool = false) {
        self.watts = watts
        self.source = source
        self.estimated = estimated
    }
}

public struct PowerSnapshot: Codable, Equatable, Sendable {
    public var date = Date()
    public var model = "Apple Silicon Mac"
    public var kind: MacKind = .unknown
    public var batteryPresent = false
    public var externalPower: Bool?
    public var charging: Bool?
    public var chargePercent: Double?
    public var fullCapacityMAh: Double?
    public var designCapacityMAh: Double?
    public var nominalCapacityMAh: Double?
    public var cycles: Int?
    public var designCycles: Int?
    public var temperatureC: Double?
    public var voltage: Double?
    public var currentAmps: Double?
    public var minutesRemaining: Int?
    public var condition: String?
    public var adapterRatingWatts: Double?
    public var input: PowerReading?
    public var device: PowerReading?
    /// Positive = into the battery. Negative = battery supplying the Mac.
    public var battery: PowerReading?
    /// Driver timestamp, distinct from when the app read the cached registry values.
    public var batterySampleDate: Date?
    public var powerFlowSettling = false
    /// Both input and load were read directly from SMC in this sample.
    public var hasDirectPowerFlow = false
    public var phone: PhoneSnapshot?
    public var notes: [String] = []

    public init() {}

    public var healthPercent: Double? {
        guard let full = fullCapacityMAh, let design = designCapacityMAh,
              full > 0, design > 0 else { return nil }
        return full / design * 100
    }

    public var status: String {
        if kind == .desktop { return "Desktop power" }
        guard batteryPresent else { return "Waiting for battery data" }
        if charging == true { return "Charging" }
        if powerFlowSettling { return "Power updating" }
        if externalPower == true {
            if let watts = battery?.watts, watts < -0.5 { return "Battery assisting" }
            return (chargePercent ?? 0) >= 99 ? "Fully charged" : "Charging paused"
        }
        if externalPower == false { return "On battery" }
        return "Battery"
    }

    public func isStale(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(date) > 120
    }

    public static var preview: PowerSnapshot {
        var s = PowerSnapshot()
        s.model = "MacBook Pro"; s.kind = .portable; s.batteryPresent = true
        s.externalPower = true; s.charging = true; s.chargePercent = 72
        s.fullCapacityMAh = 7816; s.designCapacityMAh = 8694; s.nominalCapacityMAh = 7900
        s.cycles = 246; s.designCycles = 1000; s.temperatureC = 29.4
        s.voltage = 12.6; s.currentAmps = 2.54; s.minutesRemaining = 48
        s.condition = "Good"; s.adapterRatingWatts = 96
        s.input = .init(48.2, source: "PowerTelemetryData.SystemPowerIn")
        s.device = .init(16.2, source: "PowerTelemetryData.SystemLoad")
        s.battery = .init(32, source: "PowerTelemetryData.BatteryPower")
        return s
    }
}

public struct PowerPoint: Codable, Equatable, Sendable, Identifiable {
    public var date: Date
    public var input: Double?
    public var device: Double?
    public var battery: Double?
    public var id: Date { date }
    public init(_ snapshot: PowerSnapshot) {
        date = snapshot.date; input = snapshot.input?.watts
        device = snapshot.device?.watts; battery = snapshot.battery?.watts
    }
}
