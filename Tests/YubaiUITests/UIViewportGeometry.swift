import Foundation

/// Accessibility keeps a row's full frame when a native scroll view clips it.
/// Use the visible portion for overlaps, and the native viewport for structure.
enum UIViewportGeometry {
    /// A fixed owner does not cover its own children. Scroll content still
    /// clears every other fixed region, across the full width of the page.
    static func fixedOcclusions(_ regions: [(id: String, frame: CGRect)], owners: [String],
                                hasScrollAncestors: Bool, window: CGRect) -> [CGRect] {
        guard hasScrollAncestors else { return [] }
        return regions.filter { !owners.contains($0.id) }.map {
            // A toast owns its internal message scroll. Page rows must move
            // above it, including rows initially BELOW its body: AX can expose
            // a full-screen scroll frame and call a partly clipped button
            // hittable, then send the tap to its off-viewport center (run 7's
            // soft-line mode at y=907.8). There is no usable lane below a toast.
            let gap: CGFloat = $0.id == "toastBody" ? 12 : 0
            let bottom = $0.id == "toastBody" ? max(window.maxY, $0.frame.maxY) : $0.frame.maxY
            return CGRect(x: window.minX, y: $0.frame.minY - gap, width: window.width, height: bottom - $0.frame.minY + gap)
        }
    }
    /// Ancestors are the target's actual snapshot scroll ancestors, outermost
    /// first. Native hittability owns occlusion; the structural gallery audit
    /// separately rejects page chrome overlapping a scroll viewport.
    static func revealed(exists: Bool, enabled: Bool, hittable: Bool, staticText: Bool = false,
                         frame: CGRect, scrollAncestors: [CGRect], keyboards: [CGRect] = [], occlusions: [CGRect] = []) -> Bool {
        guard exists, !frame.isEmpty, !frame.isNull, !frame.isInfinite,
              staticText || (enabled && hittable),
              scrollAncestors.allSatisfy({ $0.insetBy(dx: -0.5, dy: -0.5).contains(frame) }) else { return false }
        guard !occlusions.contains(where: { overlaps(frame, $0) }) else { return false }
        guard let inner = scrollAncestors.last else { return true }
        return visibleParts(inner, ancestors: [], excluding: keyboards + occlusions).contains {
            $0.insetBy(dx: -0.5, dy: -0.5).contains(frame)
        }
    }

