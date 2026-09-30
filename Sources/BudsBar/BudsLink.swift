import BudsKit
import CoreBluetooth
import Foundation
import IOBluetooth

/// The control channel to the earbuds: an RFCOMM (serial port) link next to the audio links,
/// over which the Buds report battery, placement and noise-control mode. Main thread only.
final class BudsLink: NSObject, IOBluetoothRFCOMMChannelDelegate {
    struct Peer: Equatable {
        let name: String
        let address: String   // "AA-BB-CC-DD-EE-FF", as CoreAudio spells it
    }

    /// The Serial Port records Galaxy Buds publish their control channel under, newest first.
    private static let serviceUUIDs = [
        "2e73a4ad-332d-41fc-90e2-16bef06523f2",
        "00001101-0000-1000-8000-00805f9b34fb",
        "f8620674-a1ed-41ab-a8b9-de9ad655729d",
    ]
    private static let openTimeout = 6.0
    private static let sdpInterval = 10.0
    private static let stuckAfter = 3
    private static let stuckRetry = 60.0

    var onChange: (() -> Void)?
    private(set) var status = BudsStatus()
    /// The Buds whose audio is connected to this Mac right now.
    private(set) var peer: Peer?
    private(set) var isLinked = false
    var bluetoothDenied: Bool { CBCentralManager.authorization == .denied }

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var reader = FrameReader()
    private var openingSince: Date?
    private var sdpAskedAt: Date?
    private var failedOpens = 0
    private var nextOpenAt = Date.distantPast

    /// The channel keeps refusing to open. Seen when another app left its own connection to the
    /// earbuds dangling inside macOS ("DLCI exists" in the bluetoothd log): only a Bluetooth
    /// disconnect/reconnect of the earbuds clears it.
    var isStuck: Bool { !isLinked && failedOpens >= BudsLink.stuckAfter }
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    /// Closes the control channel; an app that dies with it open can leave it dangling in macOS.
    func stop() {
        timer?.invalidate()
        close()
    }

    func setNoiseControl(_ mode: NoiseControl) {
        guard send(Command.setNoiseControl(mode)) else { return }
        // The Buds confirm with a noise-controls update only when the change came from a touch.
        status.noiseControl = mode
        status.otherNoiseMode = nil
        onChange?()
    }

    // MARK: connection

