import SwiftUI
import YubaiCore

struct DSIconView: View {
    let icon: DS.Icon
    let size: CGFloat
    var color: Color? = nil

    private static let cachedPaths: [DS.Icon: Path] = {
        var map: [DS.Icon: Path] = [:]
        map.reserveCapacity(DS.Icon.allCases.count)
        for glyph in DS.Icon.allCases {
            map[glyph] = buildPath(from: glyph.pathData)
        }
        return map
    }()

    private static func buildPath(from d: String) -> Path {
        var path = Path()
        guard let commands = try? SVGPathParser.parse(d) else { return path }
        for command in commands {
            switch command {
            case .moveTo(let point):
                path.move(to: CGPoint(x: point.x, y: point.y))
            case .lineTo(let point):
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            case .cubicTo(let c1, let c2, let end):
                path.addCurve(
                    to: CGPoint(x: end.x, y: end.y),
                    control1: CGPoint(x: c1.x, y: c1.y),
                    control2: CGPoint(x: c2.x, y: c2.y)
                )
            case .quadTo(let control, let end):
                path.addQuadCurve(
                    to: CGPoint(x: end.x, y: end.y),
                    control: CGPoint(x: control.x, y: control.y)
                )
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }

    var body: some View {
        let line = icon.line
        let scale = size / (line?.grid ?? DS.Icon.grid)
        let basePath = Self.cachedPaths[icon] ?? Path()
        let scaled = basePath.applying(CGAffineTransform(scaleX: scale, y: scale))
        let fillStyle: AnyShapeStyle = color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.foreground)
        Rectangle()
            .fill(fillStyle)
            .frame(width: size, height: size)
            .mask {
                ZStack {
                    if let line {
                        scaled.stroke(Color.black, style: StrokeStyle(lineWidth: line.stroke * scale, lineCap: .round, lineJoin: .round))
                    } else {
                        scaled.fill(Color.black)
                        scaled.stroke(
                            Color.black,
                            style: StrokeStyle(
                                lineWidth: size * DS.Icon.outline / DS.Icon.grid,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

extension DS.Icon {
    func view(size: CGFloat, color: Color? = nil) -> DSIconView {
        DSIconView(icon: self, size: size, color: color)
    }
}
