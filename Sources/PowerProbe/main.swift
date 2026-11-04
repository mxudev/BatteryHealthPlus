import Foundation
import PowerCore

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
let snapshot = PowerReader.read()
print(String(data: try encoder.encode(snapshot), encoding: .utf8)!)
if CommandLine.arguments.contains("--smc") {
    let smc = SMCReader()
    for key in ["PSTR", "PDTR", "PPBR"] {
        print("\(key): \(smc.read(key).map { String(format: "%.3f W", $0) } ?? "unavailable")")
    }
}
