import Foundation

/// Private framework calls are isolated from both the UI and Mac sampling loop.
/// The app's own executable runs one read and exits; no installed helper is needed.
enum PhoneSampler {
    static func read(executable: URL) -> PhoneSnapshot? {
        let process = Process()
        let pipe = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = executable
        process.arguments = ["--read-iphone"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + 6) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return try? JSONDecoder().decode(PhoneSnapshot.self, from: data)
    }
}
