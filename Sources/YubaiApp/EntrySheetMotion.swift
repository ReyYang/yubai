import SwiftUI
#if DEBUG
import OSLog
#endif

struct SpringFlight {
    let start: CGFloat
    let target: CGFloat
    let velocity: CGFloat
    let date = Date()

    func position(at now: Date) -> CGFloat {
        DSMotion.smooth.value(fromValue: start, toValue: target,
                              initialVelocity: velocity, time: max(0, now.timeIntervalSince(date)))
    }

    var duration: TimeInterval {
        DSMotion.smooth.settlingDuration(fromValue: start, toValue: target, initialVelocity: velocity, epsilon: EntrySpec.springEpsilon)
    }
}

@MainActor @Observable final class EntrySheetMotion {
    private(set) var offset: CGFloat = 0
    private(set) var flight: SpringFlight?
    private(set) var opacity = 1.0
    private(set) var closing = false
    @ObservationIgnored private var dragOrigin: CGFloat?
    @ObservationIgnored private var sealed = false
    @ObservationIgnored private var height: CGFloat = 0
    @ObservationIgnored private var started: Bool
    @ObservationIgnored private var pendingCompletion: (() -> Void)?
    @ObservationIgnored private var fadeTask: Task<Void, Never>?

    init(settled: Bool) {
        started = settled
        opacity = settled ? 1 : 0
    }

    func updateHeight(_ height: CGFloat, reduced: Bool) {
        self.height = height
        guard !started, height > 0 else { return }
        started = true
        if reduced {
            withAnimation(DSMotion.reduceMotionAnimation.speed(EntrySpec.fadeSpeed)) { opacity = 1 }
        } else {
            offset = height
            opacity = 1
            spring(to: 0, velocity: 0)
        }
    }

    func position(at date: Date) -> CGFloat { flight?.position(at: date) ?? offset }

    /// Spec-Gestures: 遮罩透明度 = 1 − y / 520. One denominator while pulled and after release,
    /// so letting go never makes the scrim jump; a sheet shorter than 520 fades out by its own height.
    func scrimProgress(at date: Date) -> Double {
        guard height > 0 else { return 1 }
        let y = max(0, position(at: date))
        return Double(1 - min(1, y / min(height, EntrySpec.scrimFadeDistance)))
    }

    func drag(_ value: DragGesture.Value) {
        guard !sealed else { return }
        if dragOrigin == nil {
            EntryRenderDiagnostics.mark("drag")
            fadeTask?.cancel()
            pendingCompletion = nil
            if opacity != 1 { withAnimation(nil) { opacity = 1 } }
            let current = position(at: .now)
            dragOrigin = current
            offset = current
            flight = nil
            closing = false
        }
        let movement = (dragOrigin ?? 0) + value.translation.height
        // Spec-Gestures: 向下 1:1；向上橡皮筋 y = 40 × (1 − 1 / (1 + d / 120)).
        offset = movement >= 0 ? movement
            : -EntrySpec.rubberLimit * (1 - 1 / (1 + -movement / EntrySpec.rubberScale))
    }

    func willDismiss(_ value: DragGesture.Value) -> Bool {
        dragOrigin != nil && (offset > EntrySpec.dismissDistance || value.velocity.height > EntrySpec.dismissVelocity)
    }

    func release(_ value: DragGesture.Value, reduced: Bool, onClose: @escaping () -> Void) {
        guard dragOrigin != nil else { return }
        let dismiss = willDismiss(value)
        dragOrigin = nil
        let speed = value.velocity.height
        if dismiss {
            close(reduced: reduced, velocity: speed, onClose: onClose)
        } else if reduced {
            offset = 0
            EntryRenderDiagnostics.mark("settled")
        } else {
            spring(to: 0, velocity: offset < 0 ? 0 : speed)
        }
    }

    /// A drag the system cancelled never reaches `release`; go back to rest from where it is.
    func settleIfDragging(reduced: Bool) {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        if reduced { offset = 0 } else { spring(to: 0, velocity: 0) }
    }

