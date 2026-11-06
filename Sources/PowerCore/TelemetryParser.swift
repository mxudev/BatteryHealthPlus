import Foundation

/// Pure parsing keeps undocumented fields, unit conversions and fallbacks testable.
public enum TelemetryParser {
    public static func parse(root: [String: Any], pack: [String: Any] = [:],
                             publicSource: [String: Any] = [:], model: String,
                             boardPower: Double? = nil, inputPower: Double? = nil,
                             hasClamshell: Bool = false, date: Date = Date()) -> PowerSnapshot {
        var s = PowerSnapshot()
        s.date = date; s.model = model
        let data = root["BatteryData"] as? [String: Any] ?? [:]
        let packData = pack["BatteryData"] as? [String: Any] ?? pack
        let fields = [root, data, packData]
        func number(_ keys: [String]) -> Double? {
            for key in keys {
                for field in fields {
                    if let value = finite(field[key]) { return value }
                }
            }
            return nil
        }
        s.batteryPresent = (root["BatteryInstalled"] as? Bool) ?? (!publicSource.isEmpty || !data.isEmpty || !packData.isEmpty)
        // A missing sensor on a MacBook must never turn it into a desktop.
        s.kind = s.batteryPresent || hasClamshell || model.hasPrefix("MacBook") ? .portable :
            (model.hasPrefix("Mac") || model.hasPrefix("iMac") ? .desktop : .unknown)
        s.externalPower = root["ExternalConnected"] as? Bool
        if s.externalPower == nil, let state = publicSource["Power Source State"] as? String {
            s.externalPower = state == "AC Power"
        }
        s.charging = root["IsCharging"] as? Bool ?? publicSource["Is Charging"] as? Bool
        if s.externalPower == false { s.charging = false }
        if let updated = finite(root["UserVisiblePathUpdated"]), updated > 0 {
            s.batterySampleDate = Date(timeIntervalSince1970: updated)
        }
        if s.batteryPresent {
            let current = finite(publicSource["Current Capacity"]) ?? finite(root["CurrentCapacity"])
            let max = finite(publicSource["Max Capacity"]) ?? finite(root["MaxCapacity"])
            if let current, let max, max > 0, current >= 0, current <= max {
                s.chargePercent = current / max * 100
            }
            s.fullCapacityMAh = positive(number(["AppleRawMaxCapacity", "FullChargeCapacity", "NominalChargeCapacity"]))
            s.designCapacityMAh = positive(number(["DesignCapacity"]))
            s.nominalCapacityMAh = positive(number(["NominalChargeCapacity"]))
            s.cycles = integer(number(["CycleCount"]), range: 0...100_000)
            s.designCycles = integer(number(["DesignCycleCount9C"]), range: 1...100_000)
            if let temperature = number(["Temperature"]), (0...10000).contains(temperature) {
                s.temperatureC = temperature / 100
            }
            s.voltage = positive(number(["Voltage", "AppleRawBatteryVoltage"])).map { $0 / 1000 }
            for field in fields {
                if let current = signed(field["InstantAmperage"] ?? field["Amperage"]), abs(current) < 100_000 {
                    s.currentAmps = current / 1000
                    break
                }
            }
            let timeKey = s.charging == true ? "Time to Full Charge" : "Time to Empty"
            if s.charging == true || s.externalPower == false {
                s.minutesRemaining = integer(finite(publicSource[timeKey]) ?? number([s.charging == true ? "AvgTimeToFull" : "AvgTimeToEmpty"]), range: 1...1440)
            }
            s.condition = publicSource["BatteryHealth"] as? String
        }
        let adapter = root["AdapterDetails"] as? [String: Any] ?? [:]
        if s.externalPower == true { s.adapterRatingWatts = positive(finite(adapter["Watts"])) }
        let telemetry = root["PowerTelemetryData"] as? [String: Any] ?? [:]
        func power(_ key: String, signedValue: Bool = false) -> PowerReading? {
            guard let value = signedValue ? signed(telemetry[key]) : finite(telemetry[key]),
                  abs(value) <= 2_000_000, signedValue || value >= 0 else { return nil }
            return .init(value / 1000, source: "PowerTelemetryData.\(key)")
        }
        // AdapterDetails.Watts is a negotiated capability, never a consumption reading.
        if s.externalPower == true { s.input = power("SystemPowerIn") }
        if s.externalPower == false { s.input = .init(0, source: "External power disconnected") }
        s.device = power("SystemLoad")
        if s.batteryPresent {
            let electrical = s.voltage.flatMap { voltage in s.currentAmps.map { voltage * $0 } }
            let measuredBattery = power("BatteryPower", signedValue: true)
            // These three values come from the same telemetry dictionary. A
            // coherent charging split is stronger evidence than a separately
            // cached battery current, which can still describe discharge.
            let coherentCharging: Bool
            if s.externalPower == true, let input = s.input, let device = s.device,
               let battery = measuredBattery, input.watts > 0.5, battery.watts > 0.5 {
                coherentCharging = abs(input.watts - device.watts - battery.watts) <= max(1, input.watts * 0.05)
            } else {
                coherentCharging = false
            }
            if coherentCharging {
                s.battery = measuredBattery
                s.charging = true
                if (electrical ?? 0) < -0.5 { s.currentAmps = nil }
            } else if let reading = measuredBattery,
               // Reject stale charging telemetry after unplugging or when current reverses.
               !(s.externalPower == false && reading.watts > 0),
               !(reading.watts > 0 && (electrical ?? 0) < -0.5),
               !(reading.watts < 0 && (electrical ?? 0) > 0.5),
               !(reading.watts == 0 && s.externalPower == false && (electrical ?? 0) < -0.5) {
                s.battery = reading
            } else if let electrical, electrical.isFinite, abs(electrical) < 2000,
                      !(s.externalPower == false && electrical > 0) {
                s.battery = .init(electrical, source: "Battery voltage × signed current", estimated: true)
            }
            // A confirmed charging flag must not be paired with a stale reverse
            // arrow. Leave the direction unknown until a measurement catches up.
            if s.charging == true && (s.battery?.watts ?? 0) < -0.5 {
                s.battery = nil
                s.currentAmps = nil
                s.powerFlowSettling = true
                if s.input?.watts == 0 { s.input = nil }
            }
            if s.externalPower == false && (s.currentAmps ?? 0) > 0 { s.currentAmps = nil }
        }
        if s.device == nil, let input = s.input, let battery = s.battery {
            let difference = input.watts - battery.watts
            if difference >= 0, difference < 2000 {
                s.device = .init(difference, source: "Input − battery (includes conversion losses)", estimated: true)
            }
        }
        // Apply direct sensors after the registry fallback has been parsed. Never
        // calculate a new split by mixing a direct value with a cached value.
        let directDevice = boardPower.flatMap { $0.isFinite && (0...2000).contains($0) ? $0 : nil }
        let directInput = inputPower.flatMap { $0.isFinite && (0...2000).contains($0) ? $0 : nil }
        if let directDevice { s.device = .init(directDevice, source: "AppleSMC.PSTR") }
        if s.batteryPresent, let directInput {
            s.input = .init(directInput, source: "AppleSMC.PDTR")
            // Positive measured input can arrive before the connection flag.
            if directInput > 0.5 {
                if s.externalPower != true { s.minutesRemaining = nil }
                s.externalPower = true
                s.adapterRatingWatts = positive(finite(adapter["Watts"]))
            }
            if let directDevice {
                let difference = directInput - directDevice
                // Separate reads have small timing/noise differences around zero.
                let batteryPower = abs(difference) <= 0.5 ? 0 : difference
                s.battery = .init(batteryPower, source: "AppleSMC.PDTR − PSTR (estimated net battery power)", estimated: true)
                s.hasDirectPowerFlow = true
                s.powerFlowSettling = false
                let charging = batteryPower > 0.5
                if s.charging != charging { s.minutesRemaining = nil }
                s.charging = charging
                // Keep health metadata from the registry, but don't display
                // cached current pointing against the direct power flow.
                if let current = s.currentAmps,
                   (batteryPower > 0.5 && current < 0) ||
                   (batteryPower < -0.5 && current > 0) ||
                   (batteryPower == 0 && abs(current) > 0.1) {
                    s.currentAmps = nil
                }
            }
        }
        if s.device == nil { s.notes.append("This Mac is not exposing a supported system power sensor.") }
        if s.kind == .portable && !s.batteryPresent { s.notes.append("Battery telemetry is currently unavailable.") }
        return s
    }

    static func finite(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }
    /// IORegistry can serialize negative currents as unsigned two's-complement integers.
    static func signed(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        if String(cString: number.objCType) == "f" || String(cString: number.objCType) == "d" {
            return finite(number)
        }
        let raw = number.uint64Value
        if raw > UInt64(Int64.max) { return Double(Int64(bitPattern: raw)) }
        // Some older drivers expose a signed 32-bit value in an unsigned field.
        if raw >= 0x8000_0000, raw <= 0xffff_ffff { return Double(Int32(bitPattern: UInt32(raw))) }
        return Double(number.int64Value)
    }
    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }; return value
    }
    private static func integer(_ value: Double?, range: ClosedRange<Int>) -> Int? {
        guard let value, value >= Double(range.lowerBound), value <= Double(range.upperBound) else { return nil }
        return Int(value)
    }
}
