import XCTest
@testable import BudsKit

final class PlaybackResumeTests: XCTestCase {
    private let pause = "… [com.apple.bluetooth:Server.Remote] Received AVRCP Pause command from device AA:BB:CC:DD:EE:FF"
    private let playLine = "… [com.apple.bluetooth:Server.Remote] Received AVRCP Play command from device AA:BB:CC:DD:EE:FF"
    private var plays = 0
    private var resume: PlaybackResume!
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        plays = 0
        resume = PlaybackResume(play: { [unowned self] in self.plays += 1 }, log: { _ in })
        resume.setDevice(address: "AA-BB-CC-DD-EE-FF")
        resume.setWornCount(2, at: t0)
    }

    /// The Play command is sent a second after the earbud goes back in.
    private func settle() {
        resume.flush()
        let done = expectation(description: "delayed play")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.3) { done.fulfill() }
        wait(for: [done], timeout: 3)
        resume.flush()
    }

    func testResumesAfterRemovalPause() {
        resume.setWornCount(0, at: t0 + 10)
        resume.logLine(pause, at: t0 + 11)
        resume.setWornCount(2, at: t0 + 40)
        settle()
        XCTAssertEqual(plays, 1)
    }

    func testPauseBeforeTheWearReportCountsToo() {
        resume.logLine(pause, at: t0 + 10)
        resume.setWornCount(1, at: t0 + 11)
        resume.setWornCount(2, at: t0 + 40)
        settle()
        XCTAssertEqual(plays, 1)
    }

    func testNothingWasPlaying() {
        resume.setWornCount(0, at: t0 + 10)
        resume.setWornCount(2, at: t0 + 40)
        settle()
        XCTAssertEqual(plays, 0)
    }

    func testPauseByTouchIsLeftAlone() {
        resume.logLine(pause, at: t0 + 10)
        resume.setWornCount(0, at: t0 + 60)
        resume.setWornCount(2, at: t0 + 90)
        settle()
        XCTAssertEqual(plays, 0)
    }

    func testAlreadyRestartedByHand() {
        resume.setWornCount(0, at: t0 + 10)
        resume.logLine(pause, at: t0 + 11)
        resume.logLine(playLine, at: t0 + 20)
        resume.setWornCount(2, at: t0 + 40)
        settle()
        XCTAssertEqual(plays, 0)
    }

    func testTooLongAway() {
        resume.setWornCount(0, at: t0 + 10)
        resume.logLine(pause, at: t0 + 11)
        resume.setWornCount(2, at: t0 + 11 + PlaybackResume.maxAway + 1)
        settle()
        XCTAssertEqual(plays, 0)
    }

    func testOtherDeviceAndDisabled() {
        resume.setWornCount(0, at: t0 + 10)
        resume.logLine(pause.replacingOccurrences(of: "AA:BB", with: "11:22"), at: t0 + 11)
        resume.setWornCount(2, at: t0 + 40)
        resume.setEnabled(false)
        resume.setWornCount(0, at: t0 + 50)
        resume.logLine(pause, at: t0 + 51)
        resume.setWornCount(2, at: t0 + 60)
        settle()
        XCTAssertEqual(plays, 0)
    }
}