    func close(reduced: Bool, velocity: CGFloat = 0, sealed: Bool = false, onClose: @escaping () -> Void) {
        guard !closing else { return }
        dragOrigin = nil
        closing = true
        self.sealed = sealed
        pendingCompletion = onClose
        if reduced {
            flight = nil
            withAnimation(DSMotion.reduceMotionAnimation.speed(EntrySpec.fadeSpeed)) { opacity = 0 }
            fadeTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(EntrySpec.reduceMotionDuration)) }
                catch { return }
                self?.completeClose()
            }
        } else {
            spring(to: height + EntrySpec.dismissOvershoot, velocity: velocity)
        }
    }

    func duration(of current: SpringFlight) -> TimeInterval {
        closing ? min(current.duration, EntrySpec.saveCloseDuration) : current.duration
    }

    func finish(_ current: SpringFlight, onClose: () -> Void) {
        guard flight?.date == current.date else { return }
        offset = current.target
        flight = nil
        if closing { completeClose(fallback: onClose) }
    }

    private func completeClose(fallback: () -> Void = {}) {
        let action = pendingCompletion
        pendingCompletion = nil
        if let action { action() } else { fallback() }
    }

    private func spring(to target: CGFloat, velocity: CGFloat) {
        offset = position(at: .now)
        EntryRenderDiagnostics.mark("flight")
        flight = SpringFlight(start: offset, target: target, velocity: velocity)
    }
}

struct EntryScrimView: View {
    let motion: EntrySheetMotion
    let color: Color
    let close: () -> Void

    var body: some View {
        TimelineView(.animation(paused: motion.flight == nil)) { tick in
            let _ = EntryRenderDiagnostics.hit(.scrim)
            color.opacity(motion.scrimProgress(at: tick.date) * motion.opacity)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
        }
    }
}

/// The content is built before this modifier. Only the transform samples motion.
struct EntrySheetPositionModifier: ViewModifier {
    let motion: EntrySheetMotion
    let reduced: Bool
    let onClose: () -> Void
    var tracksOverview = false
    /// What shows under the sheet when it is pulled above its rest position.
    var fill = DS.Color.tray

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: motion.flight == nil)) { tick in
            let _ = EntryRenderDiagnostics.hit(.sheetTransform)
            let _ = tracksOverview ? OverviewRenderCounts.hit("overviewSheetTransform") : ()
            let y = motion.position(at: tick.date)
            content
                .offset(y: y)
                .background(alignment: .bottom) {
                    if y < 0 { fill.frame(height: -y).allowsHitTesting(false) }
                }
                .opacity(motion.opacity)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
            motion.updateHeight($0, reduced: reduced)
        }
        .task(id: motion.flight?.date) {
            guard let flight = motion.flight else { return }
            do { try await Task.sleep(for: .seconds(motion.duration(of: flight))) }
            catch { return }
            EntryRenderDiagnostics.mark("settling")
            motion.finish(flight, onClose: onClose)
            // Read the boundary separately from the spring frames.
            await Task.yield()
            EntryRenderDiagnostics.mark("settled")
        }
    }
}

struct EntryTactileButtonStyle: ButtonStyle {
    var haptic = DSMotion.Press.haptic

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(EntryPressEffect(pressed: configuration.isPressed, haptic: haptic))
    }
}

struct EntryPressEffect: ViewModifier {
    let pressed: Bool
    let haptic: SensoryFeedback
    @Environment(\.accessibilityReduceMotion) private var reduced

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .scaleEffect(!reduced && pressed ? DSMotion.Press.scale : 1)
            .opacity(reduced && pressed ? DSInteraction.reducedPressOpacity : 1)
            .animation(reduced ? DSMotion.reduceMotionAnimation : DSMotion.Press.animation, value: pressed)
            .sensoryFeedback(haptic, trigger: pressed) { _, pressed in pressed }
    }
}

@MainActor enum EntryRenderDiagnostics {
    enum Part: String, CaseIterable {
        case sheetBody, amountBlock, caret, categoryRow, subRow, pillsRow, effectLine, keypad, scrim, sheetTransform, categoryPanel
    }

    #if DEBUG
    private static let enabled = ProcessInfo.processInfo.arguments.contains("-YubaiLogRenderCounts")
    private static let logger = Logger(subsystem: "app.yubai.personal", category: "EntryRenderCounts")
    private static var counts: [Part: Int] = [:]
    private static var baseline: [Part: Int] = [:]
    private static var phase = "initial"
    #endif

    static func hit(_ part: Part) {
        #if DEBUG
        if enabled { counts[part, default: 0] += 1 }
        #endif
    }

    static func mark(_ next: String) {
        #if DEBUG
        guard enabled else { return }
        let delta = Part.allCases.map { "\($0.rawValue)=\(counts[$0, default: 0] - baseline[$0, default: 0])" }
        let message = "YubaiEntryRender \(phase) → \(next) \(delta.joined(separator: " "))"
        logger.notice("\(message, privacy: .public)")
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        baseline = counts
        phase = next
        #endif
    }
}
