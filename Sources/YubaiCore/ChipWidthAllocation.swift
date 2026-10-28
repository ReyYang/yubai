import Foundation

/// Single-row widths with a shared cap; shorter items keep their natural width.
public enum ChipWidthAllocation {
    public static func widths(naturalWidths: [CGFloat], availableWidth: CGFloat, spacing: CGFloat) -> [CGFloat] {
        guard !naturalWidths.isEmpty else { return [] }
        let gaps = CGFloat(naturalWidths.count - 1) * spacing
        var remaining = max(0, availableWidth - gaps)
        guard naturalWidths.reduce(0, +) > remaining else { return naturalWidths }

        // Reserve small items first, then share the remaining width equally.
        // Sorting finds the cap only; the returned widths keep the input order.
        for (index, width) in naturalWidths.sorted().enumerated() {
            let cap = remaining / CGFloat(naturalWidths.count - index)
            if width >= cap { return naturalWidths.map { min($0, cap) } }
            remaining -= width
        }
        return naturalWidths
    }
}
