import BudsKit
import CoreAudio
import Foundation
import ServiceManagement

/// What the panel and the menu-bar item show, and the actions behind their controls.
final class AppModel: ObservableObject {
    enum BarStyle: String, CaseIterable, Identifiable {
        case all, earbuds, icon

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Earbuds and case"
            case .earbuds: return "Earbuds only"
            case .icon: return "Icon only"
            }
        }
    }

    @Published private(set) var name: String?
    @Published private(set) var isLinked = false
    @Published private(set) var isStuck = false
    @Published private(set) var bluetoothDenied = false
    @Published private(set) var status = BudsStatus()
    @Published private(set) var outputs: [AudioDevices.Device] = []
    @Published private(set) var inputs: [AudioDevices.Device] = []
    @Published private(set) var outputID: AudioDeviceID = 0
    @Published private(set) var inputID: AudioDeviceID = 0
    @Published private(set) var lastRecovery: Date?
    @Published private(set) var launchesAtLogin = false

    @Published var barStyle: BarStyle {
        didSet { defaults.set(barStyle.rawValue, forKey: "barStyle") }
    }
    @Published var recoveryEnabled: Bool {
        didSet {
            defaults.set(recoveryEnabled, forKey: "recovery")
            recovery.setEnabled(recoveryEnabled)
        }
    }

    @Published var resumeEnabled: Bool {
        didSet {
            defaults.set(resumeEnabled, forKey: "resume")
            resume.setEnabled(resumeEnabled)
        }
    }

    private let link: BudsLink
    private let recovery: CallLinkRecovery
    private let resume: PlaybackResume
    private let defaults = UserDefaults.standard

    init(link: BudsLink, recovery: CallLinkRecovery, resume: PlaybackResume) {
        self.link = link
        self.recovery = recovery
        self.resume = resume
        barStyle = BarStyle(rawValue: defaults.string(forKey: "barStyle") ?? "") ?? .all
        recoveryEnabled = defaults.object(forKey: "recovery") as? Bool ?? true
        resumeEnabled = defaults.object(forKey: "resume") as? Bool ?? true
        recovery.setEnabled(recoveryEnabled)
        resume.setEnabled(resumeEnabled)
        recovery.onRecovered = { [weak self] _ in
            DispatchQueue.main.async { self?.lastRecovery = Date() }
        }
        syncLink()
    }

    /// Copies the link's state; called whenever it changes.
    func syncLink() {
        name = link.peer?.name
        isLinked = link.isLinked
        isStuck = link.isStuck
        bluetoothDenied = link.bluetoothDenied
        status = link.status
    }

    /// Sample earbuds for `BudsBar --snapshot`, which draws the panel without any hardware.
    func loadSample() {
        var sample = BudsStatus()
        sample.left = 78
        sample.right = 82
        sample.caseLevel = 25
        sample.placementLeft = .wearing
        sample.placementRight = .wearing
        sample.noiseControl = .noiseCancelling
        name = "Galaxy Buds2"
        isLinked = true
        status = sample
        outputs = [AudioDevices.Device(id: 1, uid: "", name: "Galaxy Buds2", isBuiltIn: false),
                   AudioDevices.Device(id: 2, uid: "", name: "MacBook Pro Speakers", isBuiltIn: true)]
        inputs = [AudioDevices.Device(id: 1, uid: "", name: "Galaxy Buds2", isBuiltIn: false),
                  AudioDevices.Device(id: 2, uid: "", name: "MacBook Pro Microphone", isBuiltIn: true)]
        outputID = 1
        inputID = 1
    }

    /// Audio devices and the login item change outside the app: read them when the panel opens.
    func syncSystem() {
        outputs = AudioDevices.list(.output)
        inputs = AudioDevices.list(.input)
        outputID = AudioDevices.current(.output)?.id ?? 0
        inputID = AudioDevices.current(.input)?.id ?? 0
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setNoiseControl(_ mode: NoiseControl) {
        link.setNoiseControl(mode)
    }

    func select(_ id: AudioDeviceID, _ direction: AudioDevices.Direction) {
        AudioDevices.select(id, direction)
        syncSystem()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.write("launch at login: \(error.localizedDescription)")
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// What the menu-bar item shows next to its icon: the earbuds' average charge, and the case's.
    var barLevels: (earbuds: Int?, caseLevel: Int?) {
        guard name != nil, barStyle != .icon else { return (nil, nil) }
        let sides = [status.left, status.right].compactMap { $0 }
        guard !sides.isEmpty else { return (nil, nil) }
        let average = Int((Double(sides.reduce(0, +)) / Double(sides.count)).rounded())
        return (average, barStyle == .all ? status.caseLevel : nil)
    }
}
