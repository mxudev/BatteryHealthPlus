import Foundation
import IOKit

/// A deliberately tiny read-only AppleSMC client. No fan, charging or SMC writes.
public final class SMCReader {
    private var connection: io_connect_t = 0

    public init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }

    public func systemPower() -> Double? { read("PSTR") }

    public func read(_ key: String) -> Double? {
        guard connection != 0, key.utf8.count == 4 else { return nil }
        // AppleSMC's 80-byte user-client ABI. Explicit offsets avoid Swift struct padding.
        var request = [UInt8](repeating: 0, count: 80)
        let code = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        put(code, at: 0, into: &request)
        request[42] = 9 // Get key metadata.
        guard let metadata = call(request) else { return nil }
        let size = uint32(metadata, at: 28)
        guard size > 0, size <= 32 else { return nil }
        let type = uint32(metadata, at: 32)
        put(size, at: 28, into: &request)
        request[42] = 5 // Read key bytes. No write selector is implemented.
        guard let response = call(request) else { return nil }
        let bytes = Array(response[48..<48 + Int(size)])
        let tag = String(bytes: [UInt8((type >> 24) & 255), UInt8((type >> 16) & 255),
                                 UInt8((type >> 8) & 255), UInt8(type & 255)], encoding: .ascii) ?? ""
        return Self.decode(bytes, type: tag)
    }

    private func call(_ request: [UInt8]) -> [UInt8]? {
        var response = [UInt8](repeating: 0, count: 80)
        var length = 80
        let result = request.withUnsafeBytes { input in
            response.withUnsafeMutableBytes { output in
                IOConnectCallStructMethod(connection, 2, input.baseAddress, 80, output.baseAddress, &length)
            }
        }
        guard result == KERN_SUCCESS, length == 80, response[40] == 0 else { return nil }
        return response
    }
    private func put(_ value: UInt32, at offset: Int, into bytes: inout [UInt8]) {
        for index in 0..<4 { bytes[offset + index] = UInt8((value >> (8 * index)) & 255) }
    }
    private func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }
    static func decode(_ bytes: [UInt8], type: String) -> Double? {
        let value: Double
        if type == "flt ", bytes.count == 4 {
            let bits = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[$1]) << (8 * $1) }
            value = Double(Float(bitPattern: bits))
        } else if type == "sp78", bytes.count == 2 {
            value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        } else if type == "fpe2", bytes.count == 2 {
            value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        } else { return nil }
        return value.isFinite ? value : nil
    }
}
