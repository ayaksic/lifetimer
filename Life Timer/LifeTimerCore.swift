//
//  LifeTimerCore.swift
//  Life Timer
//
//  Created by Andrew Yaksic on 5/5/26.
//

import Foundation

let defaultLifetimeStart = LifePeriod.calendar.date(
    from: DateComponents(year: 1985, month: 4, day: 17, hour: 3, minute: 41)
)!

struct TimerPage: Identifiable, Equatable {
    let period: LifePeriod
    let style: TimerPageStyle

    var id: String {
        "\(style.rawValue)-\(period.rawValue)"
    }

    static let all: [TimerPage] = {
        LifePeriod.allCases.map { TimerPage(period: $0, style: .flow) }
            + LifePeriod.allCases.map { TimerPage(period: $0, style: .grid) }
    }()
}

enum TimerPageStyle: String {
    case flow
    case grid
}

struct SegmentGrid {
    let rows: Int
    let cols: Int
    let segments: Int
}

struct SegmentProgress {
    let index: Int
    let progress: Double
}

struct CellFillRange {
    let start: Double
    let end: Double
    let showMarker: Bool
}

enum LifePeriod: Int, CaseIterable, Identifiable {
    case hour
    case day
    case week
    case month
    case year
    case lifetime

    var id: Int { rawValue }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = .current
        return calendar
    }

    var decimalPlaces: Int {
        switch self {
        case .hour:
            4
        case .day:
            5
        case .week:
            6
        case .month:
            7
        case .year:
            8
        case .lifetime:
            9
        }
    }

    func progress(at date: Date, lifetimeStart: Date) -> Double {
        let interval = range(containing: date, lifetimeStart: lifetimeStart)
        let duration = interval.end.timeIntervalSince(interval.start)
        guard duration > 0 else { return 0 }

        let elapsed = date.timeIntervalSince(interval.start)
        return min(1, max(0, elapsed / duration))
    }

    func percentString(at date: Date, lifetimeStart: Date) -> String {
        let percent = progress(at: date, lifetimeStart: lifetimeStart) * 100
        return String(format: "%.\(decimalPlaces)f%%", percent)
    }

    func label(for date: Date) -> String {
        let calendar = Self.calendar

        switch self {
        case .hour:
            let hour = calendar.component(.hour, from: date)
            let suffix = hour < 12 ? "AM" : "PM"
            let hour12 = hour % 12 == 0 ? 12 : hour % 12
            return "\(hour12) \(suffix)"
        case .day:
            return "\(monthName(for: date)) \(calendar.component(.day, from: date))"
        case .week:
            return "\(monthName(for: date)) week \(monthWeek(for: date))"
        case .month:
            return monthName(for: date)
        case .year:
            return String(calendar.component(.year, from: date))
        case .lifetime:
            return "Life"
        }
    }

    func range(containing date: Date, lifetimeStart: Date) -> DateInterval {
        let calendar = Self.calendar

        switch self {
        case .hour:
            return calendar.dateInterval(of: .hour, for: date)!
        case .day:
            return calendar.dateInterval(of: .day, for: date)!
        case .week:
            let startOfDay = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: startOfDay)
            let start = calendar.date(byAdding: .day, value: -(weekday - 1), to: startOfDay)!
            let end = calendar.date(byAdding: .day, value: 7, to: start)!
            return DateInterval(start: start, end: end)
        case .month:
            return calendar.dateInterval(of: .month, for: date)!
        case .year:
            return calendar.dateInterval(of: .year, for: date)!
        case .lifetime:
            let end = calendar.date(byAdding: .year, value: 80, to: lifetimeStart)!
            return DateInterval(start: lifetimeStart, end: end)
        }
    }

    func grid(containing date: Date) -> SegmentGrid {
        switch self {
        case .hour:
            return SegmentGrid(rows: 10, cols: 6, segments: 60)
        case .day:
            return SegmentGrid(rows: 6, cols: 4, segments: 24)
        case .week:
            return SegmentGrid(rows: 14, cols: 12, segments: 168)
        case .month:
            return monthGrid(dayCount: daysInMonth(date))
        case .year:
            return SegmentGrid(rows: 4, cols: 3, segments: 12)
        case .lifetime:
            return SegmentGrid(rows: 10, cols: 8, segments: 80)
        }
    }

    func segment(at date: Date, lifetimeStart: Date, totalSegments: Int) -> SegmentProgress {
        switch self {
        case .month:
            return monthSegment(at: date)
        case .year:
            return yearSegment(at: date)
        case .lifetime:
            return lifetimeSegment(at: date, lifetimeStart: lifetimeStart)
        case .hour, .day, .week:
            let interval = range(containing: date, lifetimeStart: lifetimeStart)
            return uniformSegment(
                at: date,
                start: interval.start,
                end: interval.end,
                totalSegments: totalSegments
            )
        }
    }

    func cellFillRange(for index: Int, segment: SegmentProgress, lifetimeStart: Date) -> CellFillRange {
        if self == .lifetime && index == 0 {
            let startProgress = yearProgress(at: lifetimeStart)
            let end = index < segment.index ? 1 : segment.progress

            return CellFillRange(
                start: startProgress,
                end: max(startProgress, end),
                showMarker: index == segment.index
            )
        }

        if index < segment.index {
            return CellFillRange(start: 0, end: 1, showMarker: false)
        }

        if index == segment.index {
            return CellFillRange(start: 0, end: segment.progress, showMarker: true)
        }

        return CellFillRange(start: 0, end: 0, showMarker: false)
    }

    func gridLabelLines(for index: Int, at date: Date, lifetimeStart: Date) -> [String] {
        if self == .week {
            return [weekdayLabel(for: index), hourLabel(for: index % 24)]
        }

        return [gridLabel(for: index, at: date, lifetimeStart: lifetimeStart)]
    }

    func unitPositionLabel(at date: Date, lifetimeStart: Date) -> String {
        switch self {
        case .lifetime:
            return "1/1"
        case .year:
            let total = 80
            return "\(currentCalendarYearNumber(at: date, lifetimeStart: lifetimeStart, total: total))/\(total)"
        case .month:
            let total = 80 * 12
            return "\(currentCalendarMonthNumber(at: date, lifetimeStart: lifetimeStart, total: total))/\(total)"
        case .week:
            return currentDurationUnitLabel(at: date, lifetimeStart: lifetimeStart, unitDuration: 7 * 24 * 60 * 60)
        case .day:
            return currentDurationUnitLabel(at: date, lifetimeStart: lifetimeStart, unitDuration: 24 * 60 * 60)
        case .hour:
            return currentDurationUnitLabel(at: date, lifetimeStart: lifetimeStart, unitDuration: 60 * 60)
        }
    }

    private func monthName(for date: Date) -> String {
        Self.monthNameFormatter.string(from: date)
    }

    private func monthWeek(for date: Date) -> Int {
        let day = Self.calendar.component(.day, from: date)
        return ((day - 1) / 7) + 1
    }

    private func gridLabel(for index: Int, at date: Date, lifetimeStart: Date) -> String {
        switch self {
        case .hour:
            return String(format: "%02d", index)
        case .day:
            return hourLabel(for: index)
        case .week:
            return String(index + 1)
        case .month:
            return "\(monthName(for: date)) \(index + 1)"
        case .year:
            let labelDate = Self.calendar.date(
                from: DateComponents(
                    year: Self.calendar.component(.year, from: date),
                    month: index + 1,
                    day: 1
                )
            )!
            return monthName(for: labelDate)
        case .lifetime:
            return String(Self.calendar.component(.year, from: lifetimeStart) + index)
        }
    }

    private func hourLabel(for hour: Int) -> String {
        let suffix = hour < 12 ? "a" : "p"
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(hour12)\(suffix)"
    }

    private func weekdayLabel(for hourIndex: Int) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][hourIndex / 24]
    }

    private func monthGrid(dayCount: Int) -> SegmentGrid {
        switch dayCount {
        case 28:
            return SegmentGrid(rows: 7, cols: 4, segments: dayCount)
        case 29, 30:
            return SegmentGrid(rows: 6, cols: 5, segments: dayCount)
        default:
            return SegmentGrid(rows: 8, cols: 4, segments: dayCount)
        }
    }

    private func daysInMonth(_ date: Date) -> Int {
        let interval = Self.calendar.dateInterval(of: .month, for: date)!
        return Self.calendar.dateComponents([.day], from: interval.start, to: interval.end).day!
    }

    private func uniformSegment(
        at date: Date,
        start: Date,
        end: Date,
        totalSegments: Int
    ) -> SegmentProgress {
        let totalDuration = end.timeIntervalSince(start)
        guard totalDuration > 0 else {
            return SegmentProgress(index: 0, progress: 0)
        }

        let elapsed = min(totalDuration, max(0, date.timeIntervalSince(start)))
        let segmentDuration = totalDuration / Double(totalSegments)
        let rawIndex = Int(floor(elapsed / segmentDuration))
        let index = min(totalSegments - 1, rawIndex)
        let segmentStart = segmentDuration * Double(index)
        let progress = elapsed >= totalDuration ? 1 : (elapsed - segmentStart) / segmentDuration

        return SegmentProgress(index: index, progress: min(1, max(0, progress)))
    }

    private func monthSegment(at date: Date) -> SegmentProgress {
        let totalSegments = daysInMonth(date)
        let index = min(totalSegments - 1, max(0, Self.calendar.component(.day, from: date) - 1))
        let interval = Self.calendar.dateInterval(of: .day, for: date)!

        return SegmentProgress(
            index: index,
            progress: min(1, max(0, date.timeIntervalSince(interval.start) / interval.duration))
        )
    }

    private func yearSegment(at date: Date) -> SegmentProgress {
        let index = Self.calendar.component(.month, from: date) - 1
        let interval = Self.calendar.dateInterval(of: .month, for: date)!

        return SegmentProgress(
            index: index,
            progress: min(1, max(0, date.timeIntervalSince(interval.start) / interval.duration))
        )
    }

    private func lifetimeSegment(at date: Date, lifetimeStart: Date) -> SegmentProgress {
        let totalSegments = 80
        let end = Self.calendar.date(byAdding: .year, value: totalSegments, to: lifetimeStart)!
        let index = min(
            totalSegments - 1,
            max(0, Self.calendar.component(.year, from: date) - Self.calendar.component(.year, from: lifetimeStart))
        )
        let progress = date >= end ? 1 : yearProgress(at: date)

        return SegmentProgress(index: index, progress: progress)
    }

    private func yearProgress(at date: Date) -> Double {
        let interval = Self.calendar.dateInterval(of: .year, for: date)!
        return min(1, max(0, date.timeIntervalSince(interval.start) / interval.duration))
    }

    private func currentCalendarYearNumber(at date: Date, lifetimeStart: Date, total: Int) -> Int {
        let end = Self.calendar.date(byAdding: .year, value: total, to: lifetimeStart)!
        if date >= end { return total }

        var elapsedYears = Self.calendar.component(.year, from: date) - Self.calendar.component(.year, from: lifetimeStart)
        if let anniversary = Self.calendar.date(byAdding: .year, value: elapsedYears, to: lifetimeStart), date < anniversary {
            elapsedYears -= 1
        }

        return min(total, max(1, elapsedYears + 1))
    }

    private func currentCalendarMonthNumber(at date: Date, lifetimeStart: Date, total: Int) -> Int {
        let end = Self.calendar.date(byAdding: .year, value: 80, to: lifetimeStart)!
        if date >= end { return total }

        let yearDelta = Self.calendar.component(.year, from: date) - Self.calendar.component(.year, from: lifetimeStart)
        var elapsedMonths = yearDelta * 12
            + Self.calendar.component(.month, from: date)
            - Self.calendar.component(.month, from: lifetimeStart)

        if let monthStart = Self.calendar.date(byAdding: .month, value: elapsedMonths, to: lifetimeStart), date < monthStart {
            elapsedMonths -= 1
        }

        return min(total, max(1, elapsedMonths + 1))
    }

    private func currentDurationUnitLabel(at date: Date, lifetimeStart: Date, unitDuration: TimeInterval) -> String {
        let end = Self.calendar.date(byAdding: .year, value: 80, to: lifetimeStart)!
        let duration = calendarTime(for: end) - calendarTime(for: lifetimeStart)
        let elapsed = min(duration, max(0, calendarTime(for: date) - calendarTime(for: lifetimeStart)))
        let total = Int(ceil(duration / unitDuration))
        let current = elapsed >= duration ? total : Int(floor(elapsed / unitDuration)) + 1

        return "\(min(total, max(1, current)))/\(total)"
    }

    private func calendarTime(for date: Date) -> TimeInterval {
        let components = Self.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let utcDate = utcCalendar.date(from: DateComponents(
            calendar: utcCalendar,
            timeZone: utcCalendar.timeZone,
            year: components.year,
            month: components.month,
            day: components.day,
            hour: components.hour,
            minute: components.minute,
            second: components.second,
            nanosecond: components.nanosecond
        ))!

        return utcDate.timeIntervalSince1970
    }

    private static let monthNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Self.calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM"
        return formatter
    }()
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

@available(iOS 16.2, *)
struct LifeTimerHourAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var generatedAt: Date
        var progress: Double
    }

    let hourStart: Date
    let hourEnd: Date
}
#endif
