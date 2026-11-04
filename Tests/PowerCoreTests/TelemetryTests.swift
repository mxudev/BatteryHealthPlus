import XCTest
@testable import PowerCore

final class TelemetryTests: XCTestCase {
    func testModernNestedBatteryAndMeasuredFlow() {
        let sample = TelemetryParser.parse(root: [
            "BatteryInstalled": true, "ExternalConnected": true, "IsCharging": true,
            "CurrentCapacity": 61, "MaxCapacity": 100,
            "BatteryData": ["DesignCapacity": 8694, "FullChargeCapacity": 6960, "NominalChargeCapacity": 7204],
            "PowerTelemetryData": ["SystemPowerIn": 56602, "SystemLoad": 12047, "BatteryPower": 44555],
            "AdapterDetails": ["Watts": 60]
        ], pack: ["BatteryData": ["CycleCount": 524, "Temperature": 2519]], model: "Mac14,6")
        XCTAssertEqual(sample.fullCapacityMAh, 6960)
        XCTAssertEqual(sample.designCapacityMAh, 8694)
        XCTAssertEqual(sample.cycles, 524)
        XCTAssertEqual(sample.temperatureC, 25.19)
        XCTAssertEqual(sample.chargePercent, 61)
        XCTAssertEqual(sample.input!.watts, 56.602, accuracy: 0.001)
        XCTAssertEqual(sample.device!.watts + sample.battery!.watts, sample.input!.watts, accuracy: 0.001)
        XCTAssertEqual(sample.kind, .portable)
        XCTAssertEqual(sample.healthPercent!, 80.055, accuracy: 0.01)
    }

    func testUnsignedNegativeCurrentAndStaleChargingTelemetry() {
        let sample = TelemetryParser.parse(root: [
            "BatteryInstalled": true, "ExternalConnected": false, "Voltage": 12000,
            "InstantAmperage": NSNumber(value: UInt64(bitPattern: -1500)),
            "PowerTelemetryData": ["SystemPowerIn": 60000, "BatteryPower": 30000]
        ], model: "MacBookPro18,3")
        XCTAssertEqual(sample.battery?.watts, -18)
        XCTAssertEqual(sample.input?.watts, 0)
        XCTAssertEqual(sample.device?.watts, 18)
        XCTAssertEqual(sample.device?.estimated, true)
    }

    func testThirtyTwoBitSignedCurrent() {
        XCTAssertEqual(TelemetryParser.signed(NSNumber(value: UInt32(bitPattern: -1200))), -1200)
        XCTAssertEqual(TelemetryParser.signed(NSNumber(value: -1200)), -1200)
    }

    func testMissingReadingsNeverBecomeFakeZerosOrPercentCapacities() {
        let sample = TelemetryParser.parse(root: ["BatteryInstalled": true, "MaxCapacity": 100,
                                                "CurrentCapacity": 42, "AdapterDetails": ["Watts": 140]], model: "MacBookPro")
        XCTAssertNil(sample.fullCapacityMAh)
        XCTAssertNil(sample.healthPercent)
        XCTAssertNil(sample.input)
        XCTAssertNil(sample.device)
        XCTAssertNil(sample.battery)
        XCTAssertNil(sample.externalPower)
    }

    func testIdleZeroIsValid() {
        let sample = TelemetryParser.parse(root: ["BatteryInstalled": true, "Voltage": 12000, "Amperage": 0,
                                                "ExternalConnected": true, "PowerTelemetryData": ["BatteryPower": 0]], model: "MacBookPro")
        XCTAssertEqual(sample.battery?.watts, 0)
    }

    func testDesktopUsesBoardSensorWithoutBatteryUI() {
        let sample = TelemetryParser.parse(root: [:], model: "Mac16,10", boardPower: 12.8)
        XCTAssertEqual(sample.kind, .desktop)
        XCTAssertFalse(sample.batteryPresent)
        XCTAssertEqual(sample.device?.watts, 12.8)
        XCTAssertNil(sample.input)
        XCTAssertNil(sample.healthPercent)
    }

    func testUnavailablePortableRemainsPortable() {
        let sample = TelemetryParser.parse(root: [:], model: "MacBookPro18,1")
        XCTAssertEqual(sample.kind, .portable)
        XCTAssertNil(sample.device)
        XCTAssertFalse(sample.notes.isEmpty)
        let modern = TelemetryParser.parse(root: [:], model: "Mac16,1", hasClamshell: true)
        XCTAssertEqual(modern.kind, .portable)
    }

    func testBatterySupplementingCharger() {
        let sample = TelemetryParser.parse(root: ["BatteryInstalled": true, "ExternalConnected": true,
            "Voltage": 12000, "Amperage": -1000, "PowerTelemetryData": ["SystemPowerIn": 30000, "BatteryPower": 15000]], model: "MacBookPro")
        XCTAssertEqual(sample.battery?.watts, -12)
        XCTAssertEqual(sample.device?.watts, 42)
        XCTAssertEqual(sample.status, "Battery assisting")
    }

    func testUnknownTimesAndInvalidMeasurementsAreAbsent() {
        let sample = TelemetryParser.parse(root: ["BatteryInstalled": true, "ExternalConnected": false,
            "AvgTimeToEmpty": 65535, "DesignCapacity": 0, "CycleCount": -1,
            "PowerTelemetryData": ["SystemLoad": Double.nan, "BatteryPower": Double.infinity]], model: "MacBookPro")
        XCTAssertNil(sample.minutesRemaining)
        XCTAssertNil(sample.healthPercent)
        XCTAssertNil(sample.cycles)
        XCTAssertNil(sample.device)
    }

    func testSMCDecoding() {
        let bits = Float(12.5).bitPattern
        let bytes = (0..<4).map { UInt8((bits >> (8 * $0)) & 255) }
        XCTAssertEqual(SMCReader.decode(bytes, type: "flt "), 12.5)
        XCTAssertEqual(SMCReader.decode([0x0c, 0x80], type: "sp78"), 12.5)
        XCTAssertNil(SMCReader.decode([0], type: "flt "))
        XCTAssertNil(SMCReader.decode([0, 0, 0x80, 0x7f], type: "flt "))
        XCTAssertNil(SMCReader.decode(bytes, type: "????"))
    }

    func testSnapshotRoundTripAndStaleness() throws {
        var snapshot = PowerSnapshot.preview
        snapshot.date = Date(timeIntervalSince1970: 1000)
        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(PowerSnapshot.self, from: encoded), snapshot)
        XCTAssertFalse(snapshot.isStale(at: Date(timeIntervalSince1970: 1100)))
        XCTAssertTrue(snapshot.isStale(at: Date(timeIntervalSince1970: 1201)))
    }

    func testZeroChargeTelemetryDoesNotHideBatteryDischarge() {
        let sample = TelemetryParser.parse(root: ["BatteryInstalled": true, "ExternalConnected": false,
            "Voltage": 12000, "Amperage": -1000, "PowerTelemetryData": ["BatteryPower": 0]], model: "MacBookPro")
        XCTAssertEqual(sample.battery?.watts, -12)
        XCTAssertEqual(sample.device?.watts, 12)
    }
}
