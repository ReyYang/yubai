import XCTest
@testable import YubaiCore

final class DeferredLayoutValueTests: XCTestCase {
    func testNoStateWriteOccursInsideTheGeometryCallback() {
        var jobs: [() -> Void] = []
        let value = DeferredLayoutValue<Int>(schedule: { jobs.append($0) })
        var observed: [Int] = []
        value.submit(44) { observed.append($0) }
        XCTAssertTrue(observed.isEmpty)
        XCTAssertEqual(jobs.count, 1)
        jobs.removeFirst()()
        XCTAssertEqual(observed, [44])
    }
    func testLiveTextSizeReflowPublishesOnlyTheLatestMeasurement() {
        var jobs: [() -> Void] = []
        let value = DeferredLayoutValue<Int>(schedule: { jobs.append($0) })
        var observed: [Int] = []
        for height in [44, 64, 120, 72] { value.submit(height) { observed.append($0) } }
        XCTAssertEqual(jobs.count, 1)
        jobs.removeFirst()()
        value.submit(72) { observed.append($0) }
        XCTAssertTrue(jobs.isEmpty)
        XCTAssertEqual(observed, [72])
    }
    func testCancelledSheetCannotPublishIntoItsReplacement() {
        var jobs: [() -> Void] = []
        let value = DeferredLayoutValue<Int>(schedule: { jobs.append($0) })
        var observed: [Int] = []
        value.submit(44) { observed.append($0) }
        value.cancel()
        value.submit(88) { observed.append($0) }
        jobs.removeFirst()()
        XCTAssertTrue(observed.isEmpty)
        jobs.removeFirst()()
        XCTAssertEqual(observed, [88])
    }
    func testReturningToDeliveredSizeCancelsAnIntermediateReflow() {
        var jobs: [() -> Void] = []
        let value = DeferredLayoutValue<Int>(schedule: { jobs.append($0) })
        var observed: [Int] = []
        value.submit(44) { observed.append($0) }; jobs.removeFirst()()
        value.submit(72) { observed.append($0) }
        value.submit(44) { observed.append($0) }; jobs.removeFirst()()
        XCTAssertEqual(observed, [44])
    }
    func testAReentrantObservationWaitsForAnotherTurn() {
        var jobs: [() -> Void] = []
        let value = DeferredLayoutValue<Int>(schedule: { jobs.append($0) })
        var observed: [Int] = []
        value.submit(44) { height in
            observed.append(height)
            value.submit(88) { observed.append($0) }
        }
        jobs.removeFirst()()
        XCTAssertEqual(observed, [44])
        XCTAssertEqual(jobs.count, 1)
        jobs.removeFirst()()
        XCTAssertEqual(observed, [44, 88])
    }
}
