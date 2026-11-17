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
    func testReturnOnlyHandoffPreservesTheCompletePurpose() {
        // Run 13 submitted "外卖\n", then "\n". Both keyboard cycles keep 外卖;
        // the old contains("") predicate failed for every possible field value.
        XCTAssertFalse("外卖".contains("\n".trimmingCharacters(in: .newlines)))
        XCTAssertTrue(UIFieldTextRetention.matches("外卖", before: "外卖", typed: "\n"))
        for changed in ["", "外", "卖", "外卖外卖", "外卖\n"] {
            XCTAssertFalse(UIFieldTextRetention.matches(changed, before: "外卖", typed: "\n"), changed)
        }
    }
    func testReturnOnlyHandoffRequiresReadableBeforeAndAfterValues() {
        XCTAssertTrue(UIFieldTextRetention.matches("", before: "", typed: "\n"))
        XCTAssertFalse(UIFieldTextRetention.matches(nil, before: "外卖", typed: "\n"))
        XCTAssertFalse(UIFieldTextRetention.matches("外卖", before: nil, typed: "\n"))
        XCTAssertFalse(UIFieldTextRetention.matches(nil, before: nil, typed: "\n"))
    }
    func testTypedChineseLatinAndSpacesMustStillBeRetainedInFull() {
        for typed in ["外卖\n", "咖啡", "long purpose\n", " 周四是和同事拼单 "] {
            let inserted = typed.trimmingCharacters(in: .newlines)
            XCTAssertTrue(UIFieldTextRetention.matches(inserted, before: "", typed: typed))
            XCTAssertFalse(UIFieldTextRetention.matches(String(inserted.dropFirst()), before: "", typed: typed))
            XCTAssertFalse(UIFieldTextRetention.matches(String(inserted.dropLast()), before: "", typed: typed))
            XCTAssertFalse(UIFieldTextRetention.matches(nil, before: "", typed: typed))
        }
    }
}
