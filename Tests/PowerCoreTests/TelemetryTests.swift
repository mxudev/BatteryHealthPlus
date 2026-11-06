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

    func testCoherentChargingTelemetryWinsOverCachedDischargeCurrent() {
        let sample = TelemetryParser.parse(root: [
            "BatteryInstalled": true, "ExternalConnected": true, "IsCharging": false,
            "Voltage": 11350, "InstantAmperage": -1920,
            "PowerTelemetryData": ["SystemPowerIn": 56000, "SystemLoad": 21600, "BatteryPower": 34400]
        ], model: "MacBookPro18,1")
        XCTAssertEqual(sample.battery?.watts, 34.4)
        XCTAssertEqual(sample.status, "Charging")
        XCTAssertNil(sample.currentAmps, "Do not display stale negative current beside charging power")
        XCTAssertEqual(sample.input?.watts, 56)
    }

    func testChargingFlagDoesNotDisplayOldDischargeArrow() {
        let sample = TelemetryParser.parse(root: [
            "BatteryInstalled": true, "ExternalConnected": true, "IsCharging": true,
            "Voltage": 11350, "InstantAmperage": -1920,
            "PowerTelemetryData": ["SystemPowerIn": 0, "SystemLoad": 21600, "BatteryPower": -21600]
        ], model: "MacBookPro18,1")
        XCTAssertEqual(sample.status, "Charging")
        XCTAssertNil(sample.battery)
        XCTAssertNil(sample.input)
        XCTAssertNil(sample.currentAmps)
        XCTAssertTrue(sample.powerFlowSettling)
    }

    func testUnplugDoesNotRetainChargingFlagOrPositiveElectricalFallback() {
        let sample = TelemetryParser.parse(root: [
            "BatteryInstalled": true, "ExternalConnected": false, "IsCharging": true,
            "Voltage": 12000, "InstantAmperage": 2000,
            "PowerTelemetryData": ["BatteryPower": 24000]
        ], model: "MacBookPro18,1")
        XCTAssertEqual(sample.charging, false)
        XCTAssertNil(sample.battery)
        XCTAssertEqual(sample.input?.watts, 0)
        XCTAssertEqual(sample.status, "On battery")
    }

    func testPlugInWaitsForSensorUpdateNotAppPollsAndRecoversImmediately() {
        var filter = PowerTransitionFilter()
        var sample = dischargeSample()
        _ = filter.process(sample)
        sample.externalPower = true
        sample.date += 1
        let first = filter.process(sample)
        XCTAssertEqual(first.status, "Power updating")
        XCTAssertNil(first.input)
        XCTAssertNil(first.battery)
        XCTAssertNil(first.currentAmps)
        XCTAssertEqual(first.device?.watts, 21.6)
        XCTAssertNil(PowerPoint(first).input, "Do not record a fabricated zero in history")
        sample.date += 60
        XCTAssertTrue(filter.process(sample).powerFlowSettling, "Polling a cached value doesn't make it fresh")
        // Telemetry catches up before the slower current and driver timestamp.
        sample.input = .init(56, source: "test")
        sample.battery = .init(34.4, source: "test")
        sample.charging = true
        sample.date += 1
        let recovered = filter.process(sample)
        XCTAssertFalse(recovered.powerFlowSettling)
        XCTAssertEqual(recovered.battery?.watts, 34.4)
        XCTAssertEqual(recovered.status, "Charging")
    }

    func testFreshDischargePreservesGenuineBatteryAssistance() {
        var filter = PowerTransitionFilter()
        var sample = dischargeSample()
        _ = filter.process(sample)
        sample.externalPower = true
        sample.date += 1
        sample.input = .init(10, source: "test")
        XCTAssertTrue(filter.process(sample).powerFlowSettling)
        sample.batterySampleDate! += 2
        sample.date += 2
        let fresh = filter.process(sample)
        XCTAssertFalse(fresh.powerFlowSettling)
        XCTAssertEqual(fresh.status, "Battery assisting")
        XCTAssertEqual(fresh.input?.watts, 10)
    }

    func testTransitionAtLaunchIsBoundedWhenChargerDeliversNoPower() {
        var filter = PowerTransitionFilter()
        var sample = dischargeSample()
        sample.externalPower = true
        XCTAssertTrue(filter.process(sample).powerFlowSettling)
        sample.date += 90
        XCTAssertFalse(filter.process(sample).powerFlowSettling)
        sample.date += 1
        XCTAssertFalse(filter.process(sample).powerFlowSettling, "Do not restart a timed-out transition")
    }

    func testLegacyTransitionAndQuickUnplug() {
        var filter = PowerTransitionFilter()
        var sample = dischargeSample()
        sample.batterySampleDate = nil
        _ = filter.process(sample)
        sample.externalPower = true
        sample.date += 1
        XCTAssertTrue(filter.process(sample).powerFlowSettling)
        sample.currentAmps = -1.5
        sample.date += 1
        XCTAssertFalse(filter.process(sample).powerFlowSettling)
        sample.externalPower = false
        sample.date += 1
        XCTAssertEqual(filter.process(sample).status, "On battery")
        XCTAssertFalse(filter.process(sample).powerFlowSettling)
    }

    func testStablePausedChargingIsNotHidden() {
        var filter = PowerTransitionFilter()
        var sample = PowerSnapshot.preview
        sample.charging = false
        sample.battery = .init(0, source: "test")
        let result = filter.process(sample)
        XCTAssertEqual(result.status, "Charging paused")
        XCTAssertFalse(result.powerFlowSettling)
        XCTAssertEqual(result.battery?.watts, 0)
    }

    func testDirectPowerOverridesFrozenRegistrySplitAndChargingState() {
        let sample = TelemetryParser.parse(root: [
            "BatteryInstalled": true, "ExternalConnected": false, "IsCharging": false,
            "Voltage": 12000, "InstantAmperage": -1800,
            "PowerTelemetryData": ["SystemPowerIn": 0, "SystemLoad": 21600, "BatteryPower": -21600]
        ], model: "MacBookPro18,1", boardPower: 14, inputPower: 56)
        XCTAssertEqual(sample.input?.watts, 56)
        XCTAssertEqual(sample.input?.source, "AppleSMC.PDTR")
        XCTAssertEqual(sample.device?.watts, 14)
        XCTAssertEqual(sample.device?.source, "AppleSMC.PSTR")
        XCTAssertEqual(sample.battery?.watts, 42)
        XCTAssertEqual(sample.battery?.estimated, true)
        XCTAssertEqual(sample.externalPower, true)
        XCTAssertEqual(sample.status, "Charging")
        XCTAssertNil(sample.currentAmps)
        XCTAssertTrue(sample.hasDirectPowerFlow)
        XCTAssertFalse(sample.powerFlowSettling)
    }

    func testDirectPowerUnplugOverridesCachedChargingMeasurements() {
        let sample = TelemetryParser.parse(root: [
            "BatteryInstalled": true, "ExternalConnected": false, "IsCharging": true,
            "Voltage": 12000, "InstantAmperage": 3000,
            "PowerTelemetryData": ["SystemPowerIn": 56000, "SystemLoad": 20000, "BatteryPower": 36000]
        ], model: "MacBookPro", boardPower: 12, inputPower: 0)
        XCTAssertEqual(sample.input?.watts, 0)
        XCTAssertEqual(sample.battery?.watts, -12)
        XCTAssertEqual(sample.charging, false)
        XCTAssertEqual(sample.status, "On battery")
        XCTAssertNil(sample.currentAmps)
    }

    func testDirectAssistanceAndIdleDoNotWaitForRegistryTimestamp() {
        for (input, expectedBattery, expectedStatus) in [(10.0, -10.0, "Battery assisting"), (20.2, 0.0, "Charging paused")] {
            var filter = PowerTransitionFilter()
            _ = filter.process(dischargeSample())
            let sample = TelemetryParser.parse(root: [
                "BatteryInstalled": true, "ExternalConnected": true, "IsCharging": true,
                "UserVisiblePathUpdated": 1000, "Voltage": 12000, "InstantAmperage": 3000
            ], model: "MacBookPro", boardPower: 20, inputPower: input, date: Date(timeIntervalSince1970: 1001))
            let result = filter.process(sample)
            XCTAssertEqual(result.battery?.watts, expectedBattery)
            XCTAssertEqual(result.status, expectedStatus)
            XCTAssertFalse(result.powerFlowSettling)
            XCTAssertNil(result.currentAmps)
        }
    }

    func testMissingOrInvalidSMCPreservesRegistryFallback() {
        let root: [String: Any] = ["BatteryInstalled": true, "ExternalConnected": true, "IsCharging": true,
            "PowerTelemetryData": ["SystemPowerIn": 56000, "SystemLoad": 20000, "BatteryPower": 36000]]
        for invalid: Double? in [nil, .nan, .infinity, -1, 2001] {
            let sample = TelemetryParser.parse(root: root, model: "MacBookPro", boardPower: invalid, inputPower: invalid)
            XCTAssertEqual(sample.input?.watts, 56)
            XCTAssertEqual(sample.device?.watts, 20)
            XCTAssertEqual(sample.battery?.watts, 36)
            XCTAssertEqual(sample.battery?.estimated, false)
            XCTAssertFalse(sample.hasDirectPowerFlow)
        }
    }

    func testPartialSMCDoesNotCalculateBatteryFromMixedSources() {
        let root: [String: Any] = ["BatteryInstalled": true, "ExternalConnected": true,
            "PowerTelemetryData": ["SystemPowerIn": 56000, "SystemLoad": 20000, "BatteryPower": 36000]]
        let deviceOnly = TelemetryParser.parse(root: root, model: "MacBookPro", boardPower: 12)
        XCTAssertEqual(deviceOnly.device?.watts, 12)
        XCTAssertEqual(deviceOnly.battery?.watts, 36)
        XCTAssertFalse(deviceOnly.hasDirectPowerFlow)
        let inputOnly = TelemetryParser.parse(root: root, model: "MacBookPro", inputPower: 50)
        XCTAssertEqual(inputOnly.input?.watts, 50)
        XCTAssertEqual(inputOnly.battery?.watts, 36)
        XCTAssertFalse(inputOnly.hasDirectPowerFlow)
    }

    func testDesktopPrefersDirectSystemPowerWithoutInventingBattery() {
        let sample = TelemetryParser.parse(root: ["PowerTelemetryData": ["SystemLoad": 30000]],
                                          model: "Mac16,10", boardPower: 18, inputPower: 30)
        XCTAssertEqual(sample.device?.watts, 18)
        XCTAssertNil(sample.input)
        XCTAssertNil(sample.battery)
        XCTAssertFalse(sample.hasDirectPowerFlow)
        XCTAssertEqual(sample.status, "Desktop power")
    }

    func testDirectZeroIsValidAndCancelsPendingTransition() {
        var filter = PowerTransitionFilter()
        var old = dischargeSample()
        _ = filter.process(old)
        old.externalPower = true
        XCTAssertTrue(filter.process(old).powerFlowSettling)
        let sample = TelemetryParser.parse(root: ["BatteryInstalled": true, "ExternalConnected": true],
                                          model: "MacBookPro", boardPower: 0, inputPower: 0)
        let result = filter.process(sample)
        XCTAssertEqual(result.input?.watts, 0)
        XCTAssertEqual(result.device?.watts, 0)
        XCTAssertEqual(result.battery?.watts, 0)
        XCTAssertFalse(result.powerFlowSettling)
    }

    private func dischargeSample() -> PowerSnapshot {
        var sample = PowerSnapshot.preview
        sample.date = Date(timeIntervalSince1970: 1000)
        sample.batterySampleDate = sample.date
        sample.externalPower = false
        sample.charging = false
        sample.voltage = 11.35
        sample.currentAmps = -1.92
        sample.input = .init(0, source: "test")
        sample.device = .init(21.6, source: "test")
        sample.battery = .init(-21.6, source: "test")
        return sample
    }
}
