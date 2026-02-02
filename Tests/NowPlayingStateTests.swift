import XCTest
@testable import itsytv

final class NowPlayingStateTests: XCTestCase {

    // MARK: - isPlaying

    func testIsPlayingWhenRatePositive() {
        let state = NowPlayingState(playbackRate: 1.0, timestamp: Date())
        XCTAssertTrue(state.isPlaying)
    }

    func testIsNotPlayingWhenRateZero() {
        let state = NowPlayingState(playbackRate: 0, timestamp: Date())
        XCTAssertFalse(state.isPlaying)
    }

    // MARK: - currentPosition

    func testCurrentPositionReturnsZeroWhenElapsedTimeNil() {
        let state = NowPlayingState(elapsedTime: nil, playbackRate: 1.0, timestamp: Date())
        XCTAssertEqual(state.currentPosition, 0)
    }

    func testCurrentPositionWhenPaused() {
        let state = NowPlayingState(
            elapsedTime: 30.0,
            playbackRate: 0,
            timestamp: Date(timeIntervalSinceNow: -5.0)
        )
        // Rate is 0, so position = elapsed + 0 = 30
        XCTAssertEqual(state.currentPosition, 30.0, accuracy: 0.1)
    }

    func testCurrentPositionWhenPlaying() {
        let fiveSecondsAgo = Date(timeIntervalSinceNow: -5.0)
        let state = NowPlayingState(
            elapsedTime: 10.0,
            playbackRate: 1.0,
            timestamp: fiveSecondsAgo
        )
        // position = 10 + ~5 * 1.0 = ~15
        XCTAssertEqual(state.currentPosition, 15.0, accuracy: 0.5)
    }

    func testCurrentPositionWithFastForward() {
        let fiveSecondsAgo = Date(timeIntervalSinceNow: -5.0)
        let state = NowPlayingState(
            elapsedTime: 10.0,
            playbackRate: 2.0,
            timestamp: fiveSecondsAgo
        )
        // position = 10 + ~5 * 2.0 = ~20
        XCTAssertEqual(state.currentPosition, 20.0, accuracy: 0.5)
    }
}
