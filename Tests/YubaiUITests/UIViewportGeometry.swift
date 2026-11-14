import Foundation

/// Accessibility keeps a row's full frame when a native scroll view clips it.
/// Use the visible portion for overlaps, and the native viewport for structure.
enum UIViewportGeometry {
    /// Ancestors are the target's actual snapshot scroll ancestors, outermost
    /// first. Native hittability owns occlusion; the structural gallery audit
    /// separately rejects page chrome overlapping a scroll viewport.
    static func revealed(exists: Bool, enabled: Bool, hittable: Bool, staticText: Bool = false,
                         frame: CGRect, scrollAncestors: [CGRect], keyboards: [CGRect] = []) -> Bool {
        guard exists, !frame.isEmpty, !frame.isNull, !frame.isInfinite,
              staticText || (enabled && hittable),
              scrollAncestors.allSatisfy({ $0.insetBy(dx: -0.5, dy: -0.5).contains(frame) }) else { return false }
        guard let inner = scrollAncestors.last else { return true }
        return visibleParts(inner, ancestors: [], excluding: keyboards).contains {
            $0.insetBy(dx: -0.5, dy: -0.5).contains(frame)
        }
    }

    static func clipped(_ frame: CGRect, to ancestors: [CGRect]) -> CGRect {
        ancestors.reduce(frame) { $0.intersection($1) }
    }

    static func overlaps(_ first: CGRect, _ second: CGRect) -> Bool {
        let intersection = first.intersection(second)
        return !intersection.isNull && intersection.width > 0.5 && intersection.height > 0.5
    }

    /// Native navigation owns every touch in its rectangle. Preserve all
    /// remaining pieces, including a control beside a non-full-width region.
    static func visibleParts(_ frame: CGRect, ancestors: [CGRect], excluding regions: [CGRect]) -> [CGRect] {
        let clipped = clipped(frame, to: ancestors)
        guard !clipped.isNull, !clipped.isEmpty else { return [] }
        return regions.reduce([clipped]) { parts, region in
            parts.flatMap { part -> [CGRect] in
                let cut = part.intersection(region)
                guard !cut.isNull, !cut.isEmpty else { return [part] }
                return [CGRect(x: part.minX, y: part.minY, width: part.width, height: cut.minY - part.minY),
                        CGRect(x: part.minX, y: cut.maxY, width: part.width, height: part.maxY - cut.maxY),
                        CGRect(x: part.minX, y: cut.minY, width: cut.minX - part.minX, height: cut.height),
                        CGRect(x: cut.maxX, y: cut.minY, width: part.maxX - cut.maxX, height: cut.height)]
                    .filter { !$0.isEmpty && !$0.isNull }
            }
        }
    }

    static func canClearToast(_ control: CGRect, viewport: CGRect, toast: CGRect, remainingDown: CGFloat, gap: CGFloat = 12) -> Bool {
        let top = viewport.minY, bottom = min(viewport.maxY, toast.minY - gap)
        return bottom - top >= control.height - 0.5 && control.maxY - remainingDown <= bottom + 0.5
    }
}

/// Values come from the app's scripted-only UIKit probe, in screen points.
struct UIWindowMetrics: Decodable {
    static let probeIdentifier = "uiTestWindowMetrics"
    struct Scroll: Decodable {
        let identifier: String
        let frame: [CGFloat]
        let remainingDown: CGFloat
        let remainingUp: CGFloat
        var rectangle: CGRect { UIWindowMetrics.rectangle(frame) }
    }
    let safeArea: [CGFloat]
    let transitioning: Bool
    let focused: String
    let scrolls: [Scroll]
    var safeRectangle: CGRect { Self.rectangle(safeArea) }
    static func decode(_ value: Any?) -> Self? {
        guard let value = value as? String, let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    static func rectangle(_ values: [CGFloat]) -> CGRect {
        guard values.count == 4 else { return .null }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
    func scroll(matching frame: CGRect) -> Scroll? {
        scrolls.first {
            let actual = $0.rectangle
            return abs(actual.minX - frame.minX) < 1 && abs(actual.minY - frame.minY) < 1 &&
                abs(actual.width - frame.width) < 1 && abs(actual.height - frame.height) < 1
        }
    }
}
