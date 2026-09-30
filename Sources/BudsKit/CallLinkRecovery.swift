import CoreAudio
import Foundation

/// Brings the sound back after the earbuds are taken out and put back in.
///
/// When an app holds the Buds' microphone, macOS runs them in call mode (HFP over an SCO link,
/// 16 kHz mono). Out of the ears for a while, the Buds drop that link — bluetoothd logs
/// "HFP Stream State: Stop" — and macOS never asks for it again, while CoreAudio keeps the device
/// "running": total silence until someone reconnects Bluetooth by hand. The device never leaves
/// the device list, so tools that react to devices appearing cannot see it.
///
/// Parking the default input on another microphone until the Buds leave call mode, then giving it
/// back, makes macOS set the link up again. This class detects the state and does that.
public final class CallLinkRecovery {
    public struct Timing {
        public var confirmDelay = 3.0   // after a Stop, before calling it a wedge
        public var holdMin = 3.0        // on the other microphone: 1 s never works, 3 s always did
        public var holdMax = 8.0
        public var holdProof = 5.0      // a restarted link that lasts this long is a recovery
        public var retry = 5.0          // when a flip changed nothing at all
        public var fastWindow = 600.0   // wear state unknown: a flip every ~10 s for this long,
        public var slowRetry = 30.0     // then this long after each drop
        public init() {}
    }

    private let timing: Timing
    private let log: (String) -> Void
    private let queue = DispatchQueue(label: "budsbar.recovery")

    // Everything below is only touched on `queue`.
    private var address: String?            // "AA-BB-CC-DD-EE-FF"
    private var worn: Bool?                 // nil: the Buds are not telling
    private var enabled = true
    private var generation = 0              // bumped by every event: older scheduled work is stale
    private var episodeSince: Date?
    private var attempts = 0
    private var waitingForWear = false

    /// Called on an arbitrary queue each time a recovery completes.
    public var onRecovered: ((Int) -> Void)?

    public init(timing: Timing = Timing(), log: @escaping (String) -> Void) {
        self.timing = timing
        self.log = log
    }

    // MARK: inputs

    /// A line of the bluetoothd log (see `BluetoothLog`).
    public func logLine(_ line: String) {
        queue.async { self.handle(line) }
    }

    public func setEnabled(_ value: Bool) {
        queue.async {
            self.enabled = value
            self.generation += 1
            if value { self.schedule(after: self.timing.confirmDelay) { self.check() } }
        }
    }

    /// The Buds this Mac is talking to, or nil when there are none. A wedge that predates this
    /// call has no Stop event to announce it, hence the check.
    public func setDevice(address: String?) {
        queue.async {
            guard self.address != address else { return }
            self.address = address
            self.worn = nil
            self.generation += 1
            if address != nil { self.schedule(after: self.timing.confirmDelay) { self.check() } }
        }
    }

    /// Wear state from the Buds themselves; nil when the control link is down.
    public func setWorn(_ value: Bool?) {
        queue.async {
            guard self.worn != value else { return }
            self.worn = value
            // Back in the ears (or no longer telling): this is the moment to look.
            if value != false {
                self.generation += 1
                self.schedule(after: 0.5) { self.check() }
            }
        }
    }

    // MARK: state machine

    private func schedule(after delay: Double, _ work: @escaping () -> Void) {
        let expected = generation
        queue.asyncAfter(deadline: .now() + delay) { if expected == self.generation { work() } }
    }

    private func endEpisode(_ why: String) {
        if episodeSince != nil {
            log("recovered after \(attempts) flip(s): \(why)")
            if attempts > 0 { onRecovered?(attempts) }
        }
        episodeSince = nil
        attempts = 0
        waitingForWear = false
    }

    private func handle(_ line: String) {
        guard line.contains("HFP Stream State:") else { return }
        generation += 1
        if line.contains("State: Start") {
            schedule(after: timing.holdProof) { self.endEpisode("call link holding") }
        } else if line.contains("State: Stop") {
            // Wear state unknown and the link keeps dropping: the Buds are lying on a desk.
            let out = episodeSince.map { Date().timeIntervalSince($0) } ?? 0
            schedule(after: out < timing.fastWindow ? timing.confirmDelay : timing.slowRetry) { self.check() }
        }
    }

