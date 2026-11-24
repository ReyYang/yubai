// 由 scripts/generate-design-tokens.py 从 design-tokens.json 生成，不要手改。
import SwiftUI

enum DSMotion {
    struct SpringToken {
        let mass: Double
        let stiffness: Double
        let damping: Double
        var spring: Spring { Spring(mass: mass, stiffness: stiffness, damping: damping) }
    }
    /// 按压、切换、勾选、箭头旋转。
    static let snappy = Spring(mass: 1, stiffness: 300, damping: 22)
    static let snappyToken = SpringToken(mass: 1, stiffness: 300, damping: 22)
    static let snappyAnimation: Animation = .spring(snappy)
    /// 面板、位移、分段滑块、列表入场（零回弹）。
    static let smooth = Spring(mass: 1, stiffness: 200, damping: 28)
    static let smoothToken = SpringToken(mass: 1, stiffness: 200, damping: 28)
    static let smoothAnimation: Animation = .spring(smooth)
    /// 常规状态过渡：颜色、展开收起、数字换位、柱子长出。
    static let standard = Spring(mass: 1, stiffness: 130, damping: 14)
    static let standardToken = SpringToken(mass: 1, stiffness: 130, damping: 14)
    static let standardAnimation: Animation = .spring(standard)
    /// 完成、弹出反馈：记下成功、浮动卡出现。
    static let bouncy = Spring(mass: 1, stiffness: 180, damping: 12)
    static let bouncyToken = SpringToken(mass: 1, stiffness: 180, damping: 12)
    static let bouncyAnimation: Animation = .spring(bouncy)

    static func interpolating(_ s: SpringToken) -> Animation {
        .interpolatingSpring(mass: s.mass, stiffness: s.stiffness, damping: s.damping, initialVelocity: 0)
    }

    enum Press {
        static let scale: CGFloat = 0.97
        static let animation = snappyAnimation
        static let haptic: SensoryFeedback = .impact(weight: .light)
    }

    enum Role: CaseIterable {
        /// 分段 / 类型标签的滑块。
        case segmentedThumb
        /// 抽屉展开收起。
        case accordion
        /// 抽屉箭头转向。
        case chevronRotate
        /// 账单行首次出现：上移 8pt 淡入，每行晚 0.04s 开始（只是起步延迟，不是时长）。
        case rowEnter
        /// 日线柱首次长出。
        case barGrow
        /// 数字变化：.contentTransition(.numericText())，只换变了的位。
        case number
        /// 浮动账单卡出现（缩放 0.96 → 1 + 淡入）。
        case floatCard
        /// 底部弹窗用系统 .sheet 自带弹簧，不自定义。
        case sheet

        var animation: Animation? {
            switch self {
            case .segmentedThumb: smoothAnimation
            case .accordion: standardAnimation
            case .chevronRotate: snappyAnimation
            case .rowEnter: smoothAnimation
            case .barGrow: standardAnimation
            case .number: standardAnimation
            case .floatCard: bouncyAnimation
            case .sheet: nil
            }
        }
        var staggerDelay: Double {
            switch self {
            case .rowEnter: 0.04
            case .barGrow: 0.012
            default: 0
            }
        }
        var offsetY: CGFloat {
            switch self {
            case .rowEnter: 8
            default: 0
            }
        }
        var initialScale: CGFloat {
            switch self {
            case .floatCard: 0.96
            default: 1
            }
        }
    }

    enum Property { case movement, opacity }
    static let reduceMotionAnimation: Animation = .spring(smooth)
    static let reduceMotionAllowed = ["opacity"]
    /// Reduced motion: callers MUST apply the opacity animation to opacity only.
    /// Movement, scale, rotation and numeric replacement must jump immediately.
    /// Sheet returns nil because the native presenter owns its spring.
    static func animation(_ role: Role, reduceMotion: Bool) -> Animation? {
        animation(role, reduceMotion: reduceMotion, property: .movement)
    }
    static func animation(_ role: Role, reduceMotion: Bool, property: Property) -> Animation? {
        if reduceMotion { return property == .opacity ? reduceMotionAnimation : nil }
        return role.animation
    }

    enum Haptic {
        static let save: SensoryFeedback = .success
        static let overspend: SensoryFeedback = .warning
        static let toggle: SensoryFeedback = .selection
    }

    struct LoopToken {
        let phases: [Double]
        let property: String
        let spring: Spring
        let hold: Double
        var animation: Animation { .spring(spring).delay(hold) }
    }
    enum Loop {
        /// AI 正在想、读取中。
        static let breathe = LoopToken(phases: [1.0, 0.55], property: "opacity", spring: smooth, hold: 0.6)
        /// 骨架屏扫光。
        static let shimmer = LoopToken(phases: [-1.0, 1.0], property: "offsetX", spring: smooth, hold: 0.4)
    }
}
