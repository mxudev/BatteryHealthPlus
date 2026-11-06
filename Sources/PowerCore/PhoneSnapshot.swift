import Foundation

public struct PhoneSnapshot: Codable, Equatable, Sendable {
    public var date = Date()
    public var chargePercent: Double?
    public var input: PowerReading?
    public var device: PowerReading?
    public var battery: PowerReading?
    public var message: String?

    public init(message: String? = nil) { self.message = message }

    public static func parse(_ response: [String: Any]) -> PhoneSnapshot {
        guard response["Status"] as? String == "Success",
              let diagnostics = response["Diagnostics"] as? [String: Any],
              let root = diagnostics["IORegistry"] as? [String: Any] else {
            return PhoneSnapshot(message: "Power readings unavailable")
        }
        var result = PhoneSnapshot()
        let telemetry = root["PowerTelemetryData"] as? [String: Any] ?? [:]
        func power(_ key: String, signed: Bool = false) -> PowerReading? {
            let value = signed ? TelemetryParser.signed(telemetry[key]) : TelemetryParser.finite(telemetry[key])
            guard let value, value.isFinite, abs(value) <= 200_000, signed || value >= 0 else { return nil }
            return PowerReading(value / 1000, source: "iPhone PowerTelemetryData.\(key)")
        }
        result.input = power("SystemPowerIn")
        result.device = power("SystemLoad")
        result.battery = power("BatteryPower", signed: true)
        if let current = TelemetryParser.finite(root["CurrentCapacity"]),
           let maximum = TelemetryParser.finite(root["MaxCapacity"]), maximum > 0,
           current >= 0, current <= maximum {
            result.chargePercent = current / maximum * 100
        }
        // AdapterDetails is a negotiated limit, never an input measurement.
        if result.input == nil && result.device == nil && result.battery == nil {
            result.message = "Power readings unavailable"
        }
        return result
    }
}
