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
    func testTemporarilyAbsentTargetKeepsSearchingWhileContentMoves() {
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
    func testVisibleCategoryInFortyFourPointHorizontalScrollIsAlreadyReached() {
        var progress = UIRevealProgress()
        let strip = CGRect(x: 20, y: 400, width: 400, height: 44)
        XCTAssertEqual(progress.next(.init(target: CGRect(x: 20, y: 400, width: 58.7, height: 44), viewport: strip)), .reached)
    }
    func testCategoryStillNeedsItsOuterScrollToRevealIt() {
        var progress = UIRevealProgress()
        let clippedStrip = CGRect(x: 20, y: 448, width: 400, height: 22)
        XCTAssertEqual(progress.next(.init(target: CGRect(x: 20, y: 448, width: 58.7, height: 44), viewport: clippedStrip)), .stalled)
    }
    func testCategoryBeyondHorizontalEdgeIsScrolledIntoTheStrip() {
        var progress = UIRevealProgress()
        let strip = CGRect(x: 20, y: 400, width: 400, height: 44)
        guard case .dragHorizontally(left: true, distance: _) = progress.next(.init(target: CGRect(x: 410, y: 400, width: 58.7, height: 44), viewport: strip)) else { return XCTFail() }
        XCTAssertEqual(progress.next(.init(target: CGRect(x: 330, y: 400, width: 58.7, height: 44), viewport: strip)), .reached)
    }
    func testCategoryClippedByOuterScrollUsesThatScrollBeforeTheStrip() {
        var progress = UIRevealProgress()
        let outer = CGRect(x: 0, y: 130, width: 440, height: 340)
        guard case .drag(up: true, distance: _) = progress.next(.init(target: CGRect(x: 20, y: 448, width: 58.7, height: 44), viewport: outer)) else { return XCTFail() }
        XCTAssertEqual(progress.next(.init(target: CGRect(x: 20, y: 400, width: 58.7, height: 44), viewport: CGRect(x: 20, y: 400, width: 400, height: 44))), .reached)
    }
    func testLongReceiptReflowDoesNotDiscardRealNativeScrollProgress() {
        var progress = UIRevealProgress()
        var first = sample(1994.7, height: 62.3); first.scrollOffset = 0
        guard case .drag(up: true, distance: _) = progress.next(first) else { return XCTFail() }
        var reflow = sample(2027.3, height: 62.3); reflow.scrollOffset = 120
        guard case .drag(up: true, distance: _) = progress.next(reflow) else { return XCTFail() }
        XCTAssertEqual(progress.next(reflow), .stalled)
    }
    func testVirtualizedLandmarkTurnoverStillRequiresActualNativeMotion() {
        var progress = UIRevealProgress()
        let first = UIRevealProgress.Sample(target: nil, viewport: viewport, landmarks: ["first": 500], scrollOffset: 0)
        _ = progress.next(first)
        let second = UIRevealProgress.Sample(target: nil, viewport: viewport, landmarks: ["later": 500], scrollOffset: 325)
        guard case .drag(up: true, distance: _) = progress.next(second) else { return XCTFail() }
        XCTAssertEqual(progress.next(second), .stalled)
    }
}