    private func tick() {
        let found = connectedBuds()
        if found?.peer != peer {
            close()
            peer = found?.peer
            device = found?.device
            status = BudsStatus()
            // The case only reports while an earbud sits in it: start from what it last said.
            status.caseLevel = peer.flatMap { UserDefaults.standard.object(forKey: "case." + $0.address) as? Int }
            failedOpens = 0
            nextOpenAt = .distantPast
            Log.write(peer.map { "earbuds connected: \($0.name)" } ?? "earbuds gone")
            onChange?()
        }
        guard let device else { return }
        if let channel, channel.isOpen() {
            // The open-complete callback does not fire on every macOS build.
            if !isLinked { linked() }
            return
        }
        if let since = openingSince {
            guard Date().timeIntervalSince(since) > BudsLink.openTimeout else { return }
            close()
            failedOpens += 1
            if failedOpens == BudsLink.stuckAfter {
                Log.write("control channel still not opening: reconnect the earbuds in Bluetooth once")
                onChange?()
            }
            if isStuck { nextOpenAt = Date().addingTimeInterval(BudsLink.stuckRetry) }
        }
        guard Date() >= nextOpenAt else { return }
        guard let id = channelID(of: device) else {
            // Service records arrive asynchronously; the next ticks will find them.
            if sdpAskedAt.map({ Date().timeIntervalSince($0) > BudsLink.sdpInterval }) ?? true {
                sdpAskedAt = Date()
                Log.write("no control channel among the earbuds' services (\(services(of: device))), asking again")
                device.performSDPQuery(nil)
            }
            return
        }
        var opened: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&opened, withChannelID: id, delegate: self)
        guard result == kIOReturnSuccess, let opened else {
            Log.write("cannot open control channel \(id): \(String(format: "0x%08x", UInt32(bitPattern: result)))")
            return
        }
        Log.write("opening control channel \(id)")
        channel = opened
        openingSince = Date()
    }

    /// Paired earbuds that macOS is using as an audio device. Going through CoreAudio rather
    /// than IOBluetooth's isConnected() keeps BudsBar from ever pulling the Buds off a phone.
    private func connectedBuds() -> (peer: Peer, device: IOBluetoothDevice)? {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        for device in paired {
            guard let name = device.name, name.lowercased().contains("buds"),
                  let address = device.addressString?.uppercased(),
                  AudioDevices.isPresent(bluetoothAddress: address) else { continue }
            return (Peer(name: name, address: address), device)
        }
        return nil
    }

    private func channelID(of device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        for uuid in BudsLink.serviceUUIDs {
            guard let bytes = UUID(uuidString: uuid).map({ withUnsafeBytes(of: $0.uuid) { Array($0) } }),
                  let record = device.getServiceRecord(for: IOBluetoothSDPUUID(bytes: bytes, length: bytes.count))
            else { continue }
            var id: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&id) == kIOReturnSuccess { return id }
        }
        return nil
    }

    /// What the earbuds advertise, for the log: the one clue when no known record matches.
    private func services(of device: IOBluetoothDevice) -> String {
        guard let records = device.services as? [IOBluetoothSDPServiceRecord], !records.isEmpty else { return "none" }
        return records.map { record in
            var id: BluetoothRFCOMMChannelID = 0
            let name = record.getServiceName() ?? "unnamed"
            return record.getRFCOMMChannelID(&id) == kIOReturnSuccess ? "\(name) rfcomm \(id)" : name
        }.joined(separator: ", ")
    }

    private func linked() {
        isLinked = true
        openingSince = nil
        failedOpens = 0
        reader = FrameReader()
        Log.write("control channel open")
        send(Command.hello)
        onChange?()
    }

    private func close() {
        if let channel {
            channel.setDelegate(nil)
            channel.close()
        }
        channel = nil
        openingSince = nil
        if isLinked {
            isLinked = false
            // Battery levels stay as last seen; where the earbuds are is no longer known.
            status.placementLeft = .unknown
            status.placementRight = .unknown
        }
    }

    @discardableResult
    private func send(_ frame: Frame) -> Bool {
        guard isLinked, let channel else { return false }
        var bytes = frame.encoded()
        if Log.debug { Log.write("→ " + hex(bytes)) }
        return channel.writeSync(&bytes, length: UInt16(bytes.count)) == kIOReturnSuccess
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard rfcommChannel === channel else { return }
        // The status lies on some builds: believe isOpen() as well.
        if error == kIOReturnSuccess || rfcommChannel.isOpen() {
            if !isLinked { linked() }
        } else {
            Log.write("control channel refused: \(String(format: "0x%08x", UInt32(bitPattern: error)))")
            close()
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                           data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard rfcommChannel === channel else { return }
        let bytes = [UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        if Log.debug { Log.write("← " + hex(bytes)) }
        var changed = false
        for frame in reader.feed(bytes) {
            let before = status
            if status.apply(frame), status != before { changed = true }
        }
        if changed {
            if let peer, let level = status.caseLevel {
                UserDefaults.standard.set(level, forKey: "case." + peer.address)
            }
            Log.write("status: \(summary)")
            onChange?()
        }
    }

    private var summary: String {
        func level(_ value: Int?) -> String { value.map(String.init) ?? "–" }
        return "L\(level(status.left)) \(status.placementLeft) · R\(level(status.right)) \(status.placementRight)"
            + " · case \(level(status.caseLevel)) · noise \(status.noiseControl.map { "\($0)" } ?? "?")"
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard rfcommChannel === channel else { return }
        Log.write("control channel closed")
        close()
        onChange?()
    }
}
