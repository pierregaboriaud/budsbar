import Foundation

/// One message of the Galaxy Buds control protocol (Buds+ and later), carried over RFCOMM:
///
///     0xFD | header (LE, 10-bit size + flags) | id | payload… | CRC-16 (LE) | 0xDD
///
/// `size` counts id + payload + CRC. The CRC covers id + payload.
public struct Frame: Equatable {
    public let id: UInt8
    public let payload: [UInt8]
    public let isResponse: Bool

    public init(id: UInt8, payload: [UInt8] = [], isResponse: Bool = false) {
        self.id = id
        self.payload = payload
        self.isResponse = isResponse
    }

    static let start: UInt8 = 0xFD
    static let end: UInt8 = 0xDD
    static let responseFlag: UInt16 = 0x1000
    static let sizeMask: UInt16 = 0x03FF

    /// CRC-16/XMODEM (polynomial 0x1021, seed 0). The Buds ignore a frame whose CRC is wrong.
    public static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    public func encoded() -> [UInt8] {
        let body = [id] + payload
        let crc = Frame.crc16(body)
        var header = UInt16(body.count + 2) & Frame.sizeMask
        if isResponse { header |= Frame.responseFlag }
        return [Frame.start, UInt8(header & 0xFF), UInt8(header >> 8)]
            + body
            + [UInt8(crc & 0xFF), UInt8(crc >> 8), Frame.end]
    }
}

/// Reassembles frames from the RFCOMM byte stream, which splits and merges them freely.
public struct FrameReader {
    private var buffer: [UInt8] = []
    /// Bytes thrown away while looking for a valid frame; useful in a diagnostics log.
    public private(set) var discarded = 0

    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [Frame] {
        buffer += bytes
        var frames: [Frame] = []
        while let start = buffer.firstIndex(of: Frame.start) {
            skip(start)
            switch parse(at: 0) {
            case .frame(let frame, let length):
                frames.append(frame)
                buffer.removeFirst(length)
            case .invalid:
                skip(1)
            case .incomplete:
                // A stray start byte can announce a long frame that never comes, and would hold
                // everything behind it: a complete, CRC-valid frame further on settles it.
                guard let later = buffer.indices.dropFirst().first(where: {
                    if case .frame = parse(at: $0) { return true } else { return false }
                }) else { return frames }
                skip(later)
            }
        }
        skip(buffer.count)
        return frames
    }

    private enum Parsed {
        case frame(Frame, length: Int), incomplete, invalid
    }

    private func parse(at offset: Int) -> Parsed {
        guard buffer[offset] == Frame.start else { return .invalid }
        guard buffer.count - offset >= 3 else { return .incomplete }
        let header = UInt16(buffer[offset + 1]) | UInt16(buffer[offset + 2]) << 8
        let size = Int(header & Frame.sizeMask)
        guard size >= 3 else { return .invalid }
        // The length comes from the header, never from scanning for 0xDD: a payload byte may
        // well be 0xDD.
        let length = size + 4
        guard buffer.count - offset >= length else { return .incomplete }
        let end = offset + length
        let body = Array(buffer[(offset + 3)..<(end - 3)])
        let crc = UInt16(buffer[end - 3]) | UInt16(buffer[end - 2]) << 8
        guard buffer[end - 1] == Frame.end, Frame.crc16(body) == crc else { return .invalid }
        let frame = Frame(id: body[0], payload: Array(body.dropFirst()),
                          isResponse: header & Frame.responseFlag != 0)
        return .frame(frame, length: length)
    }

    /// Bytes that belong to no frame.
    private mutating func skip(_ count: Int) {
        discarded += count
        buffer.removeFirst(count)
    }
}
