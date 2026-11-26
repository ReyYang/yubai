import XCTest
@testable import YubaiApp

final class EntrySheetMotionTests: XCTestCase {
    @MainActor
    func testSpringUsesTheInitiatingCompletionExactlyOnce() throws {
        let motion = EntrySheetMotion(settled: true)
        motion.updateHeight(300, reduced: false)
        var completions = 0
        motion.close(reduced: false, sealed: true) { completions += 1 }
        let flight = try XCTUnwrap(motion.flight)
        XCTAssertEqual(completions, 0)
        motion.finish(flight) { XCTFail("The generic close cannot replace the initiating action") }
        motion.finish(flight) { XCTFail("The finished flight cannot close again") }
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    func testReduceMotionUsesTheInitiatingCompletionExactlyOnce() async throws {
        let motion = EntrySheetMotion(settled: false)
        motion.updateHeight(300, reduced: false)
        let oldFlight = try XCTUnwrap(motion.flight)
        let completed = expectation(description: "Reduced-motion close completed")
        completed.assertForOverFulfill = true
        var completions = 0
        motion.close(reduced: true, sealed: true) {
            completions += 1
            completed.fulfill()
        }
        motion.close(reduced: true) { XCTFail("The pending close cannot be replaced") }
        motion.finish(oldFlight) { XCTFail("A superseded spring cannot close the sheet") }
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(completions, 1)
    }
}
