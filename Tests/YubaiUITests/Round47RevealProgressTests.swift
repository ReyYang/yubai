import XCTest

final class Round47RevealProgressTests: XCTestCase {
    private let viewport = CGRect(x: 0, y: 130, width: 440, height: 650)
    private func sample(_ y: CGFloat, height: CGFloat = 60) -> UIRevealProgress.Sample {
        .init(target: CGRect(x: 20, y: y, width: 400, height: height), viewport: viewport)
    }
    func testLongPageContinuesBeyondEightDragsWhileTheTargetApproaches() {
        var progress = UIRevealProgress()
        for index in 0..<16 {
            guard case .drag(up: true, distance: _) = progress.next(sample(4000 - CGFloat(index) * 210)) else {
                return XCTFail("Stopped with real progress at drag \(index)")
            }
        }
        XCTAssertEqual(progress.next(sample(700)), .reached)
    }
    func testOneDragWithNoProgressStopsAtTheEndOfContent() {
        var progress = UIRevealProgress()
        _ = progress.next(sample(900))
        XCTAssertEqual(progress.next(sample(900)), .stalled)
    }
    func testMotionAwayFromTheTargetDoesNotConsumeTheWholeDeadline() {
        var progress = UIRevealProgress()
        _ = progress.next(sample(900))
        XCTAssertEqual(progress.next(sample(1000)), .stalled)
    }
    func testTargetAboveTheHeaderIsBroughtDown() {
        var progress = UIRevealProgress()
        guard case .drag(up: false, distance: _) = progress.next(sample(100)) else { return XCTFail() }
        XCTAssertEqual(progress.next(sample(140)), .reached)
    }
    func testCrossingActionMayDisappearWhileTheContentKeepsMoving() {
        var progress = UIRevealProgress()
        var before = sample(900); before.landmarks = ["date": 500]
        _ = progress.next(before)
        let crossing = UIRevealProgress.Sample(target: nil, viewport: viewport, landmarks: ["date": 360])
        guard case .drag(up: true, distance: _) = progress.next(crossing) else { return XCTFail() }
        XCTAssertEqual(progress.next(sample(600)), .reached)
    }
    func testAbsentTargetWithStationaryContentFails() {
        var progress = UIRevealProgress()
        let absent = UIRevealProgress.Sample(target: nil, viewport: viewport, landmarks: ["date": 500])
        _ = progress.next(absent)
        XCTAssertEqual(progress.next(absent), .stalled)
    }
    func testImpossibleWholeTargetAndEmptyViewportFail() {
        var progress = UIRevealProgress()
        XCTAssertEqual(progress.next(sample(130, height: 900)), .stalled)
        XCTAssertEqual(progress.next(.init(target: nil, viewport: .zero)), .stalled)
    }
}
