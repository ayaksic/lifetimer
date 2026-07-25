import Foundation
import LifeTimerCore
import SwiftUI

struct LifeTimerScreenTimeView: View {
    let configuration: LifeTimerScreenTimeConfiguration
    let period: LifePeriod
    let style: TimerPageStyle

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geometry in
                Canvas { context, size in
                    drawUsage(in: &context, size: size)
                }
                .accessibilityHidden(true)
            }

            Text(screenOnPercentageLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.lifeInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.lifeRemaining.opacity(0.88), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.lifePhone.opacity(0.72), lineWidth: 1)
                }
                .padding(.top, 8)
                .padding(.trailing, 12)
                .accessibilityLabel("Screen-on time \(screenOnPercentageLabel)")
        }
        .background(Color.clear)
    }

    private var screenOnPercentageLabel: String {
        let representedRange = period.range(
            containing: configuration.referenceDate,
            lifetimeStart: configuration.lifetimeStart
        )
        let fraction = LifeTimerUsageBucket.representedActivityFraction(
            in: configuration.buckets,
            range: representedRange,
            through: configuration.referenceDate
        )
        return String(format: "SCREEN %.1f%%", fraction * 100)
    }

    private func drawUsage(in context: inout GraphicsContext, size: CGSize) {
        let referenceDate = configuration.referenceDate
        let lifetimeStart = configuration.lifetimeStart

        switch style {
        case .flow:
            drawBuckets(
                configuration.buckets,
                in: period.range(containing: referenceDate, lifetimeStart: lifetimeStart),
                rect: CGRect(origin: .zero, size: size),
                context: &context
            )
        case .grid:
            drawGrid(
                referenceDate: referenceDate,
                lifetimeStart: lifetimeStart,
                context: &context,
                size: size
            )
        }
    }

    private func drawGrid(
        referenceDate: Date,
        lifetimeStart: Date,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let grid = period.grid(containing: referenceDate)
        let xEdges = makeEdges(size.width, count: grid.cols)
        let yEdges = makeEdges(size.height, count: grid.rows)
        let intervals = period.gridDateIntervals(
            containing: referenceDate,
            lifetimeStart: lifetimeStart
        )

        for index in intervals.indices {
            guard index < grid.segments else { break }
            drawBuckets(
                configuration.buckets,
                in: intervals[index],
                rect: cellRect(index: index, cols: grid.cols, xEdges: xEdges, yEdges: yEdges),
                context: &context
            )
        }
    }

    private func drawBuckets(
        _ buckets: [LifeTimerUsageBucket],
        in dateRange: DateInterval,
        rect: CGRect,
        context: inout GraphicsContext
    ) {
        let visibleEnd = min(dateRange.end, configuration.referenceDate)
        guard dateRange.duration > 0, visibleEnd > dateRange.start else { return }

        for bucket in buckets {
            let activityFraction = bucket.activityFraction(through: visibleEnd)
            guard bucket.dateInterval.intersects(dateRange), activityFraction > 0 else { continue }

            let start = max(bucket.dateInterval.start, dateRange.start)
            let end = min(bucket.dateInterval.end, visibleEnd)
            guard end > start else { continue }

            fillHatchedProgressRange(
                in: rect,
                startProgress: start.timeIntervalSince(dateRange.start) / dateRange.duration,
                endProgress: end.timeIntervalSince(dateRange.start) / dateRange.duration,
                activityFraction: activityFraction,
                context: &context
            )
        }
    }

    private func fillHatchedProgressRange(
        in rect: CGRect,
        startProgress: Double,
        endProgress: Double,
        activityFraction: Double,
        context: inout GraphicsContext
    ) {
        let width = max(1, Int(rect.width.rounded(.down)))
        let height = max(1, Int(rect.height.rounded(.down)))
        let totalPixels = width * height
        let startPixel = Int(floor(Double(totalPixels) * min(1, max(0, startProgress))))
        let endPixel = Int(ceil(Double(totalPixels) * min(1, max(0, endProgress))))
        let patternSize = 12
        let activeSlots = min(
            4,
            max(1, Int(ceil(activityFraction * 4)))
        )
        var pixel = startPixel

        while pixel < endPixel {
            let row = pixel / width
            let rowEnd = min(endPixel, (row + 1) * width)
            let startColumn = pixel % width
            let endColumn = rowEnd - row * width
            let stagger = (row * 3) % patternSize
            var hatchStart = ((startColumn + stagger) / patternSize) * patternSize - stagger

            if hatchStart + activeSlots <= startColumn {
                hatchStart += patternSize
            }

            while hatchStart < endColumn {
                let runStart = max(startColumn, hatchStart)
                let runEnd = min(endColumn, hatchStart + activeSlots)

                if runEnd > runStart {
                    context.fill(
                        Path(
                            CGRect(
                                x: rect.minX + CGFloat(runStart),
                                y: rect.minY + CGFloat(row),
                                width: CGFloat(runEnd - runStart),
                                height: 1
                            )
                        ),
                        with: .color(.lifePhone.opacity(0.46))
                    )
                }

                hatchStart += patternSize
            }

            pixel = rowEnd
        }
    }

    private func makeEdges(_ size: CGFloat, count: Int) -> [CGFloat] {
        (0...count).map { index in
            ((size * CGFloat(index)) / CGFloat(count)).rounded()
        }
    }

    private func cellRect(
        index: Int,
        cols: Int,
        xEdges: [CGFloat],
        yEdges: [CGFloat]
    ) -> CGRect {
        let row = index / cols
        let col = index % cols
        return CGRect(
            x: xEdges[col],
            y: yEdges[row],
            width: max(1, xEdges[col + 1] - xEdges[col]),
            height: max(1, yEdges[row + 1] - yEdges[row])
        )
    }
}

private extension Color {
    static let lifeRemaining = Color(
        red: 251.0 / 255.0,
        green: 248.0 / 255.0,
        blue: 243.0 / 255.0
    )
    static let lifeInk = Color(
        red: 22.0 / 255.0,
        green: 19.0 / 255.0,
        blue: 18.0 / 255.0
    )
    static let lifePhone = Color(
        red: 38.0 / 255.0,
        green: 166.0 / 255.0,
        blue: 91.0 / 255.0
    )
}