    private func check() {
        guard enabled, let address else { return }
        guard let state = wedged(address) else { endEpisode("no longer in call mode"); return }
        if episodeSince == nil {
            episodeSince = Date()
            log("wedged: call link stopped, \(state.reason)")
        }
        if worn == false {
            // Out of the ears the Buds accept the link and drop it a second later, every time.
            // Wait for them to say they are worn again: setWorn() comes back here.
            if !waitingForWear { log("earbuds are out: waiting for them to be worn") }
            waitingForWear = true
            return
        }
        waitingForWear = false
        guard let parking = otherMicrophone(address) else { log("no other microphone to flip to"); return }
        attempts += 1
        let held = flip(address, via: parking, back: state.input)
        if attempts <= 3 || attempts % 20 == 0 {
            log("flip #\(attempts), held the other microphone \(String(format: "%.1f", held)) s")
        }
        // A Start or Stop event supersedes this; it only fires when the flip changed nothing.
        generation += 1
        schedule(after: timing.retry) { self.check() }
    }

    // MARK: CoreAudio + Bluetooth state

    private func isBuds(_ id: AudioDeviceID, _ address: String) -> Bool {
        AudioDevices.string(id, kAudioDevicePropertyDeviceUID).uppercased().contains(address)
    }

    /// Call mode with an app still recording from the Buds (both default devices), but no SCO
    /// link to carry it. CoreAudio alone cannot tell this from a healthy call.
    private func wedged(_ address: String) -> (input: AudioDeviceID, reason: String)? {
        guard let input = AudioDevices.current(.input), let output = AudioDevices.current(.output),
              isBuds(input.id, address), isBuds(output.id, address) else { return nil }
        let rate = AudioDevices.sampleRate(output.id)
        guard rate > 0, rate < 32000, AudioDevices.isRunning(input.id) else { return nil }
        guard scoLinkUp(address) == false else { return nil }
        return (input.id, "output at \(Int(rate)) Hz, microphone still in use, no SCO link")
    }

    /// From the "Services: … < HFP AVRCP A2DP ACL SCO >" line of system_profiler (~0.1 s): the
    /// only public place that says whether the SCO link exists. nil when it cannot be read.
    private func scoLinkUp(_ address: String) -> Bool? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        task.waitUntilExit()
        let lines = text.components(separatedBy: "\n")
        let wanted = "Address: " + address.replacingOccurrences(of: "-", with: ":")
        guard let at = lines.firstIndex(where: { $0.uppercased().contains(wanted.uppercased()) }),
              let services = lines[at...].prefix(6).first(where: { $0.contains("Services:") }) else { return nil }
        return services.contains(" SCO")
    }

    /// The microphone to park on: the built-in one, else any input that is not the Buds.
    private func otherMicrophone(_ address: String) -> AudioDeviceID? {
        let inputs = AudioDevices.list(.input).filter { !$0.uid.uppercased().contains(address) }
        return (inputs.first { $0.isBuiltIn } ?? inputs.first)?.id
    }

    private func flip(_ address: String, via parking: AudioDeviceID, back input: AudioDeviceID) -> Double {
        let started = Date()
        guard AudioDevices.select(parking, .input) else { return 0 }
        while Date().timeIntervalSince(started) < timing.holdMax {
            Thread.sleep(forTimeInterval: 0.25)
            let held = Date().timeIntervalSince(started)
            let output = AudioDevices.allIDs().first {
                isBuds($0, address) && AudioDevices.hasStreams($0, .output)
            }
            if held >= timing.holdMin, let output, AudioDevices.sampleRate(output) >= 32000 { break }
        }
        let held = Date().timeIntervalSince(started)
        // The device id can change across the mode switch: look the Buds microphone up again.
        let buds = AudioDevices.allIDs().first { isBuds($0, address) && AudioDevices.hasStreams($0, .input) } ?? input
        if !AudioDevices.select(buds, .input) { log("could not give the microphone back to the earbuds") }
        return held
    }
}
