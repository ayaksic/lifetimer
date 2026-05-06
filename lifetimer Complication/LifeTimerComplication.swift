//
//  LifeTimerComplication.swift
//  lifetimer Complication
//

import SwiftUI
import WidgetKit

struct LifeTimerEntry: TimelineEntry {
    let date: Date
    let period: LifePeriod
    let periodStart: Date
    let periodEnd: Date

    var progress: Double {
        let duration = periodEnd.timeIntervalSince(periodStart)
        guard duration > 0 else { return 0 }

        let elapsed = date.timeIntervalSince(periodStart)
        return min(1, max(0, elapsed / duration))
    }

    var percentText: String {
        String(format: "%.\(period.percentDecimalPlaces)f%%", progress * 100)
    }

}

struct LifeTimerProvider: TimelineProvider {
    let period: LifePeriod

    func placeholder(in context: Context) -> LifeTimerEntry {
        entry(for: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (LifeTimerEntry) -> Void) {
        completion(entry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LifeTimerEntry>) -> Void) {
        let now = Date()
        let horizon = period.timelineHorizon(after: now)

        var entries = [entry(for: now)]
        var updateDate = period.nextTimelineUpdate(after: now)

        while updateDate <= horizon {
            entries.append(entry(for: updateDate))
            updateDate = period.nextTimelineUpdate(after: updateDate)
        }

        completion(Timeline(entries: entries, policy: .after(horizon)))
    }

    private func entry(for date: Date) -> LifeTimerEntry {
        let interval = period.range(containing: date)
        return LifeTimerEntry(
            date: date,
            period: period,
            periodStart: interval.start,
            periodEnd: interval.end
        )
    }

}

struct LifeTimerComplicationView: View {
    @Environment(\.widgetFamily) private var family

    let entry: LifeTimerEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                ProgressView(value: entry.progress)
                    .progressViewStyle(.circular)
                    .tint(progressColor(for: entry.progress))

                Text(entry.percentText)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
            }

        case .accessoryCorner:
            ProgressView(value: entry.progress)
                .progressViewStyle(.circular)
                .tint(progressColor(for: entry.progress))
                .widgetLabel {
                    Text(entry.percentText)
                        .monospacedDigit()
                }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.period.complicationLabel)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
                Text(entry.percentText)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ProgressView(value: entry.progress)
                        .tint(progressColor(for: entry.progress))
                    Text(entry.periodEnd, style: .timer)
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }

        case .accessoryInline:
            Text("\(entry.period.complicationLabel) \(entry.percentText)")

        default:
            HStack(spacing: 3) {
                Text(entry.period.complicationLabel)
                Text(entry.percentText)
                    .monospacedDigit()
            }
        }
    }
}

struct LifeTimerComplication: Widget {
    let period: LifePeriod

    init() {
        self.period = .day
    }

    init(period: LifePeriod) {
        self.period = period
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: period.widgetKind, provider: LifeTimerProvider(period: period)) { entry in
            LifeTimerComplicationView(entry: entry)
                .widgetURL(entry.period.deepLinkURL)
        }
        .configurationDisplayName(period.configurationDisplayName)
        .description(period.configurationDescription)
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

@main
struct LifeTimerComplicationBundle: WidgetBundle {
    var body: some Widget {
        LifeTimerComplication(period: .day)
        LifeTimerComplication(period: .hour)
    }
}

enum LifePeriod {
    case hour
    case day

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = .current
        return calendar
    }

    func range(containing date: Date) -> DateInterval {
        Self.calendar.dateInterval(of: calendarComponent, for: date)!
    }

    func nextTimelineUpdate(after date: Date) -> Date {
        let interval = range(containing: date)
        guard timelineCadence > 0 else { return interval.end }

        let elapsed = max(0, date.timeIntervalSince(interval.start))
        let nextStep = (floor(elapsed / timelineCadence) + 1) * timelineCadence
        let clampedStep = min(nextStep, interval.duration)
        let candidate = interval.start.addingTimeInterval(clampedStep)

        if candidate > date {
            return candidate
        }

        return date.addingTimeInterval(timelineCadence)
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .hour:
            return .hour
        case .day:
            return .day
        }
    }

    var complicationLabel: String {
        switch self {
        case .hour:
            return "Hour"
        case .day:
            return "Day"
        }
    }

    var widgetKind: String {
        switch self {
        case .hour:
            return "LifeTimerHourComplication"
        case .day:
            return "LifeTimerComplication"
        }
    }

    var configurationDisplayName: String {
        "Life Timer \(complicationLabel)"
    }

    var configurationDescription: String {
        switch self {
        case .hour:
            return "Shows current-hour progress."
        case .day:
            return "Shows current-day progress."
        }
    }

    var deepLinkURL: URL {
        URL(string: "lifetimer://timer/\(deepLinkPeriodName)")!
    }

    func timelineHorizon(after date: Date) -> Date {
        let interval = range(containing: date)

        switch self {
        case .hour:
            return max(
                date.addingTimeInterval(15 * 60),
                interval.end.addingTimeInterval(15 * 60)
            )
        case .day:
            return date.addingTimeInterval(15 * 60)
        }
    }

    private var timelineCadence: TimeInterval {
        switch self {
        case .hour:
            // Watch faces may throttle sub-minute WidgetKit timelines, which can
            // leave the first hour entry visible long after it should advance.
            return 60
        case .day:
            return 60
        }
    }

    fileprivate var percentDecimalPlaces: Int {
        switch self {
        case .hour:
            return 2
        case .day:
            return 2
        }
    }

    private var deepLinkPeriodName: String {
        switch self {
        case .hour:
            return "hour"
        case .day:
            return "day"
        }
    }

}

private struct ColorStop {
    let progress: Double
    let red: Double
    let green: Double
    let blue: Double
}

private let dayProgressColorStops = [
    ColorStop(progress: 0.00, red: 25, green: 25, blue: 112),
    ColorStop(progress: 0.12, red: 0, green: 116, blue: 128),
    ColorStop(progress: 0.25, red: 0, green: 190, blue: 96),
    ColorStop(progress: 0.40, red: 172, green: 230, blue: 48),
    ColorStop(progress: 0.55, red: 255, green: 224, blue: 48),
    ColorStop(progress: 0.68, red: 255, green: 186, blue: 32),
    ColorStop(progress: 0.78, red: 255, green: 149, blue: 0),
    ColorStop(progress: 0.90, red: 255, green: 82, blue: 32),
    ColorStop(progress: 1.00, red: 255, green: 36, blue: 36)
]

private func progressColor(for progress: Double) -> Color {
    let clampedProgress = min(1, max(0, progress))
    guard var previousStop = dayProgressColorStops.first else {
        return .orange
    }

    for nextStop in dayProgressColorStops.dropFirst() {
        guard clampedProgress > nextStop.progress else {
            let span = nextStop.progress - previousStop.progress
            let amount = span > 0 ? (clampedProgress - previousStop.progress) / span : 0

            return Color(
                red: interpolate(from: previousStop.red, to: nextStop.red, amount: amount) / 255,
                green: interpolate(from: previousStop.green, to: nextStop.green, amount: amount) / 255,
                blue: interpolate(from: previousStop.blue, to: nextStop.blue, amount: amount) / 255
            )
        }

        previousStop = nextStop
    }

    return Color(
        red: previousStop.red / 255,
        green: previousStop.green / 255,
        blue: previousStop.blue / 255
    )
}

private func interpolate(from start: Double, to end: Double, amount: Double) -> Double {
    start + (end - start) * amount
}
