import Foundation

/// Follows the two things BudsBar needs from the system's Bluetooth daemon and that no public API
/// reports: the call link starting/stopping, and the play/pause commands the earbuds send.
///
///     … HFP Stream State: Stop …
///     … Received AVRCP Pause command from device AA:BB:CC:DD:EE:FF
///
/// It reads `log stream` with a narrow predicate, which an admin account may do without sudo.
public final class BluetoothLog {
    private let onLine: (String) -> Void
    private let lock = NSLock()
    private var task: Process?
    private var stopped = false

    /// `onLine` is called on a background thread, once per matching log line.
    public init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    public func start() {
        Thread.detachNewThread { [weak self] in
            // `log stream` dies across some sleep/wake cycles: keep one running.
            while let self, !self.isStopped {
                self.run()
                Thread.sleep(forTimeInterval: 2)
            }
        }
    }

    /// The `log stream` child would outlive the app otherwise.
    public func stop() {
        lock.lock()
        stopped = true
        task?.terminate()
        lock.unlock()
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func run() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "compact", "--predicate",
                             "process == \"bluetoothd\" AND (eventMessage CONTAINS \"HFP Stream State\""
                                + " OR eventMessage CONTAINS \"Received AVRCP\")"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        lock.lock()
        task = process
        lock.unlock()
        var pending = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                onLine(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...newline)
            }
        }
        process.waitUntilExit()
    }
}
