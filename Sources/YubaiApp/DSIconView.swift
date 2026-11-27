import SwiftUI
import YubaiCore

struct DSIconView: View {
    let icon: DS.Icon
    let size: CGFloat
    var color: Color? = nil

    /// Remix filled outlines, plus the stroked line of custom glyphs, parsed once on the 24 grid.
    private static let cachedPaths: [DS.Icon: (fill: Path, stroke: Path?)] = {
        var map: [DS.Icon: (fill: Path, stroke: Path?)] = [:]
        map.reserveCapacity(DS.Icon.allCases.count)
        for glyph in DS.Icon.allCases {
            map[glyph] = (buildPath(from: glyph.pathData), glyph.stroke.map { buildPath(from: $0.pathData) })
        }
        return map
    }()

    static func buildPath(from d: String) -> Path {
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
        let scale = size / DS.Icon.grid
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let paths = Self.cachedPaths[icon] ?? (Path(), nil)
        let fillStyle: AnyShapeStyle = color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.foreground)
        Rectangle()
            .fill(fillStyle)
            .frame(width: size, height: size)
            .mask {
                ZStack {
                    paths.fill.applying(transform).fill(Color.black)
                    if let stroke = paths.stroke, let width = icon.stroke?.width {
                        stroke.applying(transform).stroke(Color.black, style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round))
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
