//
//  ContentView.swift
//  Life Timer
//
//  Created by Andrew Yaksic on 5/5/26.
//

import AVFoundation
import LifeTimerCore
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var settings = LifeTimerSettingsRepository.shared.current()
    @State private var pageIndex = 0
    @State private var showingLifetimeEditor = false
    @State private var liveActivityIsRunning = false
    @State private var liveActivityIsAvailable = false
    private let soundPlayer = LifeTimerSoundPlayer()

    private let pages = TimerPage.all

    private var lifetimeStart: Date {
        settings.lifetimeStart
    }

    private var unitPositionEnabled: Bool {
        settings.unitPositionEnabled
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            TimerFace(
                page: pages[pageIndex],
                now: timeline.date,
                lifetimeStart: lifetimeStart,
                unitPositionEnabled: unitPositionEnabled
            )
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .gesture(swipeGesture)
        .onTapGesture(count: 2) {
            handleDoubleTap()
        }
        .onLongPressGesture(minimumDuration: 0.68) {
            handleLongPress()
        }
        .safeAreaInset(edge: .bottom) {
            if pages[pageIndex].period == .hour && pages[pageIndex].style == .flow {
                LiveActivityBar(
                    isRunning: liveActivityIsRunning,
                    isAvailable: liveActivityIsAvailable,
                    startAction: {
                        Task {
                            let status = await LifeTimerLiveActivityManager.startHourTimer(now: Date())
                            applyLiveActivityStatus(status)
                        }
                    },
                    stopAction: {
                        Task {
                            let status = await LifeTimerLiveActivityManager.endHourTimer()
                            applyLiveActivityStatus(status)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingLifetimeEditor) {
            LifetimeEditor(
                lifetimeStart: lifetimeStart,
                resetAction: {
                    settings = LifeTimerSettingsRepository.shared.update(lifetimeStart: defaultLifetimeStart)
                    showingLifetimeEditor = false
                },
                saveAction: { nextStart in
                    settings = LifeTimerSettingsRepository.shared.update(lifetimeStart: nextStart)
                    showingLifetimeEditor = false
                }
            )
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
        }
        .task {
            LifeTimerSettingsRepository.shared.start()
            settings = LifeTimerSettingsRepository.shared.current()
            await monitorLiveActivity()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: LifeTimerSettingsRepository.didChangeNotification)
        ) { _ in
            settings = LifeTimerSettingsRepository.shared.current()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            Task {
                await LifeTimerSettingsRepository.shared.refreshFromCloud()
                let status = await LifeTimerLiveActivityManager.refresh()
                applyLiveActivityStatus(status)
            }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
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
    }

    private func showNextPeriod() {
        pageIndex = wrappedIndex(pageIndex + 1)
    }

    private func showPreviousPeriod() {
        pageIndex = wrappedIndex(pageIndex - 1)
    }

    private func wrappedIndex(_ value: Int) -> Int {
        (value % pages.count + pages.count) % pages.count
    }

    private func handleLongPress() {
        let page = pages[pageIndex]

        if page.period == .hour && page.style == .flow {
            settings = LifeTimerSettingsRepository.shared.update(
                unitPositionEnabled: !settings.unitPositionEnabled
            )
        } else if page.period == .lifetime {
            showingLifetimeEditor = true
        }
    }

    private func handleDoubleTap() {
        let page = pages[pageIndex]

        if page.period == .hour && page.style == .flow {
            soundPlayer.play(.nonsense)
        } else if page.period == .day && page.style == .flow {
            soundPlayer.play(.hope)
        }
    }

    private func applyLiveActivityStatus(_ status: LifeTimerLiveActivityStatus) {
        liveActivityIsRunning = status.isRunning
        liveActivityIsAvailable = status.isAvailable
    }

    private func monitorLiveActivity() async {
        while !Task.isCancelled {
            let status = await LifeTimerLiveActivityManager.refresh()
            applyLiveActivityStatus(status)

            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
        }
    }
}

private enum LifeTimerSound: CaseIterable, Hashable {
    case hope
    case nonsense

    var resource: (name: String, extension: String) {
        switch self {
        case .hope:
            return ("hope", "mp3")
        case .nonsense:
            return ("nonsense", "wav")
        }
    }
}

private final class LifeTimerSoundPlayer {
    private var players: [LifeTimerSound: AVAudioPlayer] = [:]

    init() {
        for sound in LifeTimerSound.allCases {
            let resource = sound.resource
            guard let url = Bundle.main.url(forResource: resource.name, withExtension: resource.extension) else {
                continue
            }

            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[sound] = player
            } catch {
                continue
            }
        }
    }

    func play(_ sound: LifeTimerSound) {
        guard let player = players[sound] else { return }
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

    var body: some View {
        GeometryReader { geometry in
            let size = CGSize(
                width: max(1, geometry.size.width.rounded(.down)),
                height: max(1, geometry.size.height.rounded(.down))
            )
            let progress = period.progress(at: now, lifetimeStart: lifetimeStart)
            let totalPixels = Int(size.width * size.height)
            let elapsedPixels = Int(floor(Double(totalPixels) * progress))
            let fullRows = elapsedPixels / Int(size.width)
            let partialPixels = elapsedPixels - fullRows * Int(size.width)
            let livePixel = min(totalPixels - 1, max(0, elapsedPixels))
            let marker = CGPoint(
                x: CGFloat(livePixel % Int(size.width)),
                y: CGFloat(livePixel / Int(size.width))
            )

            ZStack {
                Canvas { context, _ in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.lifeRemaining))

                    if fullRows > 0 {
                        context.fill(
                            Path(CGRect(x: 0, y: 0, width: size.width, height: CGFloat(fullRows))),
                            with: .color(.lifeElapsed)
                        )
                    }

                    if partialPixels > 0 && CGFloat(fullRows) < size.height {
                        context.fill(
                            Path(CGRect(x: 0, y: CGFloat(fullRows), width: CGFloat(partialPixels), height: 1)),
                            with: .color(.lifeElapsed)
                        )
                    }

                    drawLiveMarker(at: marker, size: size, in: &context)
                }

                TimerReadout(
                    period: period,
                    now: now,
                    lifetimeStart: lifetimeStart,
                    unitPositionEnabled: unitPositionEnabled
                )
            }
        }
    }
}

private struct GridTimerFace: View {
    let period: LifePeriod
    let now: Date
    let lifetimeStart: Date
    let unitPositionEnabled: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    drawGrid(in: &context, size: size)
                }

                TimerReadout(
                    period: period,
                    now: now,
                    lifetimeStart: lifetimeStart,
                    unitPositionEnabled: unitPositionEnabled
                )
            }
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let grid = period.grid(containing: now)
        let segment = period.segment(at: now, lifetimeStart: lifetimeStart, totalSegments: grid.segments)
        let xEdges = makeEdges(size.width, count: grid.cols)
        let yEdges = makeEdges(size.height, count: grid.rows)
        var liveMarkerPoint = CGPoint(x: size.width / 2, y: size.height / 2)

        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.lifeRemaining))

        for index in 0..<grid.segments {
            let rect = cellRect(index: index, cols: grid.cols, xEdges: xEdges, yEdges: yEdges)
            let fillRange = period.cellFillRange(for: index, segment: segment, lifetimeStart: lifetimeStart)

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
        let cellWidth = max(1, Int(rect.width.rounded(.down)))
        let cellHeight = max(1, Int(rect.height.rounded(.down)))
        let totalPixels = cellWidth * cellHeight
        let startPixel = Int(floor(Double(totalPixels) * min(1, max(0, startProgress))))
        let endPixel = Int(floor(Double(totalPixels) * min(1, max(0, endProgress))))
        let livePixel = min(totalPixels - 1, max(0, endPixel))
        var pixel = startPixel

        while pixel < endPixel {
            let row = pixel / cellWidth
            let col = pixel % cellWidth
            let rowEnd = min(endPixel, (row + 1) * cellWidth)

            context.fill(
                Path(CGRect(
                    x: rect.minX + CGFloat(col),
                    y: rect.minY + CGFloat(row),
                    width: CGFloat(rowEnd - pixel),
                    height: 1
                )),
                with: .color(.lifeElapsed)
            )

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
        guard fontSize >= 5 else { return }

        let lineHeight = fontSize * 1.18

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
        let scale: CGFloat = period == .week ? 0.25 : 0.16
        let minimum: CGFloat = period == .week ? 8 : 6
        let maximum: CGFloat = period == .week ? 12 : 11

        return min(maximum, max(minimum, floor(base * scale)))
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
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.lifeMuted)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(period.percentString(at: now, lifetimeStart: lifetimeStart))
                .font(.system(size: 54, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.lifeInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.35)

            if unitPositionEnabled {
                Text(period.unitPositionLabel(at: now, lifetimeStart: lifetimeStart))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.lifeMuted)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: Color.white.opacity(0.72), radius: 18, y: 1)
    }
}

