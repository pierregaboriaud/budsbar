import XCTest
@testable import BudsKit

final class ProtocolTests: XCTestCase {
    func testCRCIsXmodem() {
        // The standard check value of CRC-16/XMODEM.
        XCTAssertEqual(Frame.crc16(Array("123456789".utf8)), 0x31C3)
    }

    func testEncodeLayout() {
        let bytes = Frame(id: 120, payload: [1]).encoded()
        XCTAssertEqual(bytes.first, 0xFD)
        XCTAssertEqual(bytes.last, 0xDD)
        XCTAssertEqual(Array(bytes[1...2]), [4, 0])   // id + 1 payload byte + 2 CRC bytes
        XCTAssertEqual(Array(bytes[3...4]), [120, 1])
        XCTAssertEqual(bytes.count, 8)
    }

    func testRoundTrip() {
        var reader = FrameReader()
        let frame = Frame(id: 97, payload: [1, 2, 3, 0xDD, 0xFD], isResponse: true)
        XCTAssertEqual(reader.feed(frame.encoded()), [frame])
    }

    func testReaderHandlesSplitMergedAndNoisyInput() {
        let a = Frame(id: 96, payload: [1, 80, 90, 1, 0, 0x11, 55])
        let b = Frame(id: 119, payload: [2])
        let stream = [0x00, 0xFD] + a.encoded() + b.encoded()
        var reader = FrameReader()
        var frames: [Frame] = []
        for byte in stream { frames += reader.feed([byte]) }
        XCTAssertEqual(frames, [a, b])
        XCTAssertEqual(reader.discarded, 2)
    }

    func testReaderDropsCorruptedFrame() {
        var bytes = Frame(id: 96, payload: [1, 80, 90]).encoded()
        bytes[5] ^= 0xFF
        let good = Frame(id: 119, payload: [1])
        var reader = FrameReader()
        XCTAssertEqual(reader.feed(bytes + good.encoded()), [good])
    }

    func testStatusUpdate() {
        var status = BudsStatus()
        // revision, left, right, coupled, main connection, placement (L wearing, R in case), case
        XCTAssertTrue(status.apply(Frame(id: MessageID.statusUpdated, payload: [1, 82, 100, 1, 0, 0x13, 64])))
        XCTAssertEqual(status.left, 82)
        XCTAssertEqual(status.right, 100)
        XCTAssertEqual(status.caseLevel, 64)
        XCTAssertEqual(status.placementLeft, .wearing)
        XCTAssertEqual(status.placementRight, .inCase)
        XCTAssertEqual(status.isWorn, true)
    }

    func testExtendedStatusUpdate() {
        var status = BudsStatus()
        let payload: [UInt8] = [10, 0, 71, 69, 1, 1, 0x22, 101, 0, 0, 0, 0, 1, 0]
        XCTAssertTrue(status.apply(Frame(id: MessageID.extendedStatusUpdated, payload: payload)))
        XCTAssertEqual(status.left, 71)
        XCTAssertEqual(status.right, 69)
        XCTAssertNil(status.caseLevel, "101 means the case is not reporting")
        XCTAssertEqual(status.isWorn, false)
        XCTAssertEqual(status.noiseControl, .noiseCancelling)
    }

    func testCaseLevelSurvivesAnUnknownReport() {
        var status = BudsStatus()
        status.apply(Frame(id: MessageID.statusUpdated, payload: [1, 50, 50, 1, 0, 0x33, 40]))
        status.apply(Frame(id: MessageID.statusUpdated, payload: [1, 50, 50, 1, 0, 0x11, 0]))
        XCTAssertEqual(status.caseLevel, 40)
    }

    func testWornIsUnknownBeforeAnyPlacement() {
        XCTAssertNil(BudsStatus().isWorn)
    }

    func testNoiseControlUpdateAndUnknownMode() {
        var status = BudsStatus()
        status.apply(Frame(id: MessageID.noiseControlsUpdate, payload: [2]))
        XCTAssertEqual(status.noiseControl, .ambient)
        status.apply(Frame(id: MessageID.noiseControlsUpdate, payload: [3]))
        XCTAssertNil(status.noiseControl)
        XCTAssertEqual(status.otherNoiseMode, 3)
    }

    func testUnrelatedFrameIsIgnored() {
        var status = BudsStatus()
        XCTAssertFalse(status.apply(Frame(id: 41, payload: [1, 2, 3])))
        XCTAssertEqual(status, BudsStatus())
    }
}
