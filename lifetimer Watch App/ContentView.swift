//
//  ContentView.swift
//  lifetimer Watch App
//
//  Created by Andrew Yaksic on 5/5/26.
//

import SwiftUI
import AVFoundation
import WatchKit
import WidgetKit

private let lifetimeStart = LifePeriod.calendar.date(
    from: DateComponents(year: 1985, month: 4, day: 17, hour: 3, minute: 41)
)!

struct ContentView: View {
    private let pages = TimerPage.all
    private let crownClicksPerPage = 2.0
    private let crownNavigationLimit = 1_000.0

    @AppStorage("lifeTimerUnitPositionEnabled") private var unitPositionEnabled = false
    @State private var doorbellPlayer = DoorbellPlayer()
    @State private var pageIndex = 0
    @State private var crownValue = 0.0
    @State private var pendingCrownDetents = 0.0
    @FocusState private var isCrownFocused: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TimelineView(LifeTimerTimelineSchedule()) { timeline in
                TimerFace(
                    page: pages[pageIndex],
                    now: timeline.date,
                    unitPositionEnabled: unitPositionEnabled
                )
            }

            HandGestureAdvanceButton {
                showNextPeriod()
            }
        }
        .ignoresSafeArea()
        .focusable()
        .focused($isCrownFocused)
        .digitalCrownRotation(
            $crownValue,
            from: -crownNavigationLimit,
            through: crownNavigationLimit,
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height

                    guard abs(horizontal) > abs(vertical) * 1.25 else { return }

                    if horizontal < 0 {
                        showNextPeriod()
                    } else {
                        showPreviousPeriod()
                    }
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.68)
                .onEnded { _ in
                    unitPositionEnabled.toggle()
                    WKInterfaceDevice.current().play(.click)
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    doorbellPlayer.play()
                }
        )
        .onAppear {
            crownValue = 0
            pendingCrownDetents = 0
            isCrownFocused = true
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: crownValue) { oldValue, nextValue in
            handleCrownRotation(from: oldValue, to: nextValue)
        }
        .onOpenURL { url in
            openPage(from: url)
        }
    }

    private func showNextPeriod() {
        pageIndex = wrappedIndex(pageIndex + 1)
        pendingCrownDetents = 0
    }

    private func showPreviousPeriod() {
        pageIndex = wrappedIndex(pageIndex - 1)
        pendingCrownDetents = 0
    }

    private func handleCrownRotation(from oldValue: Double, to nextValue: Double) {
        let detents = nextValue - oldValue
        guard detents != 0 else { return }

        if pendingCrownDetents != 0,
           (pendingCrownDetents > 0) != (detents > 0) {
            pendingCrownDetents = 0
        }

        pendingCrownDetents += detents

        let pageDelta = Int(pendingCrownDetents / crownClicksPerPage)
        guard pageDelta != 0 else { return }

        pageIndex = wrappedIndex(pageIndex + pageDelta)
        pendingCrownDetents -= Double(pageDelta) * crownClicksPerPage
    }

    private func wrappedIndex(_ value: Int) -> Int {
        (value % pages.count + pages.count) % pages.count
    }

    private func openPage(from url: URL) {
        guard let target = TimerPage.deepLinkTarget(for: url),
              let index = pages.firstIndex(where: { $0.period == target.period && $0.style == target.style }) else {
            return
        }

        pageIndex = index
        pendingCrownDetents = 0
    }
}

private struct LifeTimerTimelineSchedule: TimelineSchedule {
    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(
            nextDate: startDate,
            interval: mode == .lowFrequency ? 1 : 1.0 / 30.0
        )
    }

    struct Entries: Sequence, IteratorProtocol {
        var nextDate: Date
        let interval: TimeInterval

        mutating func next() -> Date? {
            let date = nextDate
            nextDate = nextDate.addingTimeInterval(interval)
            return date
        }
    }
}

private struct HandGestureAdvanceButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .frame(width: 1, height: 1)
        }
        .buttonStyle(.plain)
        .handGestureShortcut(.primaryAction)
        .opacity(0.01)
        .accessibilityHidden(true)
    }
}

