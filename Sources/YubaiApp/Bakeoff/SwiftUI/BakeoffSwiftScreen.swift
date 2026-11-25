#if DEBUG && os(iOS)
  import SwiftUI

  private struct KeyStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduced
    var keypad = false
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .scaleEffect(keypad && configuration.isPressed && !reduced ? DSMotion.Press.scale : 1)
        .opacity(
          keypad && configuration.isPressed && reduced ? DSInteraction.reducedPressOpacity : 1
        )
        .animation(reduced ? nil : DSMotion.snappyAnimation, value: configuration.isPressed)
    }
  }

  private extension EnvironmentValues {
    @Entry var bakeoffTap: (String) -> Void = { _ in }
  }

  private struct PanelContent: View {
    let width: CGFloat
    let state: BakeoffFixture
    let picker: Bool
    @Environment(\.bakeoffTap) private var tap

    private func cell(_ item: BakeoffItem) -> some View {
      let weight: Font.Weight =
        item.weight == .semibold ? .semibold : item.weight == .medium ? .medium : .regular
      return ZStack {
        RoundedRectangle(cornerRadius: item.radius, style: .continuous).fill(item.fill)
          .shadow(
            color: item.id.hasPrefix("bakeoff.key.") ? BakeoffSpec.keyShadow : .clear,
            radius: DS.Shadow.key.radius, x: DS.Shadow.key.x, y: DS.Shadow.key.y)
        if item.id == "shoeBorder" {
          RoundedRectangle(cornerRadius: DS.Size.pillH / 2, style: .continuous).strokeBorder(
            DS.Color.accent, lineWidth: DS.Stroke.focus)
        }
        if let name = item.icon, let path = BakeoffIcons.vectors[name] {
          let scale = item.size / BakeoffSpec.vectorGrid
          Path(path).applying(.init(scaleX: scale, y: scale))
            .stroke(
              item.ink,
              style: .init(lineWidth: item.stroke * scale, lineCap: .round, lineJoin: .round)
            )
            .frame(width: item.size, height: item.size)
        }
        if !item.text.isEmpty {
          Text(verbatim: item.text).font(
            .system(size: item.size, weight: weight, design: item.numeric ? .rounded : .default)
          )
          .monospacedDigit().tracking(
            item.id == "bakeoff.amount"
              ? BakeoffSpec.amountTracking : item.id == "balance" ? BakeoffSpec.balanceTracking : 0
          )
          .foregroundStyle(item.ink).lineLimit(1).minimumScaleFactor(0.6)
        }
      }.frame(width: item.rect.width, height: item.rect.height).contentShape(Rectangle())
    }
    var body: some View {
      ZStack(alignment: .topLeading) {
        DS.Color.bg
        ForEach(BakeoffSpec.items(width: width, state: state, picker: picker)) { item in
          Group {
            if let label = item.label, item.id != "bakeoff.amount" {
              Button {
                tap(item.id)
              } label: {
                cell(item)
              }
              .buttonStyle(KeyStyle(keypad: item.id.hasPrefix("bakeoff.key.")))
              .accessibilityAddTraits(
                state.selected(item.id, picker: picker) ? .isSelected : []
              ).accessibilityLabel(label).accessibilityIdentifier(item.id)
            } else if item.id == "bakeoff.amount" {
              cell(item).accessibilityElement(children: .ignore).accessibilityLabel("金额")
                .accessibilityValue(item.text).accessibilityIdentifier(item.id)
            } else {
              cell(item).allowsHitTesting(false).accessibilityHidden(true)
            }
          }.position(x: item.rect.midX, y: item.rect.midY)
        }
      }.frame(width: width, height: picker ? BakeoffSpec.pickerHeight : BakeoffSpec.mainHeight)
        .clipShape(
          UnevenRoundedRectangle(
            topLeadingRadius: BakeoffSpec.sheetRadius, topTrailingRadius: BakeoffSpec.sheetRadius))
    }
  }

  @Observable private final class SheetMotion {
    var hidden = false
    var offset: CGFloat = 0
    var flight: Flight?
    @ObservationIgnored var dragOrigin: CGFloat?

    struct Flight {
      var start: CGFloat
      var target: CGFloat
      var velocity: CGFloat
      var date = Date()
      func position(_ now: Date) -> CGFloat {
        DSMotion.smooth.value(
          fromValue: start, toValue: target, initialVelocity: velocity,
          time: max(0, now.timeIntervalSince(date)))
      }
    }
    func settle(_ destination: CGFloat, velocity: CGFloat, reduced: Bool) {
      if reduced {
        offset = destination
        flight = nil
      } else {
        flight = Flight(start: offset, target: destination, velocity: velocity)
      }
    }
  }

  /// Only this modifier observes the drag offset and samples the running spring.
  private struct SheetPosition: ViewModifier {
    let motion: SheetMotion
    @Environment(\.accessibilityReduceMotion) private var reduced

    private func drag(height: CGFloat) -> some Gesture {
      DragGesture(minimumDistance: 4, coordinateSpace: .global)
        .onChanged { value in
          if motion.dragOrigin == nil {
            motion.dragOrigin = motion.flight?.position(Date()) ?? motion.offset
            motion.flight = nil
          }
          motion.offset = max(0, (motion.dragOrigin ?? 0) + value.translation.height)
        }.onEnded { value in
          motion.dragOrigin = nil
          let dismiss =
            motion.offset > height * BakeoffSpec.dismissFraction
            || (value.velocity.height > BakeoffSpec.dismissVelocity
              && motion.offset > BakeoffSpec.flickMinimumTravel)
          motion.settle(dismiss ? height : 0, velocity: value.velocity.height, reduced: reduced)
          motion.hidden = dismiss
        }
    }
    func body(content: Content) -> some View {
      TimelineView(.animation(paused: motion.flight == nil)) { tick in
        let y = motion.flight?.position(tick.date) ?? motion.offset
        content.offset(y: y)
          .simultaneousGesture(drag(height: BakeoffSpec.mainHeight))
          .allowsHitTesting(!motion.hidden || y < BakeoffSpec.mainHeight - 1)
      }
      .accessibilityHidden(motion.hidden)
      .task(id: motion.flight?.date) {
        guard let current = motion.flight else { return }
        let duration = DSMotion.smooth.settlingDuration(
          fromValue: current.start, toValue: current.target, initialVelocity: current.velocity,
          epsilon: 0.001)
        try? await Task.sleep(for: .seconds(duration))
        guard !Task.isCancelled else { return }
        motion.offset = current.target
        motion.flight = nil
      }
    }
  }

  private struct ReopenButton: View {
    let motion: SheetMotion
    @Environment(\.accessibilityReduceMotion) private var reduced

    var body: some View {
      if motion.hidden {
        Button {
          motion.hidden = false
          motion.offset = motion.flight?.position(Date()) ?? motion.offset
          motion.settle(0, velocity: 0, reduced: reduced)
        } label: {
          Text("再开").frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(KeyStyle())
          .accessibilityIdentifier("bakeoff.reopen")
      }
    }
  }

  private struct SheetPanels: View {
    let width: CGFloat
    let motion: SheetMotion
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var state = BakeoffFixture()
    @State private var hits = 0

    private func tap(_ id: String) {
      if id == "bakeoff.close" {
        motion.hidden = true
        motion.settle(BakeoffSpec.mainHeight, velocity: 0, reduced: reduced)
        return
      }
      if id.hasPrefix("bakeoff.key.") { hits += 1 }
      var next = state
      next.tap(id)
      let moves = next.tab != state.tab || (next.mode == "cats") != (state.mode == "cats")
      withAnimation(moves && !reduced ? DSMotion.smoothAnimation : nil) { state = next }
    }
    var body: some View {
      ZStack(alignment: .bottom) {
        PanelContent(width: width, state: state, picker: false)
          .accessibilityElement(children: .contain).accessibilityHidden(state.mode == "cats")
          .allowsHitTesting(state.mode != "cats")
        if state.mode == "cats" {
          DS.Color.scrim.opacity(motion.hidden ? 0 : 1).onTapGesture { tap("bakeoff.back") }
          PanelContent(width: width, state: state, picker: true).transition(
            reduced ? .opacity : .move(edge: .bottom))
        }
      }.accessibilityElement(children: .contain).accessibilityIdentifier("bakeoff.sheet")
        .environment(\.bakeoffTap, tap)
        .sensoryFeedback(DSMotion.Press.haptic, trigger: hits)
    }
  }

  struct BakeoffSwiftScreen: View {
    @State private var motion = SheetMotion()

    var body: some View {
      GeometryReader { geo in
        ZStack(alignment: .bottom) {
          BakeoffSpec.base.overlay(DS.Color.scrim)
          ReopenButton(motion: motion)
          SheetPanels(width: geo.size.width, motion: motion)
            .modifier(SheetPosition(motion: motion))
        }
      }.ignoresSafeArea()
    }
  }

  #Preview { BakeoffSwiftScreen() }
  #Preview("深色") { BakeoffSwiftScreen().preferredColorScheme(.dark) }
#endif
