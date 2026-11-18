import Foundation
import XCTest

final class UIWindowMetricsContractTests: XCTestCase {
    private func fixture() -> [String: Any] {
        let bamboo = UITestMetricsPayload.bamboo(ready: ["dark@3.0", "light@3.0"], pending: 0,
            pendingKeys: [], failed: [], failedStages: [:], renders: 2, mainRenders: 0,
            activeRenders: 0, maxConcurrentRenders: 1, lastFailure: nil)
        return UITestMetricsPayload.dictionary(safeArea: [0, 62, 440, 860], transitioning: false,
            activeTransitions: [], focused: "butlerAICorrectionText", focusedAfterAppearance: true,
            scrolls: [["identifier": "entriesScroll", "frame": [0, 130, 440, 668],
                "remainingDown": 127.33333333333333, "remainingUp": 0,
                "panPoints": [[13.199999999999999, 651.03999999999996], [426.80000000000001, 651.03999999999996],
                              [220, 651.03999999999996], [13.199999999999999, 276.96000000000004]]]],
            bamboo: bamboo, bambooSurface: ["required": false, "key": NSNull()],
            paperDiagnostics: "visited=72 markers=1 emptyMarkers=0 attached=1", inputFocusEvents: ["native editing began", "viewDidAppear"],
            focusedHost: "native-host-123")
    }
    private func read(_ packet: UITestMetricsPayload.Packet, errors: inout [String]) -> UIWindowMetrics? {
        UIWindowMetrics.decodePayload(manifest: packet.manifest,
            parts: Dictionary(uniqueKeysWithValues: packet.parts.map { ($0.identifier, $0.value as Any) }),
            onError: { errors.append($0) })
    }
    func testRunTwelveSnapshotTruncationIsReproducedAndChunkedPayloadDecodes() throws {
        let value = fixture()
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
        XCTAssertGreaterThan(raw.count, 512)
        var errors: [String] = []
        let prefix = String(raw.prefix(512))
        XCTAssertNil(UIWindowMetrics.decode(prefix, onError: { errors.append($0) }))
        XCTAssertTrue(errors[0].contains("dataCorrupted"))
        XCTAssertTrue(errors[0].contains("rawLength=512"))
        XCTAssertTrue(errors[0].hasSuffix(String(prefix.prefix(300))))
        errors = []
        let packet = try UITestMetricsPayload.encode(value)
        XCTAssertLessThan(packet.manifest.count, 512)
        XCTAssertGreaterThan(packet.parts.count, 1)
        XCTAssertTrue(packet.parts.allSatisfy { $0.value.count <= 400 && $0.value.utf8.count == $0.value.count })
        let decoded = try XCTUnwrap(read(packet, errors: &errors))
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(decoded.focused, "butlerAICorrectionText")
        XCTAssertEqual(decoded.focusedAfterAppearance, true)
        XCTAssertEqual(decoded.bamboo?.isReady, true)
        XCTAssertEqual(decoded.bambooSurface?.required, false)
        XCTAssertNil(decoded.bambooSurface?.key)
        XCTAssertEqual(decoded.paperDiagnostics, value["paperDiagnostics"] as? String)
        XCTAssertEqual(decoded.inputFocusEvents, ["native editing began", "viewDidAppear"])
        XCTAssertEqual(decoded.focusedHost, "native-host-123")
        XCTAssertEqual(decoded.scrolls[0].panOrigins?.count, 4)
        XCTAssertEqual(decoded.scrolls[0].remainingDown, 127.33333333333333, accuracy: 0.00000001)
    }
    func testEveryOptionalRootAndScrollFieldDecodesWhenPresentNullOrAbsent() throws {
        for key in ["focusedAfterAppearance", "bamboo", "bambooSurface", "activeTransitions", "paperDiagnostics", "inputFocusEvents", "focusedHost"] {
            for mode in 0..<3 {
                var value = fixture()
                if mode == 1 { value[key] = NSNull() }
                if mode == 2 { value.removeValue(forKey: key) }
                for panMode in 0..<3 {
                    var scroll = (value["scrolls"] as! [[String: Any]])[0]
                    if panMode == 1 { scroll["panPoints"] = NSNull() }
                    if panMode == 2 { scroll.removeValue(forKey: "panPoints") }
                    value["scrolls"] = [scroll]
                    var errors: [String] = []
                    XCTAssertNotNil(read(try UITestMetricsPayload.encode(value), errors: &errors), "\(key),\(mode),\(panMode): \(errors)")
                    XCTAssertTrue(errors.isEmpty)
                }
            }
        }
        let empty = UITestMetricsPayload.dictionary(safeArea: [0, 0, 440, 956], transitioning: true,
            activeTransitions: ["sheet"], focused: "", focusedAfterAppearance: nil, scrolls: [], bamboo: nil, bambooSurface: nil)
        var errors: [String] = []
        let decoded = try XCTUnwrap(read(try UITestMetricsPayload.encode(empty), errors: &errors))
        XCTAssertTrue(decoded.transitioning)
        XCTAssertNil(decoded.bamboo); XCTAssertNil(decoded.bambooSurface); XCTAssertNil(decoded.focusedAfterAppearance)
        XCTAssertEqual(decoded.activeTransitions, ["sheet"])
    }
    func testBambooFailureAndSurfaceOptionalsRetainNullAbsentAndActualValues() throws {
        for failureMode in 0..<3 {
            for keyMode in 0..<3 {
                for after in [false, true] {
                    var value = fixture(), bamboo = value["bamboo"] as! [String: Any]
                    if failureMode == 1 { bamboo.removeValue(forKey: "lastFailure") }
                    if failureMode == 2 {
                        bamboo["lastFailure"] = ["key": "light@3.0", "stage": "outputEmpty", "attempt": 2]
                        bamboo["failed"] = ["light@3.0"]; bamboo["failedStages"] = ["light@3.0": "outputEmpty"]
                    }
                    value["bamboo"] = bamboo; value["focusedAfterAppearance"] = after
                    var surface: [String: Any] = ["required": keyMode == 2]
                    if keyMode == 0 { surface["key"] = NSNull() }
                    if keyMode == 2 { surface["key"] = "light@3.0" }
                    value["bambooSurface"] = surface
                    var errors: [String] = []
                    let decoded = try XCTUnwrap(read(try UITestMetricsPayload.encode(value), errors: &errors), "\(errors)")
                    XCTAssertEqual(decoded.focusedAfterAppearance, after)
                    XCTAssertEqual(decoded.bamboo?.hasFailure, failureMode == 2)
                    XCTAssertEqual(decoded.bamboo?.lastFailure?.attempt, failureMode == 2 ? 2 : nil)
                    XCTAssertEqual(decoded.bambooSurface?.key, keyMode == 2 ? "light@3.0" : nil)
                }
            }
        }
    }
    func testUnicodeLargeNestedPayloadSurvivesTheSnapshotValueLimit() throws {
        var value = fixture()
        value["focused"] = String(repeating: "用途🪴", count: 500)
        value["scrolls"] = Array(repeating: (value["scrolls"] as! [[String: Any]])[0], count: 100)
        let packet = try UITestMetricsPayload.encode(value)
        // Simulate XCTest's 512-character snapshot cap on EVERY AX value.
        let parts = Dictionary(uniqueKeysWithValues: packet.parts.map { ($0.identifier, String($0.value.prefix(512)) as Any) })
        var errors: [String] = []
        let decoded = UIWindowMetrics.decodePayload(manifest: String(packet.manifest.prefix(512)), parts: parts, onError: { errors.append($0) })
        XCTAssertEqual(decoded?.focused, value["focused"] as? String)
        XCTAssertEqual(decoded?.scrolls.count, 100)
        XCTAssertTrue(errors.isEmpty)
    }
    func testMissingTruncatedMixedAndCorruptedPartsNeverDecode() throws {
        let packet = try UITestMetricsPayload.encode(fixture())
        let original = Dictionary(uniqueKeysWithValues: packet.parts.map { ($0.identifier, $0.value as Any) })
        for mode in 0..<4 {
            var parts = original
            let first = packet.parts[0]
            if mode == 0 { parts.removeValue(forKey: packet.parts.last!.identifier) }
            if mode == 1 { parts[first.identifier] = String(first.value.dropLast()) }
            if mode == 2 { parts[first.identifier] = "A" + first.value.dropFirst() }
            if mode == 3 {
                var newer = fixture(); newer["focused"] = "memoryText"
                parts = Dictionary(uniqueKeysWithValues: try UITestMetricsPayload.encode(newer).parts.map { ($0.identifier, $0.value as Any) })
            }
            var errors: [String] = []
            XCTAssertNil(UIWindowMetrics.decodePayload(manifest: packet.manifest, parts: parts, onError: { errors.append($0) }))
            XCTAssertEqual(errors.count, 1)
            XCTAssertTrue(errors[0].contains("rawPrefix="))
        }
    }
    func testTypeMismatchesReportTheDecoderPathAndRawPrefix() throws {
        for (key, invalid) in [("transitioning", 1 as Any), ("focusedAfterAppearance", 0 as Any),
                               ("safeArea", [true, false] as Any), ("scrolls", "bad" as Any)] {
            var value = fixture(); value[key] = invalid
            var errors: [String] = []
            XCTAssertNil(read(try UITestMetricsPayload.encode(value), errors: &errors))
            XCTAssertTrue(errors[0].contains("typeMismatch"))
            XCTAssertTrue(errors[0].contains(key))
            XCTAssertTrue(errors[0].contains("rawPrefix="))
        }
    }
    func testNonFiniteAndUnsupportedAppValuesProduceExplicitSerializationErrors() throws {
        for invalid in [Double.nan as Any, Double.infinity as Any, Date() as Any] {
            var value = fixture(); value["safeArea"] = [invalid]
            XCTAssertThrowsError(try UITestMetricsPayload.encode(value))
            do { _ = try UITestMetricsPayload.encode(value) }
            catch {
                let packet = UITestMetricsPayload.failure(error)
                XCTAssertLessThan(packet.manifest.count, 512)
                var errors: [String] = []
                XCTAssertNil(read(packet, errors: &errors))
                XCTAssertTrue(errors[0].contains("App serialization failed"))
            }
        }
    }
    private struct SurfaceNode {
        var frame: CGRect = CGRect(x: 0, y: 0, width: 440, height: 956)
        var hidden = false
        var clips = false
        var paper: [String: Any]?
        var children: [SurfaceNode] = []
    }
    private func surface(_ root: SurfaceNode) -> [String: Any]? {
        UITestPaperSurfaceSelection.first(in: root, viewport: CGRect(x: 0, y: 0, width: 440, height: 956),
            children: { $0.children }, visible: { !$0.hidden }, frame: { $0.frame }, clips: { $0.clips }, surface: { $0.paper })
    }
    private func surfaceSample(_ root: SurfaceNode, limit: Int = 2048) -> UITestPaperSurfaceSelection.Sample {
        UITestPaperSurfaceSelection.sample(in: root, viewport: CGRect(x: 0, y: 0, width: 440, height: 956),
            children: { $0.children }, visible: { !$0.hidden }, frame: { $0.frame }, clips: { $0.clips }, surface: { $0.paper }, limit: limit)
    }
    func testEmptyNativeMarkerIsUnknownUntilItReceivesThePaperProposal() {
        var marker = SurfaceNode(frame: .zero, paper: ["required": false, "key": NSNull()])
        let first = surfaceSample(SurfaceNode(children: [marker]))
        XCTAssertNil(first.value)
        XCTAssertEqual(first.emptyMarkers, 1)
        XCTAssertEqual(first.markers, 1)
        marker.frame = CGRect(x: 0, y: 0, width: 440, height: 956)
        let laidOut = surfaceSample(SurfaceNode(children: [marker]))
        XCTAssertEqual(laidOut.value?["required"] as? Bool, false)
        XCTAssertEqual(laidOut.emptyMarkers, 0)
    }
    func testSurfaceSelectionReportsHiddenClippedOffscreenAndBudgetFailures() {
        let plain = SurfaceNode(paper: ["required": false])
        let blocked = [SurfaceNode(hidden: true, children: [plain]), SurfaceNode(frame: .zero, clips: true, children: [plain]),
                       SurfaceNode(frame: CGRect(x: 700, y: 0, width: 440, height: 956), paper: ["required": false])]
        let sample = surfaceSample(SurfaceNode(children: blocked))
        XCTAssertNil(sample.value)
        XCTAssertEqual(sample.invisible, 1)
        XCTAssertEqual(sample.clipped, 1)
        XCTAssertEqual(sample.offscreenMarkers, 1)
        XCTAssertFalse(sample.exhausted)
        let limited = surfaceSample(SurfaceNode(children: [SurfaceNode(children: [plain])]), limit: 1)
        XCTAssertNil(limited.value)
        XCTAssertTrue(limited.exhausted, limited.description)
        // A dropped foreground branch must not turn the presenter's plain
        // paper into an apparent bypass of an unseen bamboo surface.
        let bamboo = SurfaceNode(paper: ["required": true, "key": "light@3.0"])
        let foreground = SurfaceNode(children: [bamboo, SurfaceNode()])
        let fallback = surfaceSample(SurfaceNode(children: [plain, foreground]), limit: 4)
        XCTAssertNil(fallback.value)
        XCTAssertTrue(fallback.exhausted, fallback.description)
    }
    func testLockedAndOtherRootPaperIsFoundThroughEmptyNonClippingWrappers() {
        let paper = SurfaceNode(paper: ["required": false, "key": NSNull()])
        // Loading, lock, recovery and the first window share RootView's paper;
        // no mainNavigation or scroll view is needed to identify that surface.
        for frame in [CGRect.zero, CGRect(x: -900, y: 0, width: 1, height: 1)] {
            let root = SurfaceNode(children: [SurfaceNode(frame: frame, children: [paper])])
            XCTAssertEqual(surface(root)?["required"] as? Bool, false)
        }
    }
    func testFrontmostSheetPaperWinsAndHiddenOrClippedBranchesCannotOverrideIt() {
        let bamboo = SurfaceNode(paper: ["required": true, "key": "light@3.0"])
        let plain = SurfaceNode(paper: ["required": false, "key": NSNull()])
        XCTAssertEqual(surface(SurfaceNode(children: [bamboo, plain]))?["required"] as? Bool, false)
        XCTAssertEqual(surface(SurfaceNode(children: [plain, bamboo]))?["key"] as? String, "light@3.0")
        let hidden = SurfaceNode(hidden: true, children: [plain])
        let clipped = SurfaceNode(frame: .zero, clips: true, children: [plain])
        let offscreen = SurfaceNode(frame: CGRect(x: 500, y: 0, width: 440, height: 956), clips: true, children: [plain])
        for blocked in [hidden, clipped, offscreen] {
            XCTAssertEqual(surface(SurfaceNode(children: [bamboo, blocked]))?["key"] as? String, "light@3.0")
        }
    }
    func testMissingOffscreenOrClippedPaperRemainsUnknown() {
        let outside = SurfaceNode(frame: CGRect(x: 500, y: 0, width: 440, height: 956), paper: ["required": false])
        XCTAssertNil(surface(SurfaceNode()))
        XCTAssertNil(surface(SurfaceNode(children: [outside])))
        let paper = SurfaceNode(frame: CGRect(x: 0, y: 500, width: 440, height: 400), paper: ["required": false])
        let clipped = SurfaceNode(frame: CGRect(x: 0, y: 0, width: 440, height: 100), clips: true, children: [paper])
        XCTAssertNil(surface(SurfaceNode(children: [clipped])))
    }
    private final class RegisteredSurfaceNode {
        weak var parent: RegisteredSurfaceNode?
        var children: [RegisteredSurfaceNode]
        var frame = CGRect(x: 0, y: 0, width: 440, height: 956)
        var hidden = false
        var clips = false
        var paper: [String: Any]?
        init(paper: [String: Any]? = nil, children: [RegisteredSurfaceNode] = []) {
            self.paper = paper; self.children = children
            for child in children { child.parent = self }
        }
    }
    private func registeredSurfaceSample(_ root: RegisteredSurfaceNode, markers: [RegisteredSurfaceNode]) -> UITestPaperSurfaceSelection.Sample {
        UITestPaperSurfaceSelection.sample(in: root, markers: markers, parent: { $0.parent },
            viewport: CGRect(x: 0, y: 0, width: 440, height: 956), children: { $0.children },
            visible: { !$0.hidden }, frame: { $0.frame }, clips: { $0.clips }, surface: { $0.paper })
    }
    func testRegisteredPaperPathsIgnoreLargeUnrelatedContentAndKeepFrontmostClipping() {
        let bamboo = RegisteredSurfaceNode(paper: ["required": true, "key": "light@3.0"])
        let plain = RegisteredSurfaceNode(paper: ["required": false, "key": NSNull()])
        let foreground = RegisteredSurfaceNode(children: [plain])
        let unrelated = RegisteredSurfaceNode(children: (0..<3000).map { _ in RegisteredSurfaceNode() })
        let root = RegisteredSurfaceNode(children: [bamboo, foreground, unrelated])
        // Registry order must not replace UIKit's back-to-front sibling order.
        let markers = [plain, bamboo]
        let sample = registeredSurfaceSample(root, markers: markers)
        XCTAssertEqual(sample.value?["required"] as? Bool, false)
        XCTAssertEqual(sample.visited, 3)
        XCTAssertFalse(sample.exhausted)
        foreground.frame = .zero
        XCTAssertEqual(registeredSurfaceSample(root, markers: markers).value?["required"] as? Bool, false)
        foreground.clips = true
        XCTAssertEqual(registeredSurfaceSample(root, markers: markers).value?["key"] as? String, "light@3.0")
        foreground.clips = false; foreground.hidden = true
        XCTAssertEqual(registeredSurfaceSample(root, markers: markers).value?["key"] as? String, "light@3.0")
    }
    func testAbsentOrDetachedRegisteredPaperDoesNotWalkContentOrBypassTheGate() {
        let root = RegisteredSurfaceNode(children: (0..<3000).map { _ in RegisteredSurfaceNode() })
        let detached = RegisteredSurfaceNode(paper: ["required": false])
        for markers in [[], [detached]] {
            let sample = registeredSurfaceSample(root, markers: markers)
            XCTAssertNil(sample.value)
            XCTAssertEqual(sample.visited, 0)
            XCTAssertFalse(sample.exhausted)
        }
    }
    func testExistingGalleryTelemetryExclusionCoversOnlyTheProbeNamespace() throws {
        let packet = try UITestMetricsPayload.encode(fixture())
        XCTAssertTrue(UIWindowMetrics.isProbeIdentifier(UITestMetricsPayload.identifier))
        XCTAssertTrue(UIWindowMetrics.isProbeIdentifier(UITestMetricsPayload.identifier + ".manifest"))
        for part in packet.parts { XCTAssertTrue(UIWindowMetrics.isProbeIdentifier(part.identifier)) }
        for identifier in ["uiTestWindowMetricsButton", "uiTestWindowMetric", "butlerAICorrectionText", "ledgerHeroLabel", "savingMode_fixed", ""] {
            XCTAssertFalse(UIWindowMetrics.isProbeIdentifier(identifier))
        }
    }
}
