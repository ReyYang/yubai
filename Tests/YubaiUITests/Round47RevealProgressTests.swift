import XCTest

final class Round47RevealProgressTests: XCTestCase {
    func testRunElevenRescueUsesAHitTestedListGutterAndStillRequiresFullChromeClearance() throws {
        let viewport = CGRect(x: 0, y: 130, width: 440, height: 668)
        let rescue = CGRect(x: 36, y: 798.7, width: 348, height: 72.3)
        let chrome = CGRect(x: 0, y: 798, width: 440, height: 124)
        var progress = UIRevealProgress()
        let step = progress.next(.init(target: rescue, viewport: viewport))
        let gutter = CGPoint(x: 13.2, y: 651.04)
        let gesture = try XCTUnwrap(UIRevealPan.plan(step, viewport: viewport,
            nativeOrigins: [gutter, CGPoint(x: 426.8, y: 651.04), CGPoint(x: 220, y: 651.04)]))
        XCTAssertEqual(gesture.start, gutter)
        XCTAssertLessThan(gesture.start.x, 20, "Start on the native List, outside its inset card")
        XCTAssertEqual(gesture.start.y - gesture.end.y, 81, accuracy: 0.01)
        XCTAssertTrue(viewport.contains(gesture.start) && viewport.contains(gesture.end))
        XCTAssertFalse(UIViewportGeometry.revealed(exists: true, enabled: true, hittable: true,
            frame: rescue, scrollAncestors: [viewport], occlusions: [chrome]))
        let revealed = rescue.offsetBy(dx: 0, dy: gesture.end.y - gesture.start.y)
        XCTAssertEqual(progress.next(.init(target: revealed, viewport: viewport)), .reached)
        XCTAssertTrue(UIViewportGeometry.revealed(exists: true, enabled: true, hittable: true,
            frame: revealed, scrollAncestors: [viewport], occlusions: [chrome]))
    }
    func testNativePanOriginsOutsideTheUnobscuredViewportCannotBeUsed() {
        let viewport = CGRect(x: 0, y: 130, width: 440, height: 420)
        XCTAssertNil(UIRevealPan.plan(.drag(up: true, distance: 100), viewport: viewport,
            nativeOrigins: [CGPoint(x: 220, y: 600), CGPoint(x: 220, y: 100)]))
        XCTAssertNil(UIRevealPan.plan(.drag(up: true, distance: 100), viewport: viewport, nativeOrigins: []),
                     "A known blocked scroll must not fall back to the card center")
    }
    func testPanChoosesAnotherObservedLaneWhenChromeCoversTheFirst() throws {
        let viewport = CGRect(x: 0, y: 130, width: 440, height: 420)
        let gesture = try XCTUnwrap(UIRevealPan.plan(.drag(up: true, distance: 100), viewport: viewport,
            nativeOrigins: [CGPoint(x: 13.2, y: 651), CGPoint(x: 13.2, y: 464), CGPoint(x: 13.2, y: 277)]))
        XCTAssertEqual(gesture.start, CGPoint(x: 13.2, y: 464))
        XCTAssertEqual(gesture.end, CGPoint(x: 13.2, y: 364))
    }
    func testPanRequiresEnoughRoomToMoveInTheRequestedDirection() {
        XCTAssertNil(UIRevealPan.plan(.drag(up: true, distance: 100), viewport: viewport,
            nativeOrigins: [CGPoint(x: 220, y: viewport.minY + 12)]))
        XCTAssertNil(UIRevealPan.plan(.drag(up: false, distance: 100), viewport: viewport,
            nativeOrigins: [CGPoint(x: 220, y: viewport.maxY - 13)]))
    }
    func testHorizontalPanStillUsesItsOwnShortScrollAndClipsItsEnd() throws {
        let viewport = CGRect(x: 20, y: 400, width: 400, height: 44)
        let gesture = try XCTUnwrap(UIRevealPan.plan(.dragHorizontally(left: true, distance: 900), viewport: viewport,
            nativeOrigins: [CGPoint(x: 320, y: 422)]))
        XCTAssertEqual(gesture.start, CGPoint(x: 320, y: 422))
        XCTAssertEqual(gesture.end, CGPoint(x: 32, y: 422))
    }
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
    func testPostDragWaitAllowsCachedSamplesBeforeRealNativeMotion() {
        var now: TimeInterval = 0
        let before = sample(827, height: 44)
        XCTAssertTrue(UIRevealMotionWait.run(from: before, timeout: 1, read: {
            now < 0.3 ? before : self.sample(727, height: 44)
        }, clock: { now }, poll: { now += $0 }))
        XCTAssertGreaterThanOrEqual(now, 0.3)
    }
    func testPostDragWaitNeverAcceptsStationaryContent() {
        var now: TimeInterval = 0
        let before = sample(827, height: 44)
        XCTAssertFalse(UIRevealMotionWait.run(from: before, timeout: 1, read: { before },
                                             clock: { now }, poll: { now += $0 }))
        XCTAssertEqual(now, 1, accuracy: 0.001)
    }
    func testPostDragWaitKeepsTheOriginalDeadlineEvenWithASlowSnapshot() {
        var now: TimeInterval = 0
        let before = sample(827, height: 44)
        XCTAssertFalse(UIRevealMotionWait.run(from: before, timeout: 6, deadline: 1, read: {
            now += 2
            return self.sample(727, height: 44)
        }, clock: { now }, poll: { now += $0 }))
    }
    func testPostDragWaitObservesNativeMotionWhenTextReflowMovesTheTargetAway() {
        var before = sample(827, height: 44); before.scrollOffset = 0
        var after = sample(860, height: 44); after.scrollOffset = 100
        XCTAssertTrue(UIRevealMotionWait.run(from: before, read: { after }))
    }
    func testPostDragWaitReturnsANewlyMaterializedTargetForOrdinaryReachabilityChecks() {
        let before = UIRevealProgress.Sample(target: nil, viewport: viewport)
        XCTAssertTrue(UIRevealMotionWait.run(from: before, read: { self.sample(600) }))
        var progress = UIRevealProgress()
        XCTAssertEqual(progress.next(sample(600)), .reached)
    }
    func testHiddenHardSettingsUsesItsShortRealScrollTravelAfterCachedSamples() {
        // Run 6: content 779.3pt in a 732pt viewport, setting row under the
        // capsule by 19.3pt. It is not at the end: 47.3pt of travel remains.
        let viewport = CGRect(x: 0, y: 130, width: 440, height: 732)
        let before = UIRevealProgress.Sample(target: CGRect(x: 36, y: 829.3, width: 368, height: 52),
                                             viewport: viewport, scrollOffset: 0)
        var progress = UIRevealProgress()
        guard case let .drag(up, distance) = progress.next(before) else { return XCTFail() }
        XCTAssertTrue(up)
        XCTAssertEqual(distance, 27.3, accuracy: 0.01)
        XCTAssertLessThan(distance, 47.3)
        let after = UIRevealProgress.Sample(target: before.target?.offsetBy(dx: 0, dy: -distance),
                                            viewport: viewport, scrollOffset: distance)
        var now: TimeInterval = 0
        XCTAssertTrue(UIRevealMotionWait.run(from: before, timeout: 1, read: { now < 0.3 ? before : after },
                                             clock: { now }, poll: { now += $0 }))
        XCTAssertEqual(progress.next(after), .reached)
        XCTAssertTrue(UIViewportGeometry.revealed(exists: true, enabled: true, hittable: true,
            frame: after.target!, scrollAncestors: [viewport],
            occlusions: [CGRect(x: 0, y: 862, width: 440, height: 60)]))
    }
}
