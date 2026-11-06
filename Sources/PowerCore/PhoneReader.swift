import Foundation
import Darwin

/// Read-only, already-trusted USB devices only. Run in a bounded child process:
/// private MobileDevice calls can block when a phone disconnects or locks.
public enum PhoneReader {
    public static func read() -> PhoneSnapshot? {
        guard let api = MobileDeviceAPI() else { return nil }
        guard let list = api.devices()?.takeRetainedValue() else { return nil }
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            guard api.interface(device) == 1, api.connect(device) == 0 else { continue }
            defer { _ = api.disconnect(device) }
            let product = api.copyValue(device, nil, "ProductType" as CFString)?.takeRetainedValue() as? String
            guard product?.hasPrefix("iPhone") == true else { continue }
            guard api.paired(device) != 0, api.validate(device) == 0, api.start(device) == 0 else {
                return PhoneSnapshot(message: "Unlock iPhone and trust this Mac")
            }
            defer { _ = api.stop(device) }
            var connection: UnsafeMutableRawPointer?
            guard api.service(device, "com.apple.mobile.diagnostics_relay" as CFString, nil, &connection) == 0,
                  let connection else { return PhoneSnapshot(message: "Unlock iPhone to read power") }
            defer { api.invalidate(connection) }
            let request = ["Request": "IORegistry", "EntryClass": "IOPMPowerSource"] as CFDictionary
            _ = api.send(connection, request, CFPropertyListFormat.xmlFormat_v1_0.rawValue)
            var response: Unmanaged<CFPropertyList>?
            var format: CFIndex = 0
            _ = api.receive(connection, &response, &format)
            guard let response else { return PhoneSnapshot(message: "Power readings unavailable") }
            return PhoneSnapshot.parse(response.takeRetainedValue() as? [String: Any] ?? [:])
        }
        return nil
    }
}

private final class MobileDeviceAPI {
    typealias DeviceCall = @convention(c) (UnsafeMutableRawPointer) -> Int32
    let handle: UnsafeMutableRawPointer
    let devices: @convention(c) () -> Unmanaged<CFArray>?
    let interface: DeviceCall
    let connect: DeviceCall
    let disconnect: DeviceCall
    let paired: DeviceCall
    let validate: DeviceCall
    let start: DeviceCall
    let stop: DeviceCall
    let copyValue: @convention(c) (UnsafeMutableRawPointer, CFString?, CFString) -> Unmanaged<CFTypeRef>?
    let service: @convention(c) (UnsafeMutableRawPointer, CFString, CFDictionary?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    let invalidate: @convention(c) (UnsafeMutableRawPointer) -> Void
    let send: @convention(c) (UnsafeMutableRawPointer, CFPropertyList, CFIndex) -> UInt64
    let receive: @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Unmanaged<CFPropertyList>?>, UnsafeMutablePointer<CFIndex>) -> UInt64

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_LAZY | RTLD_LOCAL) else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        guard let devices = symbol("AMDCreateDeviceList", as: type(of: self.devices)),
              let interface = symbol("AMDeviceGetInterfaceType", as: DeviceCall.self),
              let connect = symbol("AMDeviceConnect", as: DeviceCall.self),
              let disconnect = symbol("AMDeviceDisconnect", as: DeviceCall.self),
              let paired = symbol("AMDeviceIsPaired", as: DeviceCall.self),
              let validate = symbol("AMDeviceValidatePairing", as: DeviceCall.self),
              let start = symbol("AMDeviceStartSession", as: DeviceCall.self),
              let stop = symbol("AMDeviceStopSession", as: DeviceCall.self),
              let copyValue = symbol("AMDeviceCopyValue", as: type(of: self.copyValue)),
              let service = symbol("AMDeviceSecureStartService", as: type(of: self.service)),
              let invalidate = symbol("AMDServiceConnectionInvalidate", as: type(of: self.invalidate)),
              let send = symbol("AMDServiceConnectionSendMessage", as: type(of: self.send)),
              let receive = symbol("AMDServiceConnectionReceiveMessage", as: type(of: self.receive)) else {
            dlclose(handle); return nil
        }
        self.handle = handle; self.devices = devices; self.interface = interface
        self.connect = connect; self.disconnect = disconnect; self.paired = paired
        self.validate = validate; self.start = start; self.stop = stop
        self.copyValue = copyValue; self.service = service; self.invalidate = invalidate
        self.send = send; self.receive = receive
    }
    deinit { dlclose(handle) }
}