    /// Editing fields and the app keypad require this separately. Other fixed
    /// controls (for example a menu above a keyboard) use native hittability.
    static func keyboardClears(_ frame: CGRect, keyboards: [CGRect]) -> Bool {
        !keyboards.contains { overlaps(frame, $0) }
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
    static func isProbeIdentifier(_ identifier: String) -> Bool {
        identifier == probeIdentifier || identifier.hasPrefix(probeIdentifier + ".")
    }
    struct BambooSurface: Decodable, CustomStringConvertible {
        let required: Bool
        let key: String?
        var description: String { "required=\(required) key=\(key ?? "none")" }
    }
    struct Scroll: Decodable {
        let identifier: String
        let frame: [CGFloat]
        let remainingDown: CGFloat
        let remainingUp: CGFloat
        var panPoints: [[CGFloat]]? = nil
        var rectangle: CGRect { UIWindowMetrics.rectangle(frame) }
        var panOrigins: [CGPoint]? { panPoints.map { $0.filter { $0.count == 2 }.map { CGPoint(x: $0[0], y: $0[1]) } } }
    }
    struct Bamboo: Decodable, CustomStringConvertible {
        struct Failure: Decodable {
            let key: String
            let stage: String
            let attempt: Int
        }
        let ready: [String]
        let renders: Int
        let mainRenders: Int
        let activeRenders: Int
        let maxConcurrentRenders: Int
        let pending: Int
        let pendingKeys: [String]
        let failed: [String]
        let failedStages: [String: String]
        let lastFailure: Failure?

        var hasFailure: Bool { mainRenders != 0 || maxConcurrentRenders > 1 || !failed.isEmpty || lastFailure != nil }
        var isReady: Bool {
            let light = Set(ready.filter { $0.hasPrefix("light@") }.map { String($0.dropFirst(6)) })
            let dark = Set(ready.filter { $0.hasPrefix("dark@") }.map { String($0.dropFirst(5)) })
            return !hasFailure && activeRenders == 0 && maxConcurrentRenders == 1 &&
                pending == 0 && pendingKeys.isEmpty && !light.isEmpty && light == dark &&
                ready.count == light.count * 2 && renders == ready.count
        }
        var description: String {
            let failure = lastFailure.map { "key=\($0.key),stage=\($0.stage),attempt=\($0.attempt)" } ?? "none"
            return "ready=\(ready) pending=\(pending) pendingKeys=\(pendingKeys) failed=\(failed) " +
                "failedStages=\(failedStages) renders=\(renders) mainRenders=\(mainRenders) " +
                "activeRenders=\(activeRenders) maxConcurrentRenders=\(maxConcurrentRenders) lastFailure={\(failure)}"
        }
    }
    let safeArea: [CGFloat]
    let transitioning: Bool
    let focused: String
    var focusedAfterAppearance: Bool? = nil
    let scrolls: [Scroll]
    var bamboo: Bamboo? = nil
    var bambooSurface: BambooSurface? = nil
    var activeTransitions: [String]? = nil
    var paperDiagnostics: String? = nil
    var inputFocusEvents: [String]? = nil
    var focusedHost: String? = nil
    var nativeSheetFrame: [CGFloat]? = nil
    var safeRectangle: CGRect { Self.rectangle(safeArea) }
    static func decode(_ value: Any?, onError: (String) -> Void = { print($0) }) -> Self? {
        do { return try JSONDecoder().decode(Self.self, from: rawData(value)) }
        catch { onError(diagnostic(error, raw: value)); return nil }
    }
    /// Reassemble only parts of the manifest's generation, from ONE snapshot.
    /// Missing/truncated/mixed samples fail; no cached/default geometry escapes.
    static func decodePayload(manifest value: Any?, parts: [String: Any], onError: (String) -> Void = { print($0) }) -> Self? {
        var raw = value
        do {
            struct Manifest: Decodable {
                let version: Int?
                let checksum: String?
                let bytes: Int?
                let parts: Int?
                let error: String?
            }
            let manifest = try JSONDecoder().decode(Manifest.self, from: rawData(value))
            if let error = manifest.error { throw PayloadError.invalid("App serialization failed: " + error) }
            guard manifest.version == 1, let checksum = manifest.checksum,
                  let count = manifest.parts, count > 0, count <= 4096, let length = manifest.bytes, length > 0 else {
                throw PayloadError.invalid("Invalid window metrics manifest")
            }
            let encoded = try (0..<count).map { index -> String in
                let key = probeIdentifier + "." + checksum + "." + String(index)
                guard let part = parts[key] as? String, !part.isEmpty, part.utf8.count <= 400 else {
                    throw PayloadError.invalid("Missing/invalid window metrics part: " + key)
                }
                return part
            }.joined()
            guard let data = Data(base64Encoded: encoded), data.count == length else {
                throw PayloadError.invalid("Truncated window metrics payload; expected \(length) bytes")
            }
            raw = String(decoding: data, as: UTF8.self)
            let actual = String(data.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }, radix: 16)
            guard actual == checksum else { throw PayloadError.invalid("Window metrics checksum mismatch") }
            return try JSONDecoder().decode(Self.self, from: data)
        } catch { onError(diagnostic(error, raw: raw)); return nil }
    }
    private enum PayloadError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String { switch self { case .invalid(let message): return message } }
    }
    private static func rawData(_ value: Any?) throws -> Data {
        guard let value = value as? String else { throw PayloadError.invalid("Window metrics value is not a String: \(String(describing: value))") }
        return Data(value.utf8)
    }
    private static func diagnostic(_ error: Error, raw: Any?) -> String {
        let value = (raw as? String) ?? String(describing: raw)
        return "UI-WINDOW-METRICS decode failed: \(error); rawLength=\(value.count) rawPrefix=\(String(value.prefix(300)))"
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
