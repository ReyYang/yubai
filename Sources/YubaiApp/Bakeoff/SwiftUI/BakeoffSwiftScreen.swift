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

  struct BakeoffSwiftScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var state = BakeoffFixture()
    @State private var hidden = false
    @State private var offset: CGFloat = 0
    @State private var dragOrigin: CGFloat?
    @State private var flight: Flight?
    @State private var hits = 0

    private struct Flight {
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
    private func settle(_ destination: CGFloat, velocity: CGFloat) {
      if reduced {
        offset = destination
        flight = nil
      } else {
        flight = Flight(start: offset, target: destination, velocity: velocity)
      }
    }
    private func drag(height: CGFloat) -> some Gesture {
      DragGesture(minimumDistance: 4, coordinateSpace: .global)
        .onChanged { value in
          if dragOrigin == nil {
            dragOrigin = flight?.position(Date()) ?? offset
            flight = nil
          }
          offset = max(0, (dragOrigin ?? 0) + value.translation.height)
        }.onEnded { value in
          dragOrigin = nil
          let dismiss =
            offset > height * BakeoffSpec.dismissFraction
            || (value.velocity.height > BakeoffSpec.dismissVelocity
              && offset > BakeoffSpec.flickMinimumTravel)
          settle(dismiss ? height : 0, velocity: value.velocity.height)
          hidden = dismiss
        }
    }
    private func tap(_ id: String) {
      if id == "bakeoff.close" {
        hidden = true
        settle(BakeoffSpec.mainHeight, velocity: 0)
        return
      }
      if id.hasPrefix("bakeoff.key.") { hits += 1 }
      var next = state
      next.tap(id)
      let moves = next.tab != state.tab || (next.mode == "cats") != (state.mode == "cats")
      withAnimation(moves && !reduced ? DSMotion.smoothAnimation : nil) { state = next }

    }
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
    private func panel(width: CGFloat, picker: Bool) -> some View {
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
    var body: some View {
      GeometryReader { geo in
        TimelineView(.animation(paused: flight == nil)) { tick in
          let y = flight?.position(tick.date) ?? offset
          ZStack(alignment: .bottom) {
            BakeoffSpec.base.overlay(DS.Color.scrim)
            if hidden {
              Button {
                hidden = false
                offset = flight?.position(Date()) ?? offset
                settle(0, velocity: 0)
              } label: {
                Text("再开").frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(
                  Rectangle())
              }.buttonStyle(KeyStyle())
                .accessibilityIdentifier("bakeoff.reopen")
            }
            ZStack(alignment: .bottom) {
              panel(width: geo.size.width, picker: false)
                .accessibilityElement(children: .contain).accessibilityHidden(state.mode == "cats")
                .allowsHitTesting(state.mode != "cats")
              if state.mode == "cats" {
                DS.Color.scrim.opacity(hidden ? 0 : 1).onTapGesture { tap("bakeoff.back") }
                panel(width: geo.size.width, picker: true).transition(
                  reduced ? .opacity : .move(edge: .bottom))
              }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("bakeoff.sheet")
              .offset(y: y).simultaneousGesture(drag(height: BakeoffSpec.mainHeight))
              .allowsHitTesting(!hidden || y < BakeoffSpec.mainHeight - 1)
              .accessibilityHidden(hidden)
          }
        }
      }.task(id: flight?.date) {
        guard let current = flight else { return }
        let duration = DSMotion.smooth.settlingDuration(
          fromValue: current.start, toValue: current.target, initialVelocity: current.velocity,
          epsilon: 0.001)
        try? await Task.sleep(for: .seconds(duration))
        guard !Task.isCancelled else { return }
        offset = current.target
        flight = nil
      }.ignoresSafeArea().sensoryFeedback(DSMotion.Press.haptic, trigger: hits)
    }
  }

  #Preview { BakeoffSwiftScreen() }
  #Preview("深色") { BakeoffSwiftScreen().preferredColorScheme(.dark) }
#endif
