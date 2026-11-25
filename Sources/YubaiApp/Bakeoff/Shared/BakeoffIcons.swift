#if DEBUG && os(iOS)
  import UIKit

  enum BakeoffIcons {
    static let paths = [
      "bowl":
        "M4 11h16a8 8 0 0 1-16 0Z M9 7.5c-.6-.8.6-1.7 0-2.5 M12.5 7.5c-.6-.8.6-1.7 0-2.5 M16 7.5c-.6-.8.6-1.7 0-2.5",
      "cup":
        "M5 9h11v4.5A5.5 5.5 0 0 1 10.5 19A5.5 5.5 0 0 1 5 13.5Z M16 10.5h1.5a2.5 2.5 0 0 1 0 5H16 M4 21h13",
      "metro":
        "M7 3h10a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3Z M4 10h16 M8 21l1.5-4 M16 21l-1.5-4 M8 13.5h.01 M16 13.5h.01",
      "basket":
        "M3 9h18l-1.8 9.2A2 2 0 0 1 17.2 20H6.8a2 2 0 0 1-2-1.8Z M8 9l3-5 M16 9l-3-5 M10 13v3 M14 13v3",
      "bag": "M6 8h12l1 12.5H5Z M9 8V6.5a3 3 0 0 1 6 0V8",
      "ticket": "M4 7h16v3a2 2 0 0 0 0 4v3H4v-3a2 2 0 0 0 0-4Z M14 7v2 M14 11v2 M14 15v2",
      "phone": "M8 3h8a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Z M11 18h2",
      "wallet": "M4 7h15a1 1 0 0 1 1 1v11H5a1 1 0 0 1-1-1Z M4 7l11-3v3 M16 13h.01",
      "gift":
        "M4 10h16v10H4Z M3 7h18v3H3Z M12 7v13 M12 7c-1.5-3-5-3-5-1s3 1 5 1c2 0 5 1 5-1s-3.5-2-5 1",
      "undo": "M9 14 4 9l5-5 M4 9h10a6 6 0 0 1 0 12h-3",
      "grid": "M4 4h7v7H4Z M13 4h7v7h-7Z M4 13h7v7H4Z M13 13h7v7h-7Z",
      "house": "M4 10.5 12 4l8 6.5V20H4Z M10 20v-5h4v5",
      "box": "M4 8l8-4 8 4v8l-8 4-8-4Z M4 8l8 4 8-4 M12 12v8",
      "plus": "M12 5v14 M5 12h14",
      "dots": "M6 12h.01 M12 12h.01 M18 12h.01",
      "bank": "M3 10l9-6 9 6 M5 10v8 M19 10v8 M9.5 10v8 M14.5 10v8 M3 20h18",
      "card": "M3 6h18v12H3Z M3 10h18 M7 15h3",
      "clock": "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z M12 7v5l3 2",
      "repeat": "M17 2l3 3-3 3 M4 11V9a4 4 0 0 1 4-4h12 M7 22l-3-3 3-3 M20 13v2a4 4 0 0 1-4 4H4",
      "close": "M6 6l12 12 M18 6 6 18",
      "down": "M6 9l6 6 6-6",
      "pencil": "M4 20h4L19 9l-4-4L4 16Z M13.5 6.5l4 4",
      "calendar": "M4 6h16v14H4Z M4 10h16 M8 3v4 M16 3v4",
    ]
    static let vectors = paths.mapValues(parse)

    private static func parse(_ data: String) -> CGPath {
      let tokens = data.matches(of: #/[A-Za-z]|-?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)/#).map {
        String($0.output)
      }
      var index = 0
      var command = "M"
      let path = CGMutablePath()
      var lastControl = CGPoint.zero
      func number() -> CGFloat {
        defer { index += 1 }
        return CGFloat(Double(tokens[index])!)
      }
      while index < tokens.count {
        if tokens[index].first!.isLetter {
          command = tokens[index]
          index += 1
        }
        let start = path.currentPoint
        let relative = command == command.lowercased()
        func point() -> CGPoint {
          CGPoint(x: number() + (relative ? start.x : 0), y: number() + (relative ? start.y : 0))
        }
        switch command.uppercased() {
        case "M":
          path.move(to: point())
          command = relative ? "l" : "L"
        case "L": path.addLine(to: point())
        case "H": path.addLine(to: CGPoint(x: number() + (relative ? start.x : 0), y: start.y))
        case "V": path.addLine(to: CGPoint(x: start.x, y: number() + (relative ? start.y : 0)))
        case "Z": path.closeSubpath()
        case "C", "S":
          let c1 =
            command.uppercased() == "S"
            ? CGPoint(x: 2 * start.x - lastControl.x, y: 2 * start.y - lastControl.y) : point()
          let c2 = point()
          path.addCurve(to: point(), control1: c1, control2: c2)
          lastControl = c2
        case "A":
          // All fixture arcs are circular and have zero axis rotation.
          let radius = number()
          _ = number()
          _ = number()
          let large = number() != 0
          let sweep = number() != 0
          let end = point()
          let dx = end.x - start.x
          let dy = end.y - start.y
          let distance = hypot(dx, dy)
          let r = max(radius, distance / 2)
          let offset =
            sqrt(max(0, r * r - distance * distance / 4)) / distance * (large == sweep ? -1 : 1)
          let center = CGPoint(
            x: (start.x + end.x) / 2 - dy * offset, y: (start.y + end.y) / 2 + dx * offset)
          path.addArc(
            center: center, radius: r, startAngle: atan2(start.y - center.y, start.x - center.x),
            endAngle: atan2(end.y - center.y, end.x - center.x), clockwise: !sweep)
        default: preconditionFailure("Unsupported fixture path")
        }
      }
      return path
    }
  }
#endif
