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

    var smallPercentText: String {
        String(format: "%.\(period.smallPercentDecimalPlaces)f%%", progress * 100)
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

        while updateDate <= horizon && entries.count < period.maximumTimelineEntries {
            entries.append(entry(for: updateDate))
            updateDate = period.nextTimelineUpdate(after: updateDate)
        }

        completion(Timeline(entries: entries, policy: .atEnd))
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

struct LifeTimerCombinedEntry: TimelineEntry {
    let date: Date
    let hour: LifeTimerEntry
    let day: LifeTimerEntry
}

struct LifeTimerCombinedProvider: TimelineProvider {
    func placeholder(in context: Context) -> LifeTimerCombinedEntry {
        entry(for: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (LifeTimerCombinedEntry) -> Void) {
        completion(entry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LifeTimerCombinedEntry>) -> Void) {
        let now = Date()
        let horizon = LifePeriod.hour.timelineHorizon(after: now)

        var entries = [entry(for: now)]
        var updateDate = LifePeriod.hour.nextTimelineUpdate(after: now)

        while updateDate <= horizon && entries.count < LifePeriod.hour.maximumTimelineEntries {
            entries.append(entry(for: updateDate))
            updateDate = LifePeriod.hour.nextTimelineUpdate(after: updateDate)
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(for date: Date) -> LifeTimerCombinedEntry {
        LifeTimerCombinedEntry(
            date: date,
            hour: entry(for: .hour, at: date),
            day: entry(for: .day, at: date)
        )
    }

    private func entry(for period: LifePeriod, at date: Date) -> LifeTimerEntry {
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
                complicationProgressView(allowsDateRelativeProgress: false)
                    .progressViewStyle(.circular)

                Text(entry.smallPercentText)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
            }

        case .accessoryCorner:
            complicationProgressView()
                .progressViewStyle(.circular)
                .widgetLabel {
                    Text(entry.smallPercentText)
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
                    complicationProgressView()
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

    @ViewBuilder
    private func complicationProgressView(allowsDateRelativeProgress: Bool = true) -> some View {
        if entry.period.usesDateRelativeProgress && allowsDateRelativeProgress {
            ProgressView(timerInterval: entry.periodStart...entry.periodEnd, countsDown: false)
                .tint(progressColor(for: entry.progress))
        } else {
            ProgressView(value: entry.progress)
                .tint(progressColor(for: entry.progress))
        }
    }
}

struct LifeTimerCombinedComplicationView: View {
    let entry: LifeTimerCombinedEntry

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            LifeTimerCombinedProgressColumn(entry: entry.hour)

            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 1)
                .padding(.vertical, 4)

            LifeTimerCombinedProgressColumn(entry: entry.day)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct LifeTimerCombinedProgressColumn: View {
    let entry: LifeTimerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.period.complicationLabel)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(entry.percentText)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            ProgressView(value: entry.progress)
                .tint(progressColor(for: entry.progress))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct LifeTimerCombinedComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LifeTimerCombinedComplication", provider: LifeTimerCombinedProvider()) { entry in
            LifeTimerCombinedComplicationView(entry: entry)
                .widgetURL(LifePeriod.hour.deepLinkURL)
        }
        .configurationDisplayName("Life Timer Duo")
        .description("Shows current-hour and current-day progress side by side.")
        .supportedFamilies([
            .accessoryRectangular
        ])
    }
}

@main
struct LifeTimerComplicationBundle: WidgetBundle {
    var body: some Widget {
        LifeTimerComplication(period: .day)
        LifeTimerComplication(period: .hour)
        LifeTimerCombinedComplication()
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
        switch self {
        case .hour:
            return date.addingTimeInterval(90 * 60)
        case .day:
            return date.addingTimeInterval(15 * 60)
        }
    }

    private var timelineCadence: TimeInterval {
        switch self {
        case .hour:
            // The visible percentage is static text from each timeline entry.
            // Minute entries keep the hour face fresh without flooding watchOS
            // with hundreds of snapshots it is likely to throttle or coalesce.
            return 60
        case .day:
            return 60
        }
    }

    fileprivate var maximumTimelineEntries: Int {
        switch self {
        case .hour:
            return 96
        case .day:
            return 20
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

    fileprivate var smallPercentDecimalPlaces: Int {
        switch self {
        case .hour:
            return 0
        case .day:
            return 1
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

    fileprivate var usesDateRelativeProgress: Bool {
        switch self {
        case .hour:
            return true
        case .day:
            return false
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
