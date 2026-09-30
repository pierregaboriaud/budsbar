import Foundation

/// Resumes the music when the earbuds go back in.
///
/// Taking an earbud out makes the Buds send a Pause to the Mac; putting it back sends nothing, so
/// the player stays paused. This remembers a pause that came with an earbud leaving the ear, and
/// sends Play when one goes back in. A pause from a tap on the earbud, or from the keyboard, is
/// left alone — and so is a player that was not playing in the first place.
public final class PlaybackResume {
    /// How far apart the "out of the ear" report and the Pause command may arrive.
    static let pairing = 5.0
    /// Out for longer than this, coming back is a new listening session: do not start anything.
    static let maxAway = 30 * 60.0

    private let log: (String) -> Void
    private let play: () -> Void
    private let queue = DispatchQueue(label: "budsbar.resume")

    private var enabled = true
    private var address: String?        // "AA:BB:CC:DD:EE:FF", as bluetoothd writes it
    private var wornCount: Int?
    private var removedAt: Date?
    private var pausedAt: Date?
    private var pendingSince: Date?

    /// `play` sends a Play command to the system's current player.
    public init(play: @escaping () -> Void = MediaRemote.play, log: @escaping (String) -> Void) {
        self.play = play
        self.log = log
    }

    public func setEnabled(_ value: Bool) {
        queue.async {
            self.enabled = value
            if !value { self.pendingSince = nil }
        }
    }

    public func setDevice(address: String?) {
        queue.async {
            let colons = address?.replacingOccurrences(of: "-", with: ":")
            guard self.address != colons else { return }
            self.address = colons
            self.wornCount = nil
            self.pendingSince = nil
        }
    }

    /// How many earbuds are in an ear; nil when the Buds are not telling.
    public func setWornCount(_ count: Int?, at now: Date = Date()) {
        queue.async {
            let before = self.wornCount
            self.wornCount = count
            guard let before, let count else { return }
            if count < before {
                self.removedAt = now
                self.pairUp(now)
            } else if count > before, let since = self.pendingSince {
                self.pendingSince = nil
                guard self.enabled, now.timeIntervalSince(since) < PlaybackResume.maxAway else { return }
                self.log("earbud back in: resuming playback")
                // Let the audio route settle; the Buds ignore what arrives in the first instant.
                self.queue.asyncAfter(deadline: .now() + 1) { self.play() }
            }
        }
    }

    /// A line of the bluetoothd log (see `BluetoothLog`).
    public func logLine(_ line: String, at now: Date = Date()) {
        queue.async {
            guard let address = self.address, line.contains("Received AVRCP"),
                  line.uppercased().contains(address) else { return }
            if line.contains("AVRCP Pause") {
                self.pausedAt = now
                self.pairUp(now)
            } else if line.contains("AVRCP Play") {
                // Playing again by the wearer's own doing: nothing left to resume.
                self.pendingSince = nil
            }
        }
    }

    /// An earbud left the ear and the Buds paused the player, in either order, close together.
    private func pairUp(_ now: Date) {
        guard enabled, let removedAt, let pausedAt,
              abs(removedAt.timeIntervalSince(pausedAt)) <= PlaybackResume.pairing else { return }
        if pendingSince == nil { log("earbud out: the Buds paused playback, will resume when it is back in") }
        pendingSince = now
    }

    /// Waits for everything queued so far; for tests.
    func flush() {
        queue.sync {}
    }
}

/// The system's media controls, through the private MediaRemote framework: there is no public
/// API to tell "the current player" to play, and a simulated Play/Pause key would toggle — it
/// could pause music the wearer had already restarted.
public enum MediaRemote {
    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
    private static let playCommand: UInt32 = 0

    private static let sendCommand: SendCommand? = {
        guard let library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let symbol = dlsym(library, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    public static func play() {
        _ = sendCommand?(playCommand, nil)
    }
}
