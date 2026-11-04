import Foundation
import IOKit
import IOKit.ps

public enum PowerReader {
    public static func read(includeSMC: Bool = true) -> PowerSnapshot {
        #if !arch(arm64)
        var unsupported = PowerSnapshot()
        unsupported.notes = ["BatteryHealth++ supports Apple Silicon Macs only."]
        return unsupported
        #else
        let root = properties(className: "AppleSmartBattery")
        let pack = properties(className: "AppleSmartBatteryPack")
        var source: [String: Any] = [:]
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for item in list {
                if let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                   description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                    source = description; break
                }
            }
        }
        let telemetry = root["PowerTelemetryData"] as? [String: Any]
        let board = includeSMC && telemetry?["SystemLoad"] == nil ? SMCReader().systemPower() : nil
        let hasClamshell = properties(className: "IOPMrootDomain")["AppleClamshellState"] != nil
        return TelemetryParser.parse(root: root, pack: pack, publicSource: source, model: hardwareModel,
                                     boardPower: board, hasClamshell: hasClamshell)
        #endif
    }

    private static func properties(className: String) -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var result: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &result, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return [:] }
        return result?.takeRetainedValue() as? [String: Any] ?? [:]
    }

    public static var hardwareModel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Apple Silicon Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "Apple Silicon Mac" }
        let identifier = String(cString: bytes)
        // Recent hardware uses generic Mac identifiers; the chassis type comes from the registry.
        return identifier
    }
}
