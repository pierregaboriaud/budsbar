import CoreAudio
import Foundation

/// The little of CoreAudio BudsBar needs: list devices, read and set the defaults.
public enum AudioDevices {
    public enum Direction {
        case input, output

        var scope: AudioObjectPropertyScope {
            self == .input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        }
        var defaultSelector: AudioObjectPropertySelector {
            self == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        }
    }

    public struct Device: Equatable {
        public let id: AudioDeviceID
        public let uid: String
        public let name: String
        public let isBuiltIn: Bool

        public init(id: AudioDeviceID, uid: String, name: String, isBuiltIn: Bool) {
            self.id = id
            self.uid = uid
            self.name = name
            self.isBuiltIn = isBuiltIn
        }
    }

    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func number<T: Numeric>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ type: T.Type) -> T? {
        var addr = addr
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &value) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? value : nil
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }

    static func allIDs() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func hasStreams(_ id: AudioDeviceID, _ direction: Direction) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, direction.scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    static func describe(_ id: AudioDeviceID) -> Device {
        let transport = number(id, address(kAudioDevicePropertyTransportType), UInt32.self)
        return Device(id: id,
                      uid: string(id, kAudioDevicePropertyDeviceUID),
                      name: string(id, kAudioObjectPropertyName),
                      isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn)
    }

    /// Devices a person would pick from: aggregates and virtual devices made by apps are left out.
    public static func list(_ direction: Direction) -> [Device] {
        allIDs().filter { hasStreams($0, direction) }.compactMap { id in
            let transport = number(id, address(kAudioDevicePropertyTransportType), UInt32.self)
            if transport == kAudioDeviceTransportTypeAggregate || transport == kAudioDeviceTransportTypeVirtual {
                return nil
            }
            return describe(id)
        }
    }

    public static func current(_ direction: Direction) -> Device? {
        guard let id = number(system, address(direction.defaultSelector), AudioDeviceID.self), id != 0 else { return nil }
        return describe(id)
    }

    @discardableResult
    public static func select(_ id: AudioDeviceID, _ direction: Direction) -> Bool {
        var selectors = [direction.defaultSelector]
        // Alerts and system sounds follow the output a person picks, as in the Sound menu.
        if direction == .output { selectors.append(kAudioHardwarePropertyDefaultSystemOutputDevice) }
        var ok = true
        for selector in selectors {
            var addr = address(selector)
            var id = id
            ok = AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id) == noErr && ok
        }
        return ok
    }

    static func sampleRate(_ id: AudioDeviceID) -> Double {
        number(id, address(kAudioDevicePropertyNominalSampleRate), Float64.self) ?? 0
    }

    static func isRunning(_ id: AudioDeviceID) -> Bool {
        (number(id, address(kAudioDevicePropertyDeviceIsRunningSomewhere), UInt32.self) ?? 0) != 0
    }

    /// A Bluetooth device's CoreAudio UID starts with its address, "AA-BB-CC-DD-EE-FF:output".
    public static func isPresent(bluetoothAddress: String) -> Bool {
        allIDs().contains { string($0, kAudioDevicePropertyDeviceUID).uppercased().contains(bluetoothAddress) }
    }
}
