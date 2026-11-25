import Foundation

public struct SVGPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum SVGPathCommand: Equatable, Sendable {
    case moveTo(SVGPoint)
    case lineTo(SVGPoint)
    case cubicTo(control1: SVGPoint, control2: SVGPoint, end: SVGPoint)
    case quadTo(control: SVGPoint, end: SVGPoint)
    case close
}

public struct SVGBounds: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double
}

public enum SVGPathError: Error, Equatable {
    case unexpectedEnd(command: Character)
    case invalidNumber(index: Int)
    case invalidFlag(index: Int)
    case unexpectedToken(Character, index: Int)
    case unsupportedCommand(Character, index: Int)
}

public enum SVGPathParser {
    public static func parse(_ d: String) throws -> [SVGPathCommand] {
        var scanner = Scanner(d)
        var result: [SVGPathCommand] = []
        var current = SVGPoint(x: 0, y: 0)
        var subpathStart = SVGPoint(x: 0, y: 0)
        var lastCubicControl: SVGPoint?
        var lastQuadControl: SVGPoint?
        var activeCommand: Character?

        while true {
            scanner.skipSeparators()
            if scanner.isAtEnd { break }

            let command: Character
            if let nextCommand = scanner.peekCommand() {
                scanner.advance()
                command = nextCommand
                activeCommand = nextCommand
            } else if let repeated = activeCommand {
                command = repeated == "M" ? "L" : (repeated == "m" ? "l" : repeated)
            } else {
                throw SVGPathError.unexpectedToken(scanner.currentChar ?? "?", index: scanner.offset)
            }

            let isRelative = command.isLowercase
            let upper = Character(command.uppercased())

            func readPoint() throws -> SVGPoint {
                let x = try scanner.readNumber(command: command)
                let y = try scanner.readNumber(command: command)
                return isRelative ? SVGPoint(x: current.x + x, y: current.y + y) : SVGPoint(x: x, y: y)
            }

            switch upper {
            case "M":
                let p = try readPoint()
                result.append(.moveTo(p))
                current = p
                subpathStart = p
                lastCubicControl = nil
                lastQuadControl = nil
                activeCommand = isRelative ? "l" : "L"

            case "L":
                let p = try readPoint()
                result.append(.lineTo(p))
                current = p
                lastCubicControl = nil
                lastQuadControl = nil

            case "H":
                let x = try scanner.readNumber(command: command)
                let p = SVGPoint(x: isRelative ? current.x + x : x, y: current.y)
                result.append(.lineTo(p))
                current = p
                lastCubicControl = nil
                lastQuadControl = nil

            case "V":
                let y = try scanner.readNumber(command: command)
                let p = SVGPoint(x: current.x, y: isRelative ? current.y + y : y)
                result.append(.lineTo(p))
                current = p
                lastCubicControl = nil
                lastQuadControl = nil

            case "C":
                let c1 = try readPoint()
                let c2 = try readPoint()
                let end = try readPoint()
                result.append(.cubicTo(control1: c1, control2: c2, end: end))
                current = end
                lastCubicControl = c2
                lastQuadControl = nil

            case "S":
                let c1: SVGPoint
                if let prev = lastCubicControl {
                    c1 = SVGPoint(x: 2 * current.x - prev.x, y: 2 * current.y - prev.y)
                } else {
                    c1 = current
                }
                let c2 = try readPoint()
                let end = try readPoint()
                result.append(.cubicTo(control1: c1, control2: c2, end: end))
                current = end
                lastCubicControl = c2
                lastQuadControl = nil

            case "Q":
                let c = try readPoint()
                let end = try readPoint()
                result.append(.quadTo(control: c, end: end))
                current = end
                lastQuadControl = c
                lastCubicControl = nil

            case "T":
                let c: SVGPoint
                if let prev = lastQuadControl {
                    c = SVGPoint(x: 2 * current.x - prev.x, y: 2 * current.y - prev.y)
                } else {
                    c = current
                }
                let end = try readPoint()
                result.append(.quadTo(control: c, end: end))
                current = end
                lastQuadControl = c
                lastCubicControl = nil

            case "A":
                let rx = try scanner.readNumber(command: command)
                let ry = try scanner.readNumber(command: command)
                let xAxisRotation = try scanner.readNumber(command: command)
                let largeArc = try scanner.readFlag(command: command)
                let sweep = try scanner.readFlag(command: command)
                let end = try readPoint()
                let segments = arcToCubics(
                    from: current,
                    to: end,
                    rx: rx,
                    ry: ry,
                    xAxisRotationDegrees: xAxisRotation,
                    largeArc: largeArc,
                    sweep: sweep
                )
                result.append(contentsOf: segments)
                current = end
                lastCubicControl = nil
                lastQuadControl = nil

            case "Z":
                result.append(.close)
                current = subpathStart
                lastCubicControl = nil
                lastQuadControl = nil
                activeCommand = nil

            default:
                throw SVGPathError.unsupportedCommand(command, index: scanner.offset)
            }
        }
        return result
    }

