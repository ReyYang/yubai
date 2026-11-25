#if DEBUG && os(iOS)
  import Foundation

  struct BakeoffFixture {
    static func argument(_ name: String) -> String? {
      let args = ProcessInfo.processInfo.arguments
      guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
      return args[i + 1]
    }

    static let tabs = ["支出", "收入", "转账", "存入"]
    static let quick = [
      ("吃饭", "bowl"), ("咖啡", "cup"), ("交通", "metro"), ("买菜", "basket"), ("购物", "bag"),
      ("全部", "grid"),
    ]
    static let all = [
      ("吃饭", "bowl"), ("购物", "bag"), ("交通", "metro"), ("居住", "house"), ("买菜", "basket"),
      ("娱乐", "ticket"), ("日用", "box"), ("咖啡", "cup"), ("其他", "dots"), ("新建", "plus"),
    ]
    static let keys = [
      "1", "2", "3", "⌫", "4", "5", "6", "+", "7", "8", "9", "−", ".", "0", "00", "记下",
    ]
    var mode = Self.argument("-YubaiBakeoffState") ?? "default"
    var tab = 0
    var manualCategory = false
    var manualPickerCategory = false
    var category = "吃饭"
    var pickerCategory = "购物"
    var sub = "午餐"
    var monthly = false
    var day = "今天"
    var amount = "42.00"
    var editing = false

    func selected(_ id: String, picker: Bool = false) -> Bool {
      if id == "bakeoff.type." + String(tab) { return true }
      let options = picker ? Self.all : Self.quick
      if let i = options.firstIndex(where: { $0.0 == (picker ? pickerCategory : category) }),
        id == "bakeoff.cat." + String(i)
      {
        return true
      }
      return id == "bakeoff.sub." + sub || id == "bakeoff.day." + day
    }
    mutating func tap(_ id: String) {
      let parts = id.components(separatedBy: ".")
      guard let value = parts.last else { return }
      switch parts.count > 2 ? parts[1] : "" {
      case "type": tab = Int(value) ?? 0
      case "cat":
        guard let i = Int(value) else { return }
        if mode == "cats" {
          pickerCategory = Self.all[i].0
          manualPickerCategory = true
        } else if Self.quick[i].0 == "全部" {
          mode = "cats"
        } else {
          category = Self.quick[i].0
          manualCategory = true
        }
      case "sub": if value != "+" { sub = value }
      case "day":
        if value == "每月" { monthly.toggle() } else { day = value }
        mode = "default"
      case "key":
        let key = id.dropFirst("bakeoff.key.".count)
        guard !["+", "−", "记下"].contains(String(key)) else { return }
        if !editing {
          if key != "⌫" { amount = "" }
          editing = true
        }
        if key == "⌫" {
          if !amount.isEmpty { amount.removeLast() }
        } else if key == "." {
          if !amount.contains(".") { amount = (amount.isEmpty ? "0" : amount) + "." }
        } else if let dot = amount.firstIndex(of: ".") {
          amount += key.prefix(max(0, 2 - amount[amount.index(after: dot)...].count))
        } else {
          let digits = ((amount == "0" ? "" : amount) + key).drop(while: { $0 == "0" })
          amount = digits.isEmpty ? "0" : String(digits)
        }
        if amount.isEmpty { amount = "0" }
      default:
        if value == "time" { mode = "time" }
        if value == "back" { mode = "default" }
      }
    }
  }
#endif
