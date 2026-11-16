import Foundation

/// System ownership comes from the snapshot tree, never a translated key
/// label or a rectangle that could also contain an app control.
enum UIKeyboardOwnership {
    static func roots<Node>(in root: Node, children: (Node) -> [Node], isKeyboard: (Node) -> Bool,
                            isWindow: (Node) -> Bool, isAppPage: (Node) -> Bool,
                            isIntroduction: (Node) -> Bool) -> [Node] {
        func contains(_ node: Node, matching predicate: (Node) -> Bool) -> Bool {
            predicate(node) || children(node).contains { contains($0, matching: predicate) }
        }
        func collect(_ node: Node) -> [Node] {
            // The input assistant can be a sibling of Keyboard in a dedicated
            // window. The first-use introduction can instead share our window.
            if isKeyboard(node) || isIntroduction(node) ||
                (isWindow(node) && contains(node, matching: isKeyboard) && !contains(node, matching: isAppPage)) { return [node] }
            return children(node).flatMap(collect)
        }
        return collect(root)
    }
}
