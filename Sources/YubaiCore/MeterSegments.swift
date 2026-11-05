/// Amounts and proportions for the available-cash composition bar, in cents.
public struct HeroBarSegments: Equatable, Sendable {
    public let needs: Int64
    public let cash: Int64
    public let isOverspent: Bool
    public let leadingAmount: Int64
    public let trailingAmount: Int64

    public init(available: Int64, payable: Int64, reserved: Int64) {
        needs = payable + reserved
        cash = available + needs
        isOverspent = available <= 0
        leadingAmount = isOverspent ? max(0, cash) : available
        trailingAmount = isOverspent ? abs(available) : max(0, needs)
    }

    public var leadingFraction: Double { fraction(leadingAmount) }
    public var trailingFraction: Double { fraction(trailingAmount) }

    private func fraction(_ amount: Int64) -> Double {
        let total = Double(leadingAmount) + Double(trailingAmount)
        return total > 0 ? Double(amount) / total : 0
    }
}

/// Progress remains clamped unless the caller explicitly displays over-limit usage.
public struct SavingBarSegments: Equatable, Sendable {
    public let filledFraction: Double
    public let overflowFraction: Double

    public init(ratio: Double, showsOvershoot: Bool = false) {
        if showsOvershoot && ratio > 1 {
            filledFraction = ratio.isFinite ? 1 / ratio : 0
            overflowFraction = 1 - filledFraction
        } else {
            filledFraction = min(1, max(0, ratio))
            overflowFraction = 0
        }
    }
}
