import Foundation

public struct CashTimelineReadout: Equatable, Sendable {
    public var point: CashTimelinePoint
    public var title: String
    public var difference: Int64?
}

public struct CashTimelineEndpoint: Equatable, Sendable {
    public var date: Date
    /// Shared by the chart marker and its text; never clamped to zero.
    public var balance: Int64
    public var belowFloor: Bool
    public var amount: String { CashTimelinePresentation.amount(balance) }
    public func label(hasPayday: Bool) -> String { (hasPayday ? "发工资前 " : "月底 ") + amount }
}

public enum CashTimelinePresentation {
    public static func amount(_ cents: Int64) -> String {
        (cents < 0 ? "−" : "") + Money.text(abs(cents), currency: false)
    }
    public static func dayTitle(_ date: Date) -> String {
        "\(Dates.calendar.component(.month, from: date))月\(Dates.calendar.component(.day, from: date))日"
    }
    /// Absolute cash movement wins, with stable IDs breaking ties regardless of
    /// input ordering. This also works for forecast events and unsorted fixtures.
    public static func eventSummary(_ events: [CashTimelineEvent]) -> String? {
        guard let largest = events.sorted(by: {
            abs($0.amount) == abs($1.amount) ? $0.id < $1.id : abs($0.amount) > abs($1.amount)
        }).first else { return nil }
        let fact = largest.title + " " + (largest.amount >= 0 ? "+" : "−") + Money.text(abs(largest.amount), currency: false)
        return fact + (events.count > 1 ? " · 还有 \(events.count - 1) 笔" : "")
    }
}

extension CashTimelineWindow {
    public func readout(selectedDay: Date? = nil) -> CashTimelineReadout? {
        guard let point = selectedDay.flatMap({ self.point(on: $0) }) ?? history.last else { return nil }
        let title = selectedDay == nil && isDefault ? "今天" : CashTimelinePresentation.dayTitle(point.date)
        return CashTimelineReadout(point: point, title: title,
                                   difference: previousPoint(on: point.date).map { point.balance - $0.balance })
    }
    public var endpointPresentation: CashTimelineEndpoint? {
        endpoint.map { CashTimelineEndpoint(date: $0.date, balance: $0.balance, belowFloor: belowFloor) }
    }
    /// Show the threshold when any predicted stretch falls below it, including
    /// a temporary dip followed by a receipt. Past cycles have no forecast.
    public var showsFloor: Bool {
        guard isDefault, let floor else { return false }
        return forecastLine.contains { $0.balance < floor }
    }
    /// Keep the established eligibility rule, then show salary and two largest
    /// expenses. All daily events remain available to the press readout.
    public var topAnnotations: [CashTimelineEvent] {
        let average = averageSpending
        let candidates = history.flatMap(\.events).filter {
            $0.isSalary || ($0.amount < 0 && ($0.isRecurring || -$0.amount >= average * 3))
        }.sorted {
            abs($0.amount) == abs($1.amount) ? $0.id < $1.id : abs($0.amount) > abs($1.amount)
        }
        return (Array(candidates.filter(\.isSalary).prefix(1)) + Array(candidates.filter { $0.amount < 0 && !$0.isSalary }.prefix(2)))
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
    public var forecastSegments: [CashTimelineForecastSegment] {
        CashTimelineForecastSegment.split(forecastLine, floor: showsFloor ? floor : nil)
    }
}

public struct CashTimelinePlotPoint: Equatable, Sendable {
    public var date: Date
    /// Cents, allowing an exact interpolated threshold crossing.
    public var balance: Double
}

public struct CashTimelineForecastSegment: Identifiable, Equatable, Sendable {
    public var id: Int
    public var belowFloor: Bool
    public var points: [CashTimelinePlotPoint]

    public static func split(_ vertices: [CashTimelineVertex], floor: Int64?) -> [Self] {
        guard let first = vertices.first else { return [] }
        func point(_ vertex: CashTimelineVertex) -> CashTimelinePlotPoint {
            CashTimelinePlotPoint(date: vertex.date, balance: Double(vertex.balance))
        }
        var segments: [Self] = []
        func append(_ a: CashTimelinePlotPoint, _ b: CashTimelinePlotPoint, below: Bool) {
            if segments.last?.belowFloor == below {
                segments[segments.count - 1].points.append(b)
            } else {
                segments.append(Self(id: segments.count, belowFloor: below, points: [a, b]))
            }
        }
        var previous = first
        for next in vertices.dropFirst() {
            let a = point(previous), b = point(next)
            if let floor {
                let threshold = Double(floor)
                if (a.balance < threshold && b.balance > threshold) || (a.balance > threshold && b.balance < threshold) {
                    let fraction = (threshold - a.balance) / (b.balance - a.balance)
                    let crossing = CashTimelinePlotPoint(date: a.date.addingTimeInterval(b.date.timeIntervalSince(a.date) * fraction), balance: threshold)
                    append(a, crossing, below: a.balance < threshold)
                    append(crossing, b, below: b.balance < threshold)
                } else {
                    append(a, b, below: min(a.balance, b.balance) < threshold)
                }
            } else { append(a, b, below: false) }
            previous = next
        }
        return segments
    }
}

/// Horizontal placement is measured by the renderer; row assignment is pure.
public enum CashTimelineAnnotationLayout {
    public struct Candidate: Equatable, Sendable {
        public var id: String
        public var x: Double
        public var width: Double
        public init(id: String, x: Double, width: Double) { self.id = id; self.x = x; self.width = width }
    }
    public struct Placement: Equatable, Sendable {
        public var id: String
        public var centerX: Double
        public var row: Int
    }
    public static func place(_ candidates: [Candidate], width: Double, gap: Double = 8) -> [Placement] {
        var rows: [[ClosedRange<Double>]] = [], result: [Placement] = []
        for candidate in candidates.sorted(by: { $0.x == $1.x ? $0.id < $1.id : $0.x < $1.x }) {
            let center = max(candidate.width / 2, min(width - candidate.width / 2, candidate.x))
            let range = (center - candidate.width / 2)...(center + candidate.width / 2)
            let row = rows.firstIndex { ranges in !ranges.contains { $0.upperBound + gap > range.lowerBound && range.upperBound + gap > $0.lowerBound } } ?? rows.count
            if row == rows.count { rows.append([]) }
            rows[row].append(range)
            result.append(Placement(id: candidate.id, centerX: center, row: row))
        }
        return result
    }
}
