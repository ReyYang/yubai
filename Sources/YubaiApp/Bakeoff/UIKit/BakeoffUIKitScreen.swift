#if DEBUG && os(iOS)
  import UIKit

  private final class FixtureControl: UIControl {
    let caption = UILabel()
    let vector = CAShapeLayer()
    var item: BakeoffItem!
    var action: ((String) -> Void)?
    var pressAnimator: UIViewPropertyAnimator?

    override init(frame: CGRect) {
      super.init(frame: frame)
      layer.cornerCurve = .continuous
      addSubview(caption)
      caption.textAlignment = .center
      caption.adjustsFontSizeToFitWidth = true
      caption.minimumScaleFactor = 0.6
      layer.addSublayer(vector)
      vector.fillColor = nil
      vector.lineCap = .round
      vector.lineJoin = .round
      addTarget(self, action: #selector(activate), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func activate() { action?(item.id) }
    override var isHighlighted: Bool {
      didSet {
        guard item?.id.hasPrefix("bakeoff.key.") == true else { return }
        pressAnimator?.stopAnimation(true)
        if UIAccessibility.isReduceMotionEnabled {
          alpha = isHighlighted ? DSInteraction.reducedPressOpacity : 1
          transform = .identity
          return
        }
        let scale = isHighlighted ? DSMotion.Press.scale : 1
        let animator = BakeoffUIKitScreen.animator(DSMotion.snappyToken)
        animator.addAnimations { self.transform = CGAffineTransform(scaleX: scale, y: scale) }
        pressAnimator = animator
        animator.startAnimation()
      }
    }
    func configure(_ value: BakeoffItem) {
      item = value
      bounds.size = value.rect.size
      center = CGPoint(x: value.rect.midX, y: value.rect.midY)
      backgroundColor = UIColor(value.fill)
      layer.cornerRadius = value.id == "shoeBorder" ? DS.Size.pillH / 2 : value.radius
      layer.borderWidth = value.id == "shoeBorder" ? DS.Stroke.focus : 0
      layer.borderColor = UIColor(DS.Color.accent).resolvedColor(with: traitCollection).cgColor
      layer.shadowColor =
        UIColor(BakeoffSpec.keyShadow).resolvedColor(with: traitCollection).cgColor
      layer.shadowOpacity = value.id.hasPrefix("bakeoff.key.") ? 1 : 0
      layer.shadowRadius = DS.Shadow.key.radius
      layer.shadowOffset = CGSize(width: DS.Shadow.key.x, height: DS.Shadow.key.y)
      caption.frame = bounds
      var font =
        value.numeric
        ? UIFont.monospacedDigitSystemFont(ofSize: value.size, weight: value.weight)
        : UIFont.systemFont(ofSize: value.size, weight: value.weight)
      if value.numeric, let descriptor = font.fontDescriptor.withDesign(.rounded) {
        font = UIFont(descriptor: descriptor, size: value.size)
      }
      caption.font = font
      caption.attributedText = NSAttributedString(
        string: value.text,
        attributes: [
          .kern: value.id == "bakeoff.amount"
            ? BakeoffSpec.amountTracking : value.id == "balance" ? BakeoffSpec.balanceTracking : 0
        ])
      caption.textColor = UIColor(value.ink)
      let scale = value.size / BakeoffSpec.vectorGrid
      var transform = CGAffineTransform(scaleX: scale, y: scale)
      vector.frame = CGRect(
        x: (bounds.width - value.size) / 2, y: (bounds.height - value.size) / 2, width: value.size,
        height: value.size)
      vector.path = value.icon.flatMap { BakeoffIcons.vectors[$0]?.copy(using: &transform) }
      vector.strokeColor = UIColor(value.ink).resolvedColor(with: traitCollection).cgColor
      vector.lineWidth = value.stroke * scale
      isAccessibilityElement = value.label != nil
      isUserInteractionEnabled = value.label != nil && value.id != "bakeoff.amount"
      accessibilityTraits = isUserInteractionEnabled ? .button : .staticText
      accessibilityLabel = value.id == "bakeoff.amount" ? "金额" : value.label
      accessibilityValue = value.id == "bakeoff.amount" ? value.text : nil
      accessibilityIdentifier = value.id
    }
  }

  // UIPanGestureRecognizer's translation starts after its recognition threshold.
  // Preserve the actual contact location to match the canvas's 1:1 displacement.
  private final class SheetPan: UIPanGestureRecognizer {
    private(set) var contactY: CGFloat = 0
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      if let touch = touches.first { contactY = touch.location(in: view).y }
      super.touchesBegan(touches, with: event)
    }
    var travel: CGFloat { location(in: view).y - contactY }
  }

  final class BakeoffUIKitScreen: UIViewController {
    private var state = BakeoffFixture()
    private let sheet = UIView(), picker = UIView(), veil = UIControl(), scrim = UIView(),
      reopen = UIButton(type: .custom)
    private var animator: UIViewPropertyAnimator?
    private var origin: CGFloat = 0
    private var hidden = false
    static func animator(_ token: DSMotion.SpringToken, velocity: CGFloat = 0)
      -> UIViewPropertyAnimator
    {
      UIViewPropertyAnimator(
        duration: 0,
        timingParameters: UISpringTimingParameters(
          mass: token.mass, stiffness: token.stiffness, damping: token.damping,
          initialVelocity: CGVector(dx: 0, dy: velocity)))
    }
    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = UIColor(BakeoffSpec.base)
      scrim.backgroundColor = UIColor(DS.Color.scrim)
      view.addSubview(scrim)
      reopen.setTitle("再开", for: .normal)
      reopen.accessibilityIdentifier = "bakeoff.reopen"
      reopen.addTarget(self, action: #selector(open), for: .touchUpInside)
      view.addSubview(reopen)
      for panel in [sheet, picker] {
        panel.backgroundColor = UIColor(DS.Color.bg)
        panel.layer.cornerRadius = BakeoffSpec.sheetRadius
        panel.layer.cornerCurve = .continuous
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.clipsToBounds = true
      }
      view.addSubview(sheet)
      veil.backgroundColor = UIColor(DS.Color.scrim)
      veil.addTarget(self, action: #selector(back), for: .touchUpInside)
      view.addSubview(veil)
      view.addSubview(picker)
      let pan = SheetPan(target: self, action: #selector(drag(_:)))
      view.addGestureRecognizer(pan)
      sheet.accessibilityIdentifier = "bakeoff.sheet"
      registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
        (self: Self, _: UITraitCollection) in self.view.setNeedsLayout()
      }
    }
    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      let b = view.bounds
      scrim.frame = b
      veil.frame = b
      reopen.frame = b
      for (panel, height) in [(sheet, BakeoffSpec.mainHeight), (picker, BakeoffSpec.pickerHeight)] {
        panel.bounds.size = CGSize(width: b.width, height: height)
        panel.center = CGPoint(x: b.midX, y: b.maxY - height / 2)
      }
      render()
    }
    private func render() {
      let cats = state.mode == "cats"
      reopen.isHidden = !hidden
      veil.isHidden = !cats || hidden
      picker.isHidden = !cats || hidden
      sheet.accessibilityElementsHidden = cats || hidden
      for (panel, isPicker) in [(sheet, false), (picker, true)] {
        let items = BakeoffSpec.items(width: view.bounds.width, state: state, picker: isPicker)
        let ids = Set(items.map(\.id))
        var controls = [String: FixtureControl]()
        for case let control as FixtureControl in panel.subviews {
          if ids.contains(control.item.id) {
            controls[control.item.id] = control
          } else {
            control.removeFromSuperview()
          }
        }
        for item in items {
          let control = controls[item.id] ?? FixtureControl()
          if control.superview == nil {
            panel.addSubview(control)
            control.action = { [weak self] in self?.tap($0) }
          }
          control.configure(item)
          if state.selected(item.id, picker: isPicker) {
            control.accessibilityTraits.insert(.selected)
          }
        }
      }
    }
    @objc private func back() { tap("bakeoff.back") }
    private func tap(_ id: String) {
      if id == "bakeoff.close" {
        settle(dismiss: true, velocity: 0)
        return
      }
      if id.hasPrefix("bakeoff.key.") { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
      let was = state.mode
      state.tap(id)
      if id.hasPrefix("bakeoff.type.") {
        let slide = Self.animator(DSMotion.smoothToken)
        slide.addAnimations { self.render() }
        if UIAccessibility.isReduceMotionEnabled { render() } else { slide.startAnimation() }
      } else if (was == "cats") != (state.mode == "cats") && !UIAccessibility.isReduceMotionEnabled
      {
        let entering = state.mode == "cats"
        if entering {
          render()
          picker.transform = CGAffineTransform(translationX: 0, y: BakeoffSpec.pickerHeight)
        }
        let slide = Self.animator(DSMotion.smoothToken)
        slide.addAnimations {
          self.picker.transform =
            entering ? .identity : CGAffineTransform(translationX: 0, y: BakeoffSpec.pickerHeight)
        }
        slide.addCompletion { _ in
          self.render()
          self.picker.transform = .identity
        }
        slide.startAnimation()
      } else {
        render()
      }
    }
    @objc private func open() { settle(dismiss: false, velocity: 0) }
    @objc private func drag(_ pan: SheetPan) {
      switch pan.state {
      case .began:
        let displayed = sheet.layer.presentation()?.affineTransform().ty ?? sheet.transform.ty
        animator?.stopAnimation(true)
        sheet.transform = CGAffineTransform(translationX: 0, y: displayed)
        origin = displayed
      case .changed:
        sheet.transform = CGAffineTransform(
          translationX: 0, y: max(0, origin + pan.travel))
        picker.transform = sheet.transform
      case .ended, .cancelled:
        let v = pan.velocity(in: view).y
        let y = sheet.transform.ty
        settle(
          dismiss: pan.state == .ended
            && (y > BakeoffSpec.mainHeight * BakeoffSpec.dismissFraction
              || (v > BakeoffSpec.dismissVelocity && y > BakeoffSpec.flickMinimumTravel)),
          velocity: v)
      default: break
      }
    }
    private func settle(dismiss: Bool, velocity: CGFloat) {
      hidden = dismiss
      reopen.isHidden = !dismiss
      let end: CGFloat = dismiss ? BakeoffSpec.mainHeight : 0
      let distance = end - sheet.transform.ty
      let move = {
        self.sheet.transform = CGAffineTransform(translationX: 0, y: end)
        self.picker.transform = self.sheet.transform
      }
      if UIAccessibility.isReduceMotionEnabled {
        move()
        render()
        return
      }
      let spring = Self.animator(
        DSMotion.smoothToken, velocity: distance == 0 ? 0 : velocity / distance)
      spring.addAnimations(move)
      spring.addCompletion { _ in self.render() }
      animator = spring
      spring.startAnimation()
    }
  }
#endif
