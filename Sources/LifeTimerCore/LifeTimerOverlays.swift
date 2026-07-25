import Foundation

public enum LifeTimerOverlayKind: Int, CaseIterable, Sendable {
    case inBed
    case asleep
}

public struct LifeTimerOverlayInterval: Equatable, Sendable {
    public let kind: LifeTimerOverlayKind
    public let start: Date
    public let end: Date

    public init(kind: LifeTimerOverlayKind, start: Date, end: Date) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    public func clipped(to range: DateInterval) -> LifeTimerOverlayInterval? {
        let clippedStart = max(start, range.start)
        let clippedEnd = min(end, range.end)
        guard clippedEnd > clippedStart else { return nil }

        return LifeTimerOverlayInterval(kind: kind, start: clippedStart, end: clippedEnd)
    }

    public static func merged(_ intervals: [LifeTimerOverlayInterval]) -> [LifeTimerOverlayInterval] {
        LifeTimerOverlayKind.allCases.flatMap { kind in
            let valid = intervals
                .filter { $0.kind == kind && $0.end > $0.start }
                .sorted {
                    if $0.start == $1.start {
                        return $0.end < $1.end
                    }
                    return $0.start < $1.start
                }

            return valid.reduce(into: [LifeTimerOverlayInterval]()) { merged, interval in
                guard let last = merged.last, interval.start <= last.end else {
                    merged.append(interval)
                    return
                }

                merged[merged.count - 1] = LifeTimerOverlayInterval(
                    kind: kind,
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            }
        }
    }

    public static func totalDuration(
        of kind: LifeTimerOverlayKind,
        in intervals: [LifeTimerOverlayInterval],
        clippedTo range: DateInterval? = nil
    ) -> TimeInterval {
        merged(intervals)
            .filter { $0.kind == kind }
            .compactMap { interval in
                guard let range else { return interval }
                return interval.clipped(to: range)
            }
            .reduce(0) { $0 + $1.duration }
    }
}

public struct LifeTimerUsageBucket: Equatable, Sendable {
    public let dateInterval: DateInterval
    public let activeDuration: TimeInterval

    public init(dateInterval: DateInterval, activeDuration: TimeInterval) {
        self.dateInterval = dateInterval
        self.activeDuration = min(
            max(0, activeDuration),
            max(0, dateInterval.duration)
        )
    }

    public var representativeInterval: DateInterval? {
        guard dateInterval.duration > 0, activeDuration > 0 else { return nil }
        return DateInterval(
            start: dateInterval.start,
            duration: activeDuration
        )
    }

    public static func aggregated(_ buckets: [LifeTimerUsageBucket]) -> [LifeTimerUsageBucket] {
        struct BucketKey: Hashable {
            let start: Date
            let end: Date
        }

        let grouped = Dictionary(grouping: buckets) {
            BucketKey(start: $0.dateInterval.start, end: $0.dateInterval.end)
        }

        return grouped.compactMap { key, values in
            guard key.end > key.start else { return nil }
            return LifeTimerUsageBucket(
                dateInterval: DateInterval(start: key.start, end: key.end),
                activeDuration: values.reduce(0) { $0 + $1.activeDuration }
            )
        }
        .sorted { $0.dateInterval.start < $1.dateInterval.start }
    }
}

public extension LifePeriod {
    func gridDateIntervals(containing date: Date, lifetimeStart: Date) -> [DateInterval] {
        let calendar = Self.calendar
        let timerRange = range(containing: date, lifetimeStart: lifetimeStart)

        switch self {
        case .hour, .day, .week:
            let segmentCount = grid(containing: date).segments
            let segmentDuration = timerRange.duration / Double(segmentCount)

            return (0..<segmentCount).map { index in
                let start = timerRange.start.addingTimeInterval(Double(index) * segmentDuration)
                let end = index == segmentCount - 1
                    ? timerRange.end
                    : timerRange.start.addingTimeInterval(Double(index + 1) * segmentDuration)
                return DateInterval(start: start, end: end)
            }

        case .month:
            let dayCount = grid(containing: date).segments
            return (0..<dayCount).compactMap { index in
                guard
                    let start = calendar.date(byAdding: .day, value: index, to: timerRange.start),
                    let end = calendar.date(byAdding: .day, value: index + 1, to: timerRange.start)
                else {
                    return nil
                }
                return DateInterval(start: start, end: end)
            }

        case .year:
            return (0..<12).compactMap { index in
                guard
                    let start = calendar.date(byAdding: .month, value: index, to: timerRange.start),
                    let end = calendar.date(byAdding: .month, value: index + 1, to: timerRange.start)
                else {
                    return nil
                }
                return DateInterval(start: start, end: end)
            }

        case .lifetime:
            let birthYear = calendar.component(.year, from: lifetimeStart)
            return (0..<80).compactMap { index in
                guard
                    let start = calendar.date(from: DateComponents(year: birthYear + index, month: 1, day: 1)),
                    let end = calendar.date(from: DateComponents(year: birthYear + index + 1, month: 1, day: 1))
                else {
                    return nil
                }
                return DateInterval(start: start, end: end)
            }
        }
    }
}
