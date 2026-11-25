#if DEBUG && os(iOS)
  import SwiftUI

  // Point measurements in the expense template, relative to each sheet's top edge.
  // Frames carry the canvas contract only. Each renderer creates native controls.
  struct BakeoffItem: Identifiable {
    var id: String
    var rect: CGRect
    var text: String
    var icon: String?
    var size: CGFloat
    var weight: UIFont.Weight
    var ink: Color
    var fill: Color
    var radius: CGFloat
    var numeric: Bool
    var label: String?
    var stroke: CGFloat
  }

  enum BakeoffSpec {
    typealias C = DS.Color
    static let base = Color(
      uiColor: UIColor { trait in
        let rgb = trait.userInterfaceStyle == .dark ? 0x0E0C09 : 0x9C9483
        return UIColor(
          red: CGFloat(rgb >> 16) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
          blue: CGFloat(rgb & 255) / 255, alpha: 1)
      })
    static let mainHeight: CGFloat = 708
    static let pickerHeight: CGFloat = 560
    // Entry expense header, keyboard tray, picker chips and inline SVG attributes.
    static let amountTracking: CGFloat = -1.8
    static let balanceTracking: CGFloat = -0.4
    static let trayHeight: CGFloat = 270
    static let thumbWidth: CGFloat = 16
    static let thumbHeight: CGFloat = 3
    static let tabWidth: CGFloat = 56
    static let grabberWidth: CGFloat = 36
    static let grabberHeight: CGFloat = 5
    static let chipHeight: CGFloat = 30
    static let homeWidth: CGFloat = 134
    static let homeHeight: CGFloat = 5
    static let pickerGridGap: CGFloat = 6
    static let defaultIconStroke: CGFloat = 1.8
    static let glyphStroke: CGFloat = 2.6
    static let guessDiameter: CGFloat = 8
    static let keyShadow = Color(
      uiColor: UIColor { traits in
        UIColor(C.shadowInk).resolvedColor(with: traits).withAlphaComponent(
          traits.userInterfaceStyle == .dark ? 0.45 : 0.22)
      })
    // Entry canvas: vertical flow, SVG viewports, keypad and category picker.
    static let grabberRadius: CGFloat = 3
    static let typeRowTop: CGFloat = 13
    static let thumbTop: CGFloat = 49
    static let currencyTop: CGFloat = 94
    static let amountTop: CGFloat = 77
    static let caretTop: CGFloat = 89
    static let purposeTop: CGFloat = 147
    static let categoryTop: CGFloat = 199
    static let subcategoriesTop: CGFloat = 280
    static let pillsTop: CGFloat = 328
    static let resultTop: CGFloat = 380
    static let resultLineTop: CGFloat = 390
    static let pickerGridTop: CGFloat = 67
    static let pickerRowStride: CGFloat = 82
    static let pickerCardTop: CGFloat = 239
    static let pickerTitleTop: CGFloat = 253
    static let pickerChipsTop: CGFloat = 279
    static let pickerChipStride: CGFloat = 42
    static let amountLineHeight: CGFloat = 64
    static let amountCaretHeight: CGFloat = 40
    static let amountCaretWidth: CGFloat = 2
    static let sheetTitleHeight: CGFloat = 48
    static let categoryGlyphSize: CGFloat = 22
    static let fieldGlyphSize: CGFloat = 15
    static let pickerCardHeight: CGFloat = 136
    static let resultLineHeight: CGFloat = 26
    static let expenseChipWidth: CGFloat = 50
    static let categoryControlWidth: CGFloat = 52
    static let categoryControlHeight: CGFloat = 70
    static let pickerBackHeight: CGFloat = 61
    static let currencyGlyphSize: CGFloat = 11
    static let dismissVelocity: CGFloat = 750
    static let flickMinimumTravel: CGFloat = 40
    static let vectorGrid: CGFloat = 24
    static let sheetRadius = DS.Radius.sheet
    static let dismissFraction = 0.55
    static func items(width w: CGFloat, state s: BakeoffFixture, picker: Bool) -> [BakeoffItem] {
      var result: [BakeoffItem] = []
      func item(
        _ id: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
        _ text: String = "", _ size: CGFloat = DS.Font.tPill.size,
        _ weight: UIFont.Weight = .regular,
        _ ink: Color = C.ink, _ fill: Color = .clear, _ radius: CGFloat = 0,
        icon: String? = nil, numeric: Bool = false, label: String? = nil,
        stroke: CGFloat = defaultIconStroke
      ) {
        result.append(
          .init(
            id: id, rect: CGRect(x: x, y: y, width: width, height: height), text: text, icon: icon,
            size: size, weight: weight, ink: ink, fill: fill, radius: radius, numeric: numeric,
            label: label, stroke: stroke))
      }
      let mid = w / 2
      item(
        "grabber", mid - grabberWidth / 2, DS.Space.s8, grabberWidth, grabberHeight, "", 14,
        .regular, C.ink, C.grabber, grabberRadius)
      func category(_ pair: (String, String), _ i: Int, _ x: CGFloat, _ y: CGFloat, selected: Bool)
      {
        let manual = picker ? s.manualPickerCategory : s.manualCategory
        let ink = selected ? (manual ? C.ink : C.accentInk) : C.ink2
        item(
          "circle.\(i)", x - 24, y, DS.Size.catCircle, DS.Size.catCircle, "", categoryGlyphSize,
          .regular, ink,
          selected ? (manual ? C.selected : C.accentSoft) : C.surface, 24, icon: pair.1,
          stroke: DS.Stroke.icon)
        item(
          "name.\(i)", x - 28, y + (picker ? 53 : 54), 56, 16, pair.0, 12,
          selected ? .semibold : .regular, ink)
        item(
          "bakeoff.cat.\(i)", x - 26, y, categoryControlWidth, categoryControlHeight, label: pair.0)
      }
      func homeIndicator(_ height: CGFloat) {
        item(
          "home", mid - homeWidth / 2, height - DS.Space.s8 - homeHeight, homeWidth, homeHeight, "",
          14, .regular, C.ink, C.ink, grabberRadius)
      }
      if picker {
        item("heading", DS.Space.s20, typeRowTop, 34, sheetTitleHeight, "分类", 17, .semibold)
        item("edit", w - 54, typeRowTop, 38, sheetTitleHeight, "编辑", 15, .regular, C.accentInk)
        let cell = (w - 32 - 24) / 5
        for (i, pair) in BakeoffFixture.all.enumerated() {
          category(
            pair, i, 16 + cell / 2 + CGFloat(i % 5) * (cell + pickerGridGap),
            pickerGridTop + CGFloat(i / 5) * pickerRowStride,
            selected: s.pickerCategory == pair.0)
        }
        item(
          "panel", DS.Space.s16, pickerCardTop, w - 2 * DS.Space.s16, pickerCardHeight, "", 14,
          .regular, C.ink, C.surface, DS.Radius.m)
        item("subheading", 30, pickerTitleTop, 66, 16, "购物 · 小类", 12, .regular, C.ink3)
        var x: CGFloat = 30
        var y: CGFloat = pickerChipsTop
        for (i, name) in ["衣服", "数码配件", "日用杂货", "不分小类", "运动鞋", "小类"].enumerated() {
          let width: CGFloat = [56, 84, 84, 84, 112, 72][i]
          if x + width > w - 30 {
            x = 30
            y += pickerChipStride
          }
          let raised = Color(
            uiColor: UIColor {
              $0.userInterfaceStyle == .dark ? UIColor(C.surface) : UIColor(C.raised)
            })
          item(
            "chip.\(i)", x, y, width, DS.Size.pillH, i == 4 ? "" : name, 14,
            i == 0 ? .semibold : .regular, i == 0 || i == 5 ? C.accentInk : C.ink,
            i == 0 ? C.accentSoft : raised, 17)
          if i == 4 {
            item("shoeBorder", x, y, width, 34, "", 14, .regular, C.accent)
            item("shoe", x + 8, y, 49, 34, name, 14)
            item("cursor", x + 57, y + 9, 2, 16, "", 14, .regular, C.ink, C.accent, 1)
            item("add", x + 64, y + 5, 42, 24, "添加", 12, .semibold, C.onAccent, C.accent, 12)
          }
          if i == 5 {
            item(
              "plusChip", x + 10, y, 12, 34, "", 12, .regular, C.accentInk, icon: "plus",
              stroke: glyphStroke)
          }
          x += width + DS.Space.s8
        }
        item("bakeoff.back", 0, 0, w, pickerBackHeight, label: "关闭分类")
        homeIndicator(pickerHeight)
        return result
      }
      item(
        "bakeoff.close", DS.Space.s4, typeRowTop, DS.Size.tapMin, DS.Size.tapMin, "", 20, .regular,
        C.ink3, icon: "close", label: "关闭",
        stroke: 2)
      for (i, name) in BakeoffFixture.tabs.enumerated() {
        item(
          "bakeoff.type.\(i)", mid - 112 + CGFloat(i) * tabWidth, typeRowTop, tabWidth,
          DS.Size.tapMin,
          name, 16, i == s.tab ? .semibold : .regular, i == s.tab ? C.ink : C.ink3, label: name)
      }
      item(
        "thumb", mid - 92 + CGFloat(s.tab) * tabWidth, thumbTop, thumbWidth, thumbHeight, "", 14,
        .regular, C.ink, C.ink, 2)
      let amountWidth = min(
        w - 80,
        ceil(
          (s.amount as NSString).size(withAttributes: [
            .font: UIFont.monospacedDigitSystemFont(ofSize: DS.Font.nEntry.size, weight: .semibold)
          ]).width) + CGFloat(s.amount.count) * amountTracking + 4)
      let start = mid - (amountWidth + 58) / 2
      item("currency", start, currencyTop, 44, chipHeight, "", 16, .semibold, C.ink2, C.surface, 15)
      item("yen", start + 7, currencyTop, 15, chipHeight, "¥", 16, .semibold, C.ink2, numeric: true)
      item(
        "down", start + 25, currencyTop, currencyGlyphSize, chipHeight, "", 11, .regular, C.ink3,
        icon: "down", stroke: glyphStroke)
      item(
        "bakeoff.amount", start + 50, amountTop, amountWidth, amountLineHeight, s.amount,
        DS.Font.nEntry.size, .semibold, C.ink,
        numeric: true, label: s.amount)
      item(
        "caret", start + 56 + amountWidth, caretTop, amountCaretWidth, amountCaretHeight, "", 14,
        .regular, C.ink, C.ink3.opacity(0.6),
        1)
      item(
        "pencil", mid - 27, purposeTop, 15, 30, "", fieldGlyphSize, .regular, C.ink3, icon: "pencil"
      )
      item("purpose", mid - 6, purposeTop, 36, chipHeight, "午饭", 16, .regular, C.ink2)
      for (i, pair) in BakeoffFixture.quick.enumerated() {
        let x = 46 + CGFloat(i) * (w - 92) / 5
        category(pair, i, x, categoryTop, selected: s.category == pair.0)
        if i == 0 && !s.manualCategory && s.category == pair.0 {
          item("guessHalo", x + 11, categoryTop + 1, 12, 12, "", 14, .regular, C.ink, C.bg, 6)
          item(
            "guess", x + 13, categoryTop + 3, guessDiameter, guessDiameter, "", 14, .regular, C.ink,
            C.accentInk, 4)
        }
      }
      item("subTitle", 20, subcategoriesTop, 26, 30, "小类", 12, .regular, C.ink3)
      for (i, name) in ["午餐", "早餐", "晚餐", "夜宵", "+"].enumerated() {
        let selected = s.sub == name
        item(
          "bakeoff.sub.\(name)", 60 + CGFloat(i) * 56, subcategoriesTop,
          i == 4 ? chipHeight : expenseChipWidth, chipHeight,
          i == 4 ? "" : name, 13, selected ? .semibold : .regular, selected ? C.accentInk : C.ink2,
          selected ? C.accentSoft : C.surface, 15, icon: i == 4 ? "plus" : nil,
          label: i == 4 ? "新建小类" : name)
      }
      let time = s.mode == "time"
      let names =
        time
        ? ["今天", "昨天", "前天", "", "每月"] : ["招行储蓄", s.monthly ? s.day + " · 每月 23 日" : s.day, ""]
      let icons: [String?] =
        time
        ? [nil, nil, nil, "calendar", "repeat"] : ["bank", s.monthly ? "repeat" : "clock", "dots"]
      let widths: [CGFloat] = time ? [56, 56, 56, 34, 74] : [102, s.monthly ? 164 : 74, 34]
      var x = mid - (widths.reduce(0, +) + CGFloat(names.count - 1) * 8) / 2
      for (i, name) in names.enumerated() {
        let width = widths[i]
        let selected = time && (name == s.day || (name == "每月" && s.monthly))
        item(
          "pill.\(i)", x, pillsTop, width, DS.Size.pillH, "", 14, .regular, C.ink,
          selected ? C.selected : C.surface, 17)
        if let icon = icons[i] {
          item(
            "pillIcon.\(i)", x + (name.isEmpty ? (width - 15) / 2 : 11), pillsTop, 15, 34, "", 15,
            .regular, C.ink3, icon: icon)
        }
        if !name.isEmpty {
          let inset: CGFloat = icons[i] == nil ? 0 : 27
          item(
            "pillText.\(i)", x + inset, pillsTop, width - inset - (inset == 0 ? 0 : 8), 34, name,
            14,
            selected ? .semibold : .regular, selected ? C.ink : C.ink2, numeric: true)
        }
        if (time && !name.isEmpty) || (!time && i == 1) {
          item(
            time ? "bakeoff.day.\(name)" : "bakeoff.time", x, pillsTop, width, DS.Size.pillH,
            label: name.isEmpty ? "日期" : name)
        }
        x += width + DS.Space.s8
      }
      item(
        "summary", DS.Space.s16, resultTop, w - 2 * DS.Space.s16, 46, "", 14, .regular, C.ink,
        C.surface, DS.Radius.m)
      item(
        "resultTitle", 32, resultLineTop, 85, resultLineHeight, "记下后还能花", DS.Font.tPill.size,
        .regular, C.ink2)
      item(
        "note", 121, resultLineTop, 94, resultLineHeight, "吃饭剩 1,194.00", 12, .regular, C.ink3,
        numeric: true)
      item(
        "balance", w - 150, resultLineTop, 120, resultLineHeight, "¥6,226.40", 22, .semibold,
        C.accentInk, numeric: true)
      let trayY = mainHeight - trayHeight
      item("tray", 0, trayY, w, trayHeight, "", 14, .regular, C.ink, C.tray)
      let keyWidth = (w - 40) / 4
      for (i, key) in BakeoffFixture.keys.enumerated() {
        let ok = key == "记下"
        let fn = ["⌫", "+", "−"].contains(key)
        item(
          "bakeoff.key.\(key)", 8 + CGFloat(i % 4) * (keyWidth + DS.Space.s8),
          trayY + DS.Space.s8 + CGFloat(i / 4) * 56, keyWidth, DS.Size.keyH, key,
          ok ? DS.Font.tTitle.size : DS.Font.nKey.size,
          ok ? .semibold : .medium, ok ? C.onAccent : C.ink, ok ? C.accent : fn ? C.keyFn : C.key,
          DS.Radius.s, numeric: true, label: key == "⌫" ? "退格" : key)
      }
      homeIndicator(mainHeight)
      return result
    }
  }
#endif
