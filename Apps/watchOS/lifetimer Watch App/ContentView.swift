//
//  ContentView.swift
//  lifetimer Watch App
//
//  Created by Andrew Yaksic on 5/5/26.
//

import SwiftUI
import AVFoundation
import LifeTimerCore
import WatchKit
import WidgetKit

struct ContentView: View {
    private let pages = TimerPage.all
    private let crownClicksPerPage = 2.0
    private let crownNavigationLimit = 1_000.0

    @State private var settings = LifeTimerSettingsRepository.shared.current()
    @State private var diagnostics = LifeTimerSettingsRepository.shared.diagnostics()
    @State private var doorbellPlayer = DoorbellPlayer()
    @State private var showingDiagnostics = false
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
                    lifetimeStart: settings.lifetimeStart,
                    unitPositionEnabled: unitPositionEnabled
                )
            }

            HandGestureAdvanceButton {
                showNextPeriod()
            }

            Button {
                diagnostics = LifeTimerSettingsRepository.shared.diagnostics()
                showingDiagnostics = true
            } label: {
                Image(systemName: diagnostics.isPending ? "icloud.and.arrow.up" : "info.circle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.lifeInk.opacity(0.58))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityLabel("Life Timer diagnostics")
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
                    settings = LifeTimerSettingsRepository.shared.update(
                        unitPositionEnabled: !settings.unitPositionEnabled
                    )
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
            LifeTimerSettingsRepository.shared.start()
            settings = LifeTimerSettingsRepository.shared.current()
            diagnostics = LifeTimerSettingsRepository.shared.diagnostics()
            Task {
                await LifeTimerSettingsRepository.shared.refreshFromCloud()
            }
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
        .onReceive(
            NotificationCenter.default.publisher(for: LifeTimerSettingsRepository.didChangeNotification)
        ) { _ in
            settings = LifeTimerSettingsRepository.shared.current()
            diagnostics = LifeTimerSettingsRepository.shared.diagnostics()
            WidgetCenter.shared.reloadAllTimelines()
        }
        .sheet(isPresented: $showingDiagnostics) {
            WatchDiagnosticsView(
                identity: .current(),
                diagnostics: diagnostics,
                presentation: pages[pageIndex]
            )
        }
    }

    private func showNextPeriod() {
        pageIndex = wrappedIndex(pageIndex + 1)
        pendingCrownDetents = 0
    }

    private var unitPositionEnabled: Bool {
        settings.unitPositionEnabled
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

private struct WatchDiagnosticsView: View {
    let identity: LifeTimerReleaseIdentity
    let diagnostics: LifeTimerSyncDiagnostics
    let presentation: TimerPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Life Timer")
                    .font(.headline)
                diagnostic("Build", "\(identity.version) (\(identity.build))")
                diagnostic("Commit", identity.commit)
                diagnostic("Sync", diagnostics.status.rawValue)
                diagnostic("Pending", diagnostics.isPending ? "Yes" : "No")
                diagnostic("Revision", formatted(diagnostics.settingsRevision))
                diagnostic("Last sync", formatted(diagnostics.lastSuccessfulSync))
                diagnostic("CloudKit", "\(identity.cloudKitEnvironment) · \(identity.cloudKitContainer)")
                diagnostic("App Group", LifeTimerSettingsStorage.appGroupIdentifier)
                diagnostic("Local view", "\(presentation.period) / \(presentation.style.rawValue)")
                Text("The local view is not synchronized. The Watch refreshes through CloudKit; no WatchConnectivity path is active.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func diagnostic(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.monospaced())
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date, date != .distantPast else { return "Never" }
        return date.formatted(date: .numeric, time: .shortened)
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
    let lifetimeStart: Date
    let unitPositionEnabled: Bool

    var body: some View {
        switch page.style {
        case .flow:
            FlowTimerFace(
                period: page.period,
                now: now,
                lifetimeStart: lifetimeStart,
                unitPositionEnabled: unitPositionEnabled
            )
        case .grid:
            GridTimerFace(
                period: page.period,
                now: now,
                lifetimeStart: lifetimeStart,
                unitPositionEnabled: unitPositionEnabled
            )
        }
    }
}

private struct FlowTimerFace: View {
    let period: LifePeriod
    let now: Date
    let lifetimeStart: Date
    let unitPositionEnabled: Bool

    private var readoutHeight: Double {
        TimerReadoutLayout.height(unitPositionEnabled: unitPositionEnabled)
    }

    private var progress: Double {
        period.progress(at: now, lifetimeStart: lifetimeStart)
    }

    var body: some View {
        GeometryReader { geometry in
            let fillHeight = geometry.size.height * progress
            let markerY = max(0, min(geometry.size.height, fillHeight))
            let readoutOffset = TimerReadoutLayout.offset(
                for: markerY,
                in: geometry.size.height,
                readoutHeight: readoutHeight
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

                    Text(period.percentString(at: now, lifetimeStart: lifetimeStart))
                        .font(.system(size: 30, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.lifeInk)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.35)

                    if unitPositionEnabled {
                        Text(period.unitPositionLabel(at: now, lifetimeStart: lifetimeStart))
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

}

private struct GridTimerFace: View {
    let period: LifePeriod
    let now: Date
    let lifetimeStart: Date
    let unitPositionEnabled: Bool

    private var readoutHeight: Double {
        TimerReadoutLayout.height(unitPositionEnabled: unitPositionEnabled)
    }

    var body: some View {
        GeometryReader { geometry in
            let grid = period.grid(containing: now)
            let segment = period.segment(at: now, lifetimeStart: lifetimeStart, totalSegments: grid.segments)
            let xEdges = makeEdges(geometry.size.width, count: grid.cols)
            let yEdges = makeEdges(geometry.size.height, count: grid.rows)
            let liveMarkerPoint = liveMarkerPoint(grid: grid, segment: segment, xEdges: xEdges, yEdges: yEdges)
            let readoutOffset = TimerReadoutLayout.offset(
                for: liveMarkerPoint.y,
                in: geometry.size.height,
                readoutHeight: readoutHeight
            )

            ZStack {
                Canvas(rendersAsynchronously: true) { context, size in
                    drawGrid(
                        grid: grid,
                        segment: segment,
                        xEdges: xEdges,
                        yEdges: yEdges,
                        liveMarkerPoint: liveMarkerPoint,
                        in: &context,
                        size: size
                    )
                }

                TimerReadout(
                    period: period,
                    now: now,
                    lifetimeStart: lifetimeStart,
                    unitPositionEnabled: unitPositionEnabled
                )
                .offset(y: readoutOffset)
                .animation(.easeOut(duration: 0.16), value: readoutOffset)
            }
        }
    }

    private func drawGrid(
        grid: SegmentGrid,
        segment: SegmentProgress,
        xEdges: [CGFloat],
        yEdges: [CGFloat],
        liveMarkerPoint: CGPoint,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.lifeRemaining))

        for index in 0..<grid.segments {
            let rect = cellRect(index: index, cols: grid.cols, xEdges: xEdges, yEdges: yEdges)
            let fillRange = period.cellFillRange(for: index, segment: segment, lifetimeStart: lifetimeStart)

            if fillRange.end > fillRange.start {
                _ = fillProgressRangeRect(
                    rect,
                    startProgress: fillRange.start,
                    endProgress: fillRange.end,
                    in: &context
                )
            } else {
                continue
            }
        }

        drawGridLines(xEdges: xEdges, yEdges: yEdges, size: size, in: &context)
        drawGridLabels(grid: grid, xEdges: xEdges, yEdges: yEdges, in: &context)
        drawLiveMarker(at: liveMarkerPoint, size: size, in: &context)
    }

    private func liveMarkerPoint(
        grid: SegmentGrid,
        segment: SegmentProgress,
        xEdges: [CGFloat],
        yEdges: [CGFloat]
    ) -> CGPoint {
        for index in 0..<grid.segments {
            let fillRange = period.cellFillRange(for: index, segment: segment, lifetimeStart: lifetimeStart)
            guard fillRange.showMarker else { continue }

            let rect = cellRect(index: index, cols: grid.cols, xEdges: xEdges, yEdges: yEdges)
            return markerPoint(in: rect, progress: fillRange.end)
        }

        return CGPoint(
            x: xEdges.last.map { $0 / 2 } ?? 0,
            y: yEdges.last.map { $0 / 2 } ?? 0
        )
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
            let lines = period.gridLabelLines(for: index, at: now, lifetimeStart: lifetimeStart)
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

private enum TimerReadoutLayout {
    private static let clearance = 18.0
    private static let margin = 10.0

    static func height(unitPositionEnabled: Bool) -> Double {
        unitPositionEnabled ? 82.0 : 62.0
    }

    static func offset(for markerY: Double, in viewportHeight: Double, readoutHeight: Double) -> Double {
        let naturalTop = (viewportHeight - readoutHeight) / 2
        let naturalBottom = naturalTop + readoutHeight
        let collides = markerY >= naturalTop - clearance &&
            markerY <= naturalBottom + clearance

        guard collides else { return 0 }

        let aboveTop = markerY - clearance - readoutHeight
        let belowTop = markerY + clearance
        let canFitAbove = aboveTop >= margin
        let canFitBelow = belowTop + readoutHeight <= viewportHeight - margin

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

private struct TimerReadout: View {
    let period: LifePeriod
    let now: Date
    let lifetimeStart: Date
    let unitPositionEnabled: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(period.label(for: now))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.lifeMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(period.percentString(at: now, lifetimeStart: lifetimeStart))
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.lifeInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.35)

            if unitPositionEnabled {
                Text(period.unitPositionLabel(at: now, lifetimeStart: lifetimeStart))
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

private extension Color {
    static let lifeElapsed = Color(red: 182.0 / 255.0, green: 106.0 / 255.0, blue: 95.0 / 255.0)
    static let lifeRemaining = Color(red: 251.0 / 255.0, green: 248.0 / 255.0, blue: 243.0 / 255.0)
    static let lifeLive = Color(red: 215.0 / 255.0, green: 255.0 / 255.0, blue: 47.0 / 255.0)
    static let lifeInk = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0)
    static let lifeMuted = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0)
    static let lifeGrid = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0).opacity(0.18)
    static let lifeGridLabel = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0).opacity(0.42)
}
