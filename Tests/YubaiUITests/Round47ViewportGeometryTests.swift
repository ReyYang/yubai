import XCTest

final class Round47ViewportGeometryTests: XCTestCase {
    func testHomeCardCrossingHeaderUsesOnlyItsVisiblePart() {
        let row = CGRect(x: 20, y: 84.7, width: 400, height: 88)
        let header = CGRect(x: 376, y: 76, width: 44, height: 44)
        XCTAssertTrue(UIViewportGeometry.overlaps(row, header))
        let visible = UIViewportGeometry.clipped(row, to: [CGRect(x: 0, y: 130, width: 440, height: 656)])
        XCTAssertFalse(UIViewportGeometry.overlaps(visible, header))
    }
    func testLedgerRowCrossingCapsuleUsesTheCollectionViewport() {
        let row = CGRect(x: 20, y: 810.3, width: 400, height: 64)
        let tab = CGRect(x: 182, y: 868, width: 76, height: 48)
        XCTAssertTrue(UIViewportGeometry.overlaps(row, tab))
        XCTAssertFalse(UIViewportGeometry.overlaps(UIViewportGeometry.clipped(row, to: [CGRect(x: 0, y: 130, width: 440, height: 720)]), tab))
    }
    func testEveryScrollAncestorClipsTheControl() {
        let row = CGRect(x: 350, y: 760, width: 100, height: 44)
        let visible = UIViewportGeometry.clipped(row, to: [CGRect(x: 0, y: 130, width: 440, height: 650), CGRect(x: 20, y: 750, width: 400, height: 44)])
        XCTAssertEqual(visible, CGRect(x: 350, y: 760, width: 70, height: 20))
    }
    func testFullyOffViewportControlHasNoOverlap() {
        let hidden = UIViewportGeometry.clipped(CGRect(x: 20, y: 900, width: 400, height: 44), to: [CGRect(x: 0, y: 130, width: 440, height: 650)])
        XCTAssertTrue(hidden.isNull || hidden.isEmpty)
        XCTAssertFalse(UIViewportGeometry.overlaps(hidden, CGRect(x: 0, y: 900, width: 440, height: 44)))
    }
    func testStructuralRuleRejectsScrollUnderOurFixedActions() {
        let action = CGRect(x: 20, y: 800, width: 160, height: 44)
        XCTAssertFalse(UIViewportGeometry.overlaps(CGRect(x: 0, y: 116, width: 440, height: 664), action))
        XCTAssertTrue(UIViewportGeometry.overlaps(CGRect(x: 0, y: 116, width: 440, height: 699.3), action))
    }
    func testNativeNavigationClipsAccountsWithoutShrinkingItsScroll() {
        let viewport = CGRect(x: 0, y: 0, width: 440, height: 956)
        let bar = CGRect(x: 0, y: 62, width: 440, height: 54)
        let row = CGRect(x: 36, y: 53, width: 368, height: 99)
        let parts = UIViewportGeometry.visibleParts(row, ancestors: [viewport], excluding: [bar])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.last, CGRect(x: 36, y: 116, width: 368, height: 36))
        XCTAssertFalse(parts.contains { UIViewportGeometry.overlaps($0, CGRect(x: 20, y: 62, width: 44, height: 44)) })
    }
    func testControlEntirelyInsideNativeNavigationHasNoVisibleRemainder() {
        XCTAssertTrue(UIViewportGeometry.visibleParts(CGRect(x: 24, y: 70, width: 70, height: 44), ancestors: [],
            excluding: [CGRect(x: 0, y: 62, width: 440, height: 54)]).isEmpty)
    }
    func testToastAllowanceRequiresEnoughActualScrollTravel() {
        let row = CGRect(x: 372, y: 708, width: 44, height: 44)
        let viewport = CGRect(x: 0, y: 130, width: 440, height: 656)
        let toast = CGRect(x: 20, y: 734, width: 400, height: 52)
        XCTAssertTrue(UIViewportGeometry.canClearToast(row, viewport: viewport, toast: toast, remainingDown: 40))
        XCTAssertFalse(UIViewportGeometry.canClearToast(row, viewport: viewport, toast: toast, remainingDown: 10))
    }
    func testToastCannotExemptAControlTooTallToFitAboveIt() {
        XCTAssertFalse(UIViewportGeometry.canClearToast(CGRect(x: 20, y: 130, width: 400, height: 650),
            viewport: CGRect(x: 0, y: 130, width: 440, height: 656), toast: CGRect(x: 20, y: 738, width: 400, height: 44), remainingDown: 1000))
    }
    func testNativeWindowMetricsDecodeSafeAreaAndRemainingScrollTravel() {
        let json = #"{"safeArea":[0,62,440,860],"transitioning":false,"focused":"frequentEntryPurpose","scrolls":[{"identifier":"nowScroll","frame":[0,130,440,656],"remainingDown":64,"remainingUp":0}]}"#
        let metrics = UIWindowMetrics.decode(json)
        XCTAssertEqual(metrics?.safeRectangle.maxY, 922)
        XCTAssertEqual(metrics?.focused, "frequentEntryPurpose")
        XCTAssertEqual(metrics?.scroll(matching: CGRect(x: 0, y: 130, width: 440, height: 656))?.remainingDown, 64)
        XCTAssertNil(UIWindowMetrics.decode("missing native metrics"))
    }
    func testHalfPointToleranceDoesNotPermitLargerOverlaps() {
        let fixed = CGRect(x: 0, y: 800, width: 44, height: 44)
        XCTAssertFalse(UIViewportGeometry.overlaps(CGRect(x: 0, y: 760, width: 44, height: 40.5), fixed))
        XCTAssertTrue(UIViewportGeometry.overlaps(CGRect(x: 0, y: 760, width: 44, height: 40.6), fixed))
    }
}