private struct LiveActivityBar: View {
    let isRunning: Bool
    let isAvailable: Bool
    let startAction: () -> Void
    let stopAction: () -> Void

    var body: some View {
        HStack {
            Spacer()

            Button(action: isRunning ? stopAction : startAction) {
                Image(systemName: isRunning ? "stop.fill" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(isRunning ? Color.lifeLive : Color.lifeRemaining)
                    .frame(width: 34, height: 34)
                    .background(Color.lifeInk.opacity(isRunning ? 0.92 : 0.72), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
            .opacity(isAvailable ? 1 : 0)
            .accessibilityLabel(isRunning ? "End hour Live Activity" : "Start hour Live Activity")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(.clear)
    }
}

private struct LifetimeEditor: View {
    let lifetimeStart: Date
    let resetAction: () -> Void
    let saveAction: (Date) -> Void

    @State private var draftStart: Date

    init(lifetimeStart: Date, resetAction: @escaping () -> Void, saveAction: @escaping (Date) -> Void) {
        self.lifetimeStart = lifetimeStart
        self.resetAction = resetAction
        self.saveAction = saveAction
        _draftStart = State(initialValue: lifetimeStart)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Life starts", selection: $draftStart, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
            }
            .scrollContentBackground(.hidden)
            .background(Color.lifeRemaining)
            .navigationTitle("Lifetime")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset", action: resetAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        saveAction(draftStart)
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

private func drawLiveMarker(at point: CGPoint, size: CGSize, in context: inout GraphicsContext) {
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

extension Color {
    static let lifeElapsed = Color(red: 182.0 / 255.0, green: 106.0 / 255.0, blue: 95.0 / 255.0)
    static let lifeRemaining = Color(red: 251.0 / 255.0, green: 248.0 / 255.0, blue: 243.0 / 255.0)
    static let lifeLive = Color(red: 215.0 / 255.0, green: 255.0 / 255.0, blue: 47.0 / 255.0)
    static let lifeInk = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0)
    static let lifeMuted = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0).opacity(0.62)
    static let lifeGrid = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0).opacity(0.18)
    static let lifeGridLabel = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0).opacity(0.42)
}