private final class DoorbellPlayer {
    private var player: AVAudioPlayer?

    init() {
        guard let url = Bundle.main.url(forResource: "doorbell-ding-dong", withExtension: "wav") else {
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1.0
            player?.prepareToPlay()
        } catch {
            player = nil
        }
    }

    func play() {
        guard let player else { return }

        player.currentTime = 0
        player.play()
    }
}

private struct TimerFace: View {
    let page: TimerPage
    let now: Date
    let unitPositionEnabled: Bool

    var body: some View {
        switch page.style {
        case .flow:
            FlowTimerFace(
                period: page.period,
                now: now,
                unitPositionEnabled: unitPositionEnabled
            )
        case .grid:
            GridTimerFace(
                period: page.period,
                now: now,
                unitPositionEnabled: unitPositionEnabled
            )
        }
    }
}

private struct FlowTimerFace: View {
    let period: LifePeriod
    let now: Date
    let unitPositionEnabled: Bool

    private var readoutHeight: Double {
        unitPositionEnabled ? 82.0 : 62.0
    }

    private let readoutClearance = 18.0
    private let readoutMargin = 10.0

    private var progress: Double {
        period.progress(at: now)
    }

    var body: some View {
        GeometryReader { geometry in
            let fillHeight = geometry.size.height * progress
            let markerY = max(0, min(geometry.size.height, fillHeight))
            let readoutOffset = readoutOffset(
                for: markerY,
                in: geometry.size.height
            )

            ZStack(alignment: .top) {
                Color.lifeRemaining

                Color.lifeElapsed
                    .frame(height: fillHeight)
                    .frame(maxWidth: .infinity, alignment: .top)

                Circle()
                    .fill(Color.lifeLive)
                    .overlay(
                        Circle()
                            .stroke(Color.lifeInk, lineWidth: 1)
                    )
                    .frame(width: 8, height: 8)
                    .position(x: geometry.size.width / 2, y: markerY)

                VStack(spacing: 4) {
                    Text(period.label(for: now))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.lifeMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Text(period.percentString(at: now))
                        .font(.system(size: 30, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.lifeInk)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)

                    if unitPositionEnabled {
                        Text(period.unitPositionString(at: now))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.lifeInk)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: readoutOffset)
                .shadow(color: Color.white.opacity(0.7), radius: 10, y: 1)
                .animation(.easeOut(duration: 0.16), value: readoutOffset)
            }
        }
    }

    private func readoutOffset(for markerY: Double, in viewportHeight: Double) -> Double {
        let naturalTop = (viewportHeight - readoutHeight) / 2
        let naturalBottom = naturalTop + readoutHeight
        let collides = markerY >= naturalTop - readoutClearance &&
            markerY <= naturalBottom + readoutClearance

        guard collides else { return 0 }

        let aboveTop = markerY - readoutClearance - readoutHeight
        let belowTop = markerY + readoutClearance
        let canFitAbove = aboveTop >= readoutMargin
        let canFitBelow = belowTop + readoutHeight <= viewportHeight - readoutMargin

        let targetTop: Double
        if canFitAbove && markerY >= viewportHeight / 2 {
            targetTop = aboveTop
        } else if canFitBelow {
            targetTop = belowTop
        } else if canFitAbove {
            targetTop = aboveTop
        } else {
            targetTop = naturalTop
        }

        return (targetTop - naturalTop).rounded()
    }
}

private struct GridTimerFace: View {
    let period: LifePeriod
    let now: Date
    let unitPositionEnabled: Bool

    var body: some View {
        ZStack {
            Canvas(rendersAsynchronously: true) { context, size in
                drawGrid(in: &context, size: size)
            }

            TimerReadout(
                period: period,
                now: now,
                unitPositionEnabled: unitPositionEnabled
            )
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let grid = period.grid(containing: now)
        let segment = period.segment(at: now, totalSegments: grid.segments)
        let xEdges = makeEdges(size.width, count: grid.cols)
        let yEdges = makeEdges(size.height, count: grid.rows)
        var liveMarkerPoint = CGPoint(x: size.width / 2, y: size.height / 2)

        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.lifeRemaining))