    public static func boundingBox(of commands: [SVGPathCommand]) -> SVGBounds? {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        var hasPoint = false
        var current = SVGPoint(x: 0, y: 0)
        var subpathStart = SVGPoint(x: 0, y: 0)

        func include(_ p: SVGPoint) {
            hasPoint = true
            if p.x < minX { minX = p.x }
            if p.y < minY { minY = p.y }
            if p.x > maxX { maxX = p.x }
            if p.y > maxY { maxY = p.y }
        }

        func includeQuadExtrema(_ p0: Double, _ p1: Double, _ p2: Double, apply: (Double) -> Void) {
            let denom = p0 - 2 * p1 + p2
            guard abs(denom) > 1e-12 else { return }
            let t = (p0 - p1) / denom
            if t > 0 && t < 1 {
                let u = 1 - t
                apply(u * u * p0 + 2 * u * t * p1 + t * t * p2)
            }
        }

        func includeCubicExtrema(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, apply: (Double) -> Void) {
            let a = 3 * (p3 - 3 * p2 + 3 * p1 - p0)
            let b = 6 * (p2 - 2 * p1 + p0)
            let c = 3 * (p1 - p0)

            func eval(_ t: Double) {
                guard t > 0 && t < 1 else { return }
                let u = 1 - t
                let val = u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
                apply(val)
            }

            if abs(a) < 1e-12 {
                if abs(b) > 1e-12 {
                    eval(-c / b)
                }
                return
            }
            let disc = b * b - 4 * a * c
            guard disc >= 0 else { return }
            let s = sqrt(disc)
            eval((-b + s) / (2 * a))
            eval((-b - s) / (2 * a))
        }

        for command in commands {
            switch command {
            case .moveTo(let p):
                include(p)
                current = p
                subpathStart = p
            case .lineTo(let p):
                include(current)
                include(p)
                current = p
            case .quadTo(let c, let end):
                include(current)
                include(end)
                includeQuadExtrema(current.x, c.x, end.x) {
                    if $0 < minX { minX = $0 }
                    if $0 > maxX { maxX = $0 }
                }
                includeQuadExtrema(current.y, c.y, end.y) {
                    if $0 < minY { minY = $0 }
                    if $0 > maxY { maxY = $0 }
                }
                current = end
            case .cubicTo(let c1, let c2, let end):
                include(current)
                include(end)
                includeCubicExtrema(current.x, c1.x, c2.x, end.x) {
                    if $0 < minX { minX = $0 }
                    if $0 > maxX { maxX = $0 }
                }
                includeCubicExtrema(current.y, c1.y, c2.y, end.y) {
                    if $0 < minY { minY = $0 }
                    if $0 > maxY { maxY = $0 }
                }
                current = end
            case .close:
                current = subpathStart
            }
        }
        guard hasPoint else { return nil }
        return SVGBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    private static func arcToCubics(
        from p1: SVGPoint,
        to p2: SVGPoint,
        rx rxIn: Double,
        ry ryIn: Double,
        xAxisRotationDegrees: Double,
        largeArc: Bool,
        sweep: Bool
    ) -> [SVGPathCommand] {
        guard p1.x != p2.x || p1.y != p2.y else { return [] }
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        guard rx > 1e-12, ry > 1e-12 else { return [.lineTo(p2)] }

        let phi = xAxisRotationDegrees * .pi / 180.0
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx2 = (p1.x - p2.x) * 0.5
        let dy2 = (p1.y - p2.y) * 0.5
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        var rxSq = rx * rx
        var rySq = ry * ry
        let x1pSq = x1p * x1p
        let y1pSq = y1p * y1p

        let lambda = x1pSq / rxSq + y1pSq / rySq
        if lambda > 1.0 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
            rxSq = rx * rx
            rySq = ry * ry
        }

        let num = max(0.0, rxSq * rySq - rxSq * y1pSq - rySq * x1pSq)
        let den = rxSq * y1pSq + rySq * x1pSq
        let factor = (den > 0 ? sqrt(num / den) : 0) * (largeArc == sweep ? -1.0 : 1.0)
        let cxp = factor * rx * y1p / ry
        let cyp = factor * -ry * x1p / rx

        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) * 0.5
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) * 0.5

        func vectorAngle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let mag = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            let ratio = mag > 0 ? max(-1.0, min(1.0, dot / mag)) : 1.0
            let sign = (ux * vy - uy * vx) < 0 ? -1.0 : 1.0
            return sign * acos(ratio)
        }

        let ux = (x1p - cxp) / rx
        let uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx
        let vy = (-y1p - cyp) / ry

        let theta1 = vectorAngle(1.0, 0.0, ux, uy)
        var dTheta = vectorAngle(ux, uy, vx, vy)
        if !sweep && dTheta > 0 {
            dTheta -= 2.0 * .pi
        } else if sweep && dTheta < 0 {
            dTheta += 2.0 * .pi
        }

        let segments = max(1, Int(ceil(abs(dTheta) / (.pi * 0.5))))
        let delta = dTheta / Double(segments)
        let alpha = (4.0 / 3.0) * tan(delta * 0.25)

        func mapUnit(_ x: Double, _ y: Double) -> SVGPoint {
            let sx = rx * x
            let sy = ry * y
            return SVGPoint(
                x: cx + cosPhi * sx - sinPhi * sy,
                y: cy + sinPhi * sx + cosPhi * sy
            )
        }

        var commands: [SVGPathCommand] = []
        commands.reserveCapacity(segments)
        for i in 0..<segments {
            let t1 = theta1 + Double(i) * delta
            let t2 = t1 + delta
            let cos1 = cos(t1)
            let sin1 = sin(t1)
            let cos2 = cos(t2)
            let sin2 = sin(t2)

            let c1 = mapUnit(cos1 - alpha * sin1, sin1 + alpha * cos1)
            let c2 = mapUnit(cos2 + alpha * sin2, sin2 - alpha * cos2)
            let end = (i == segments - 1) ? p2 : mapUnit(cos2, sin2)
            commands.append(.cubicTo(control1: c1, control2: c2, end: end))
        }
        return commands
    }

    private struct Scanner {
        private let chars: [Character]
        private(set) var index = 0
        var offset: Int { index }
        var isAtEnd: Bool { index >= chars.count }
        var currentChar: Character? { isAtEnd ? nil : chars[index] }

        init(_ string: String) {
            self.chars = Array(string)
        }

        mutating func advance() {
            index += 1
        }

        mutating func skipSeparators() {
            while !isAtEnd {
                let c = chars[index]
                if c.isWhitespace || c == "," {
                    index += 1
                } else {
                    break
                }
            }
        }

        func peekCommand() -> Character? {
            guard !isAtEnd else { return nil }
            let c = chars[index]
            return "MmLlHhVvCcSsQqTtAaZz".contains(c) ? c : nil
        }

        mutating func readFlag(command: Character) throws -> Bool {
            skipSeparators()
            guard !isAtEnd else { throw SVGPathError.unexpectedEnd(command: command) }
            let c = chars[index]
            guard c == "0" || c == "1" else {
                throw SVGPathError.invalidFlag(index: index)
            }
            index += 1
            return c == "1"
        }

        mutating func readNumber(command: Character) throws -> Double {
            skipSeparators()
            guard !isAtEnd else { throw SVGPathError.unexpectedEnd(command: command) }
            let start = index
            var token = ""

            if chars[index] == "+" || chars[index] == "-" {
                token.append(chars[index])
                index += 1
            }

            var hasDigit = false
            while !isAtEnd && chars[index].isASCII && chars[index].isNumber {
                token.append(chars[index])
                index += 1
                hasDigit = true
            }

            if !isAtEnd && chars[index] == "." {
                token.append(".")
                index += 1
                while !isAtEnd && chars[index].isASCII && chars[index].isNumber {
                    token.append(chars[index])
                    index += 1
                    hasDigit = true
                }
            }

            guard hasDigit else {
                throw SVGPathError.invalidNumber(index: start)
            }

            if !isAtEnd && (chars[index] == "e" || chars[index] == "E") {
                let expIndex = index
                var expToken = String(chars[index])
                index += 1
                if !isAtEnd && (chars[index] == "+" || chars[index] == "-") {
                    expToken.append(chars[index])
                    index += 1
                }
                var hasExpDigit = false
                while !isAtEnd && chars[index].isASCII && chars[index].isNumber {
                    expToken.append(chars[index])
                    index += 1
                    hasExpDigit = true
                }
                if hasExpDigit {
                    token.append(contentsOf: expToken)
                } else {
                    index = expIndex
                }
            }

            guard let value = Double(token), value.isFinite else {
                throw SVGPathError.invalidNumber(index: start)
            }
            return value
        }
    }
}
