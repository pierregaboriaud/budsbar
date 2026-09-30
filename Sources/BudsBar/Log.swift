import Foundation

/// A small text log in ~/Library/Logs, for "why did the sound not come back" questions.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/BudsBar.log")
    private static let queue = DispatchQueue(label: "budsbar.log")
    private static let maxBytes = 512 * 1024
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// `defaults write io.github.pierregaboriaud.BudsBar debug -bool YES` logs every frame.
    static let debug = UserDefaults.standard.bool(forKey: "debug")

    static func write(_ message: String) {
        queue.async {
            let line = "\(stamp.string(from: Date())) \(message)\n"
            let manager = FileManager.default
            if let size = try? manager.attributesOfItem(atPath: url.path)[.size] as? Int, size > maxBytes {
                try? manager.removeItem(at: url)
            }
            if !manager.fileExists(atPath: url.path) {
                manager.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }
}