        for index in 0..<grid.segments {
            let rect = cellRect(index: index, cols: grid.cols, xEdges: xEdges, yEdges: yEdges)
            let fillRange = period.cellFillRange(for: index, segment: segment)

            let marker: CGPoint
            if fillRange.end > fillRange.start {
                marker = fillProgressRangeRect(
                    rect,
                    startProgress: fillRange.start,
                    endProgress: fillRange.end,
                    in: &context
                )
            } else {
                marker = markerPoint(in: rect, progress: fillRange.end)
            }

            if fillRange.showMarker {
                liveMarkerPoint = marker
            }
        }

        drawGridLines(xEdges: xEdges, yEdges: yEdges, size: size, in: &context)
        drawGridLabels(grid: grid, xEdges: xEdges, yEdges: yEdges, in: &context)
        drawLiveMarker(at: liveMarkerPoint, size: size, in: &context)
    }

    private func makeEdges(_ size: CGFloat, count: Int) -> [CGFloat] {
        (0...count).map { index in
            ((size * CGFloat(index)) / CGFloat(count)).rounded()
        }
    }

    private func cellRect(index: Int, cols: Int, xEdges: [CGFloat], yEdges: [CGFloat]) -> CGRect {
        let row = index / cols
        let col = index % cols

        return CGRect(
            x: xEdges[col],
            y: yEdges[row],
            width: max(1, xEdges[col + 1] - xEdges[col]),
            height: max(1, yEdges[row + 1] - yEdges[row])
        )
    }

    private func fillProgressRangeRect(
        _ rect: CGRect,
        startProgress: Double,
        endProgress: Double,
        in context: inout GraphicsContext
    ) -> CGPoint {
        let clampedStart = min(1, max(0, startProgress))
        let clampedEnd = min(1, max(0, endProgress))
        let cellWidth = max(1, Int(rect.width.rounded(.down)))
        let cellHeight = max(1, Int(rect.height.rounded(.down)))
        let totalPixels = cellWidth * cellHeight
        let startPixel = Int(floor(Double(totalPixels) * clampedStart))
        let endPixel = Int(floor(Double(totalPixels) * clampedEnd))
        let livePixel = min(totalPixels - 1, max(0, endPixel))
        var pixel = startPixel

        if startPixel <= 0, endPixel >= totalPixels {
            context.fill(Path(rect), with: .color(.lifeElapsed))
            return markerPoint(in: rect, progress: clampedEnd)
        }

        while pixel < endPixel {
            let row = pixel / cellWidth
            let col = pixel % cellWidth
            let rowEnd = min(endPixel, (row + 1) * cellWidth)
            let fillRect = CGRect(
                x: rect.minX + CGFloat(col),
                y: rect.minY + CGFloat(row),
                width: CGFloat(rowEnd - pixel),
                height: 1
            )

            context.fill(Path(fillRect), with: .color(.lifeElapsed))
            pixel = rowEnd
        }

        return CGPoint(
            x: rect.minX + CGFloat(livePixel % cellWidth),
            y: rect.minY + CGFloat(livePixel / cellWidth)
        )
    }

    private func markerPoint(in rect: CGRect, progress: Double) -> CGPoint {
        let cellWidth = max(1, Int(rect.width.rounded(.down)))
        let cellHeight = max(1, Int(rect.height.rounded(.down)))
        let totalPixels = cellWidth * cellHeight
        let endPixel = Int(floor(Double(totalPixels) * min(1, max(0, progress))))
        let livePixel = min(totalPixels - 1, max(0, endPixel))

        return CGPoint(
            x: rect.minX + CGFloat(livePixel % cellWidth),
            y: rect.minY + CGFloat(livePixel / cellWidth)
        )
    }

    private func drawGridLines(
        xEdges: [CGFloat],
        yEdges: [CGFloat],
        size: CGSize,
        in context: inout GraphicsContext
    ) {
        var path = Path()

        for index in 1..<(xEdges.count - 1) {
            path.move(to: CGPoint(x: xEdges[index], y: 0))
            path.addLine(to: CGPoint(x: xEdges[index], y: size.height))
        }

        for index in 1..<(yEdges.count - 1) {
            path.move(to: CGPoint(x: 0, y: yEdges[index]))
            path.addLine(to: CGPoint(x: size.width, y: yEdges[index]))
        }

        context.stroke(path, with: .color(.lifeGrid), lineWidth: 1)
    }

    private func drawGridLabels(
        grid: SegmentGrid,
        xEdges: [CGFloat],
        yEdges: [CGFloat],
        in context: inout GraphicsContext
    ) {
        let sampleRect = cellRect(index: 0, cols: grid.cols, xEdges: xEdges, yEdges: yEdges)
        let fontSize = gridLabelFontSize(for: sampleRect)
        guard fontSize >= minimumGridLabelFontSize else { return }

        let lineHeight = fontSize * 1.12

        for index in 0..<grid.segments {
            let rect = cellRect(index: index, cols: grid.cols, xEdges: xEdges, yEdges: yEdges)
            let lines = period.gridLabelLines(for: index, at: now)
            let centerX = rect.midX
            let firstY = rect.midY - (CGFloat(lines.count - 1) * lineHeight) / 2

            for lineIndex in lines.indices {
                context.draw(
                    Text(lines[lineIndex])
                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(.lifeGridLabel),
                    at: CGPoint(x: centerX, y: firstY + CGFloat(lineIndex) * lineHeight),
                    anchor: .center
                )
            }
        }
    }

    private func gridLabelFontSize(for rect: CGRect) -> CGFloat {
        let base = min(rect.width, rect.height)
        let scale: CGFloat = period == .week ? 0.24 : 0.18
        let maximum: CGFloat = period == .week ? 6 : 8

        return min(maximum, max(minimumGridLabelFontSize, floor(base * scale)))
    }

    private var minimumGridLabelFontSize: CGFloat {
        period == .week ? 4 : 5
    }

    private func drawLiveMarker(
        at point: CGPoint,
        size: CGSize,
        in context: inout GraphicsContext
    ) {
        let outer: CGFloat = 7
        let inner: CGFloat = 3
        let outerRect = markerRect(center: point, length: outer, size: size)
        let innerRect = markerRect(center: point, length: inner, size: size)

        context.fill(Path(outerRect), with: .color(.lifeInk))
        context.fill(Path(innerRect), with: .color(.lifeLive))
    }

    private func markerRect(center: CGPoint, length: CGFloat, size: CGSize) -> CGRect {
        CGRect(
            x: min(max(0, center.x - length / 2), max(0, size.width - length)),
            y: min(max(0, center.y - length / 2), max(0, size.height - length)),
            width: length,
            height: length
        )
    }
}

