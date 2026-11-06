import XCTest
@testable import PowerCore

final class PhoneTests: XCTestCase {
    private func response(_ root: [String: Any]) -> [String: Any] {
        ["Status": "Success", "Diagnostics": ["IORegistry": root]]
    }

    func testMeasuredPhoneSplitAndCharge() {
        let phone = PhoneSnapshot.parse(response([
            "CurrentCapacity": 59, "MaxCapacity": 100,
            "PowerTelemetryData": ["SystemPowerIn": 11130, "SystemLoad": 3137, "BatteryPower": 7993]
        ]))
        XCTAssertEqual(phone.input?.watts, 11.130)
        XCTAssertEqual(phone.device?.watts, 3.137)
        XCTAssertEqual(phone.battery?.watts, 7.993)
        XCTAssertEqual(phone.chargePercent, 59)
        XCTAssertNil(phone.message)
    }

    func testNegotiatedLimitIsNeverShownAsDraw() {
        let phone = PhoneSnapshot.parse(response(["AdapterDetails": ["Watts": 15, "Current": 3000, "AdapterVoltage": 5000]]))
        XCTAssertNil(phone.input)
        XCTAssertNil(phone.device)
        XCTAssertNil(phone.battery)
        XCTAssertNotNil(phone.message)
    }

    func testInvalidPartialAndZeroReadings() {
        let phone = PhoneSnapshot.parse(response([
            "CurrentCapacity": 101, "MaxCapacity": 100,
            "PowerTelemetryData": ["SystemPowerIn": Double.nan, "SystemLoad": 0, "BatteryPower": Double.infinity]
        ]))
        XCTAssertNil(phone.input)
        XCTAssertEqual(phone.device?.watts, 0)
        XCTAssertNil(phone.battery)
        XCTAssertNil(phone.chargePercent)
        XCTAssertNil(phone.message)
        XCTAssertNil(PhoneSnapshot.parse(response(["PowerTelemetryData": ["SystemPowerIn": -1, "SystemLoad": 201000]])).input)
    }

    func testSignedBatteryPowerAndUnavailableReply() {
        let phone = PhoneSnapshot.parse(response(["PowerTelemetryData": ["BatteryPower": NSNumber(value: UInt64(bitPattern: -1200))]]))
        XCTAssertEqual(phone.battery?.watts, -1.2)
        XCTAssertNotNil(PhoneSnapshot.parse(["Status": "NotAllowed"]).message)
        XCTAssertNotNil(PhoneSnapshot.parse([:]).message)
    }

    func testPhoneDoesNotChangeMacPowerAccounting() throws {
        var mac = PowerSnapshot.preview
        let point = PowerPoint(mac)
        mac.phone = PhoneSnapshot.parse(response(["PowerTelemetryData": ["SystemPowerIn": 15000]]))
        XCTAssertEqual(PowerPoint(mac).input, point.input)
        XCTAssertEqual(PowerPoint(mac).device, point.device)
        XCTAssertEqual(PowerPoint(mac).battery, point.battery)
        XCTAssertEqual(mac.input?.watts, 48.2)
        let encoded = try JSONEncoder().encode(mac)
        XCTAssertEqual(try JSONDecoder().decode(PowerSnapshot.self, from: encoded), mac)
    }
}
