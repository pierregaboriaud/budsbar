import Foundation

public enum MessageID {
    public static let statusUpdated: UInt8 = 96
    public static let extendedStatusUpdated: UInt8 = 97
    public static let noiseControlsUpdate: UInt8 = 119   // Buds → Mac: changed on the earbud
    public static let noiseControls: UInt8 = 120         // Mac → Buds
    public static let managerInfo: UInt8 = 136
}

public enum Placement: Int {
    case unknown = 0, wearing = 1, notWearing = 2, inCase = 3, inClosedCase = 4

    public var isInCase: Bool { self == .inCase || self == .inClosedCase }
}

public enum NoiseControl: Int, CaseIterable {
    case off = 0, noiseCancelling = 1, ambient = 2

    public var title: String {
        switch self {
        case .off: return "Off"
        case .noiseCancelling: return "Noise cancelling"
        case .ambient: return "Ambient sound"
        }
    }
}

/// What the Buds report about themselves. Levels are percentages; nil = not reported.
public struct BudsStatus: Equatable {
    public var left: Int?
    public var right: Int?
    /// The case only reports while an earbud sits in it; the last known value is kept.
    public var caseLevel: Int?
    public var placementLeft = Placement.unknown
    public var placementRight = Placement.unknown
    public var noiseControl: NoiseControl?
    /// The raw mode byte when it is not one BudsBar knows (e.g. 3 = adaptive on newer models).
    public var otherNoiseMode: Int?

    public init() {}

    /// At least one earbud is in an ear. nil until the Buds have reported a placement.
    public var isWorn: Bool? {
        if placementLeft == .unknown && placementRight == .unknown { return nil }
        return placementLeft == .wearing || placementRight == .wearing
    }

    /// How many earbuds are in an ear. nil until the Buds have reported a placement.
    public var wornCount: Int? {
        isWorn == nil ? nil : [placementLeft, placementRight].filter { $0 == .wearing }.count
    }

    /// Updates from a frame; returns false when the frame carries no status.
    @discardableResult
    public mutating func apply(_ frame: Frame) -> Bool {
        let p = frame.payload
        switch frame.id {
        case MessageID.statusUpdated:
            // [revision, left, right, coupled, main connection, placement, case, …]
            guard p.count >= 3 else { return false }
            setLevels(left: p[1], right: p[2])
            if p.count > 5 { setPlacement(p[5]) }
            if p.count > 6 { setCase(p[6]) }
        case MessageID.extendedStatusUpdated:
            // [revision, ear type, left, right, coupled, main connection, placement, case, …,
            //  [12] noise control mode, …]
            guard p.count >= 8 else { return false }
            setLevels(left: p[2], right: p[3])
            setPlacement(p[6])
            setCase(p[7])
            if p.count > 12 { setNoise(p[12]) }
        case MessageID.noiseControlsUpdate:
            guard let mode = p.first else { return false }
            setNoise(mode)
        default:
            return false
        }
        return true
    }

    private mutating func setLevels(left l: UInt8, right r: UInt8) {
        left = l <= 100 ? Int(l) : nil
        right = r <= 100 ? Int(r) : nil
    }

    private mutating func setPlacement(_ byte: UInt8) {
        placementLeft = Placement(rawValue: Int(byte >> 4)) ?? .unknown
        placementRight = Placement(rawValue: Int(byte & 0x0F)) ?? .unknown
    }

    private mutating func setCase(_ byte: UInt8) {
        if (1...100).contains(byte) { caseLevel = Int(byte) }
    }

    private mutating func setNoise(_ byte: UInt8) {
        noiseControl = NoiseControl(rawValue: Int(byte))
        otherNoiseMode = noiseControl == nil ? Int(byte) : nil
    }
}

public enum Command {
    /// Announces a companion app; the Buds answer with their extended status.
    public static let hello = Frame(id: MessageID.managerInfo, payload: [1, 1, 0, 1])

    public static func setNoiseControl(_ mode: NoiseControl) -> Frame {
        Frame(id: MessageID.noiseControls, payload: [UInt8(mode.rawValue)])
    }
}