private struct TimerReadout: View {
    let period: LifePeriod
    let now: Date
    let unitPositionEnabled: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(period.label(for: now))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.lifeMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(period.percentString(at: now))
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.lifeInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.35)

            if unitPositionEnabled {
                Text(period.unitPositionString(at: now))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.lifeInk)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: Color.white.opacity(0.7), radius: 10, y: 1)
    }
}

private struct TimerPage: Identifiable {
    let period: LifePeriod
    let style: TimerPageStyle

    var id: String {
        "\(style.rawValue)-\(period.rawValue)"
    }

    static let all: [TimerPage] = {
        LifePeriod.allCases.map { TimerPage(period: $0, style: .flow) }
            + LifePeriod.allCases.map { TimerPage(period: $0, style: .grid) }
    }()

    static func deepLinkTarget(for url: URL) -> TimerPage? {
        guard url.scheme == "lifetimer", url.host == "timer" else {
            return nil
        }

        guard let periodName = url.pathComponents.dropFirst().first,
              let period = LifePeriod.deepLinkPeriod(named: periodName) else {
            return nil
        }

        return TimerPage(period: period, style: .flow)
    }
}

private enum TimerPageStyle: String {
    case flow
    case grid
}

private struct SegmentGrid {
    let rows: Int
    let cols: Int
    let segments: Int
}

