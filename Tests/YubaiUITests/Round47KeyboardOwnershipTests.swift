import XCTest

final class Round47KeyboardOwnershipTests: XCTestCase {
    private struct Node {
        var id: String
        var kind = "other"
        var children: [Node] = []
    }
    private func roots(_ node: Node) -> [String] {
        UIKeyboardOwnership.roots(in: node, children: { $0.children }, isKeyboard: { $0.kind == "keyboard" },
            isWindow: { $0.kind == "window" }, isAppPage: { $0.id.hasPrefix("rootPage_") || $0.id == "uiTestWindowMetrics" },
            isIntroduction: { $0.id == "UIContinuousPathIntroductionView" }).map(\.id)
    }
    func testKeyboardAndContinueIntroductionAreExcludedInASharedAppWindow() {
        let window = Node(id: "app", kind: "window", children: [Node(id: "rootPage_ledger"),
            Node(id: "keyboard", kind: "keyboard", children: [Node(id: "Continue", kind: "button")]),
            Node(id: "UIContinuousPathIntroductionView", children: [Node(id: "Continue", kind: "button")])])
        XCTAssertEqual(roots(window), ["keyboard", "UIContinuousPathIntroductionView"])
    }
    func testDedicatedKeyboardWindowAlsoExcludesItsAssistantSiblings() {
        let app = Node(id: "app", children: [Node(id: "content", kind: "window", children: [Node(id: "rootPage_ledger")]),
            Node(id: "input", kind: "window", children: [Node(id: "keyboard", kind: "keyboard"), Node(id: "assistant", kind: "button")])])
        XCTAssertEqual(roots(app), ["input"])
    }
    func testAnAppControlNamedContinueIsStillAudited() {
        XCTAssertTrue(roots(Node(id: "app", kind: "window", children: [Node(id: "rootPage_ledger"), Node(id: "Continue", kind: "button")])).isEmpty)
    }
    func testNoKeyboardDoesNotExcludeASheetOrItsControls() {
        XCTAssertTrue(roots(Node(id: "app", kind: "window", children: [Node(id: "sheet", children: [Node(id: "butlerAICorrectionSave", kind: "button")])])).isEmpty)
    }
    func testSheetProbeKeepsAppControlsAuditedWhenTheBackgroundRootIsHidden() {
        let app = Node(id: "app", kind: "window", children: [Node(id: "sheet", children: [
            Node(id: "uiTestWindowMetrics"), Node(id: "butlerAICorrectionSave", kind: "button")]),
            Node(id: "keyboard", kind: "keyboard")])
        XCTAssertEqual(roots(app), ["keyboard"])
    }
}