private struct SegmentProgress {
    let index: Int
    let progress: Double
}

private struct CellFillRange {
    let start: Double
    let end: Double
    let showMarker: Bool
}

private enum LifePeriod: Int, CaseIterable, Identifiable {
    case hour
    case day
    case week
    case month
    case year
    case lifetime

    var id: Int { rawValue }

    static func deepLinkPeriod(named name: String) -> LifePeriod? {
        switch name {
        case "hour":
            return .hour
        case "day":
            return .day
        default:
            return nil
        }
    }

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

    func progress(at date: Date) -> Double {
        let interval = range(containing: date)
        let duration = interval.end.timeIntervalSince(interval.start)
        guard duration > 0 else { return 0 }

        let elapsed = date.timeIntervalSince(interval.start)
        return min(1, max(0, elapsed / duration))
    }

    func percentString(at date: Date) -> String {
        let percent = progress(at: date) * 100
        return String(format: "%.\(decimalPlaces)f%%", percent)
    }

    func unitPositionString(at date: Date) -> String {
        switch self {
        case .lifetime:
            return "1/1"
        case .year:
            let total = 80
            return "\(currentCalendarYearNumber(at: date, total: total))/\(total)"
        case .month:
            let total = 80 * 12
            return "\(currentCalendarMonthNumber(at: date, total: total))/\(total)"
        case .week:
            return currentDurationUnitString(at: date, unitDuration: 7 * 24 * 60 * 60)
        case .day:
            return currentDurationUnitString(at: date, unitDuration: 24 * 60 * 60)
        case .hour:
            return currentDurationUnitString(at: date, unitDuration: 60 * 60)
        }
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

    func segment(at date: Date, totalSegments: Int) -> SegmentProgress {
        switch self {
        case .month:
            return monthSegment(at: date)
        case .year:
            return yearSegment(at: date)
        case .lifetime:
            return lifetimeSegment(at: date)
        case .hour, .day, .week:
            let interval = range(containing: date)
            return uniformSegment(
                at: date,
                start: interval.start,
                end: interval.end,
                totalSegments: totalSegments
            )
        }
    }

    func cellFillRange(for index: Int, segment: SegmentProgress) -> CellFillRange {
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

    func gridLabelLines(for index: Int, at date: Date) -> [String] {
        if self == .week {
            return [weekdayLabel(for: index), hourLabel(for: index % 24)]
        }

        return [gridLabel(for: index, at: date)]
    }

    private func range(containing date: Date) -> DateInterval {
        let calendar = Self.calendar

        switch self {
        case .hour:
            return calendar.dateInterval(of: .hour, for: date)!
        case .day:
            return calendar.dateInterval(of: .day, for: date)!
        case .week:
            let startOfDay = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: startOfDay)
            let daysFromSunday = weekday - 1
            let start = calendar.date(byAdding: .day, value: -daysFromSunday, to: startOfDay)!
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

    private func monthName(for date: Date) -> String {
        let index = Self.calendar.component(.month, from: date) - 1
        return [
            "January",
            "February",
            "March",
            "April",
            "May",
            "June",
            "July",
            "August",
            "September",
            "October",
            "November",
            "December"
        ][index]
    }

    private func gridLabel(for index: Int, at date: Date) -> String {
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
            let year = Self.calendar.component(.year, from: date)
            let labelDate = Self.calendar.date(
                from: DateComponents(year: year, month: index + 1, day: 1)
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

    private func monthWeek(for date: Date) -> Int {
        let day = Self.calendar.component(.day, from: date)
        let monthStart = Self.calendar.dateInterval(of: .month, for: date)!.start
        let firstWeekdayOffset = Self.calendar.component(.weekday, from: monthStart) - 1
        return ((firstWeekdayOffset + day - 1) / 7) + 1
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
        let calendar = Self.calendar
        let interval = calendar.dateInterval(of: .month, for: date)!
        return calendar.dateComponents([.day], from: interval.start, to: interval.end).day!
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
        let calendar = Self.calendar
        let totalSegments = daysInMonth(date)
        let index = min(totalSegments - 1, max(0, calendar.component(.day, from: date) - 1))
        let interval = calendar.dateInterval(of: .day, for: date)!

        return SegmentProgress(
            index: index,
            progress: min(1, max(0, date.timeIntervalSince(interval.start) / interval.duration))
        )
    }

    private func yearSegment(at date: Date) -> SegmentProgress {
        let calendar = Self.calendar
        let index = calendar.component(.month, from: date) - 1
        let interval = calendar.dateInterval(of: .month, for: date)!

        return SegmentProgress(
            index: index,
            progress: min(1, max(0, date.timeIntervalSince(interval.start) / interval.duration))
        )
    }

    private func lifetimeSegment(at date: Date) -> SegmentProgress {
        let calendar = Self.calendar
        let totalSegments = 80
        let end = calendar.date(byAdding: .year, value: totalSegments, to: lifetimeStart)!
        let index = min(
            totalSegments - 1,
            max(0, calendar.component(.year, from: date) - calendar.component(.year, from: lifetimeStart))
        )
        let progress = date >= end ? 1 : yearProgress(at: date)

        return SegmentProgress(index: index, progress: progress)
    }

    private func yearProgress(at date: Date) -> Double {
        let calendar = Self.calendar
        let interval = calendar.dateInterval(of: .year, for: date)!

        return min(1, max(0, date.timeIntervalSince(interval.start) / interval.duration))
    }

    private func currentCalendarYearNumber(at date: Date, total: Int) -> Int {
        let calendar = Self.calendar
        let end = calendar.date(byAdding: .year, value: total, to: lifetimeStart)!
        guard date < end else { return total }

        var elapsedYears = calendar.component(.year, from: date) -
            calendar.component(.year, from: lifetimeStart)
        let anniversary = calendar.date(byAdding: .year, value: elapsedYears, to: lifetimeStart)!
        if date < anniversary {
            elapsedYears -= 1
        }

        return min(total, max(1, elapsedYears + 1))
    }

    private func currentCalendarMonthNumber(at date: Date, total: Int) -> Int {
        let calendar = Self.calendar
        let end = calendar.date(byAdding: .year, value: 80, to: lifetimeStart)!
        guard date < end else { return total }

        var elapsedMonths = (calendar.component(.year, from: date) -
            calendar.component(.year, from: lifetimeStart)) * 12 +
            (calendar.component(.month, from: date) -
                calendar.component(.month, from: lifetimeStart))
        let monthiversary = calendar.date(byAdding: .month, value: elapsedMonths, to: lifetimeStart)!
        if date < monthiversary {
            elapsedMonths -= 1
        }

        return min(total, max(1, elapsedMonths + 1))
    }

    private func currentDurationUnitString(at date: Date, unitDuration: TimeInterval) -> String {
        let calendar = Self.calendar
        let end = calendar.date(byAdding: .year, value: 80, to: lifetimeStart)!
        let duration = calendarTime(for: end).timeIntervalSince(calendarTime(for: lifetimeStart))
        let elapsed = min(
            duration,
            max(0, calendarTime(for: date).timeIntervalSince(calendarTime(for: lifetimeStart)))
        )
        let total = Int(ceil(duration / unitDuration))
        let current = elapsed >= duration ? total : Int(floor(elapsed / unitDuration)) + 1

        return "\(min(total, max(1, current)))/\(total)"
    }

    private func calendarTime(for date: Date) -> Date {
        let calendar = Self.calendar
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date
        )
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return utcCalendar.date(from: components)!
    }
}

private extension Color {
    static let lifeElapsed = Color(red: 182.0 / 255.0, green: 106.0 / 255.0, blue: 95.0 / 255.0)
    static let lifeRemaining = Color(red: 251.0 / 255.0, green: 248.0 / 255.0, blue: 243.0 / 255.0)
    static let lifeLive = Color(red: 215.0 / 255.0, green: 255.0 / 255.0, blue: 47.0 / 255.0)
    static let lifeInk = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0)
    static let lifeMuted = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0)
    static let lifeGrid = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0).opacity(0.18)
    static let lifeGridLabel = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0).opacity(0.42)
}
