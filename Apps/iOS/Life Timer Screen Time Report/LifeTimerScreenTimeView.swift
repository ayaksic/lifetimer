import LifeTimerCore
import SwiftUI

struct LifeTimerScreenTimeView: View {
    let configuration: LifeTimerScreenTimeConfiguration
    let period: LifePeriod
    let style: TimerPageStyle

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawUsage(in: &context, size: size)
            }
        }
        .background(Color.clear)
        .accessibilityHidden(true)
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
        guard dateRange.duration > 0 else { return }

        for bucket in buckets {
            guard
                bucket.dateInterval.intersects(dateRange),
                let representative = bucket.representativeInterval
            else {
                continue
            }

            let start = max(representative.start, dateRange.start)
            let end = min(representative.end, dateRange.end)
            guard end > start else { continue }

            fillLinearProgressRange(
                in: rect,
                startProgress: start.timeIntervalSince(dateRange.start) / dateRange.duration,
                endProgress: end.timeIntervalSince(dateRange.start) / dateRange.duration,
                context: &context
            )
        }
    }

    private func fillLinearProgressRange(
        in rect: CGRect,
        startProgress: Double,
        endProgress: Double,
        context: inout GraphicsContext
    ) {
        let width = max(1, Int(rect.width.rounded(.down)))
        let height = max(1, Int(rect.height.rounded(.down)))
        let totalPixels = width * height
        let startPixel = Int(floor(Double(totalPixels) * min(1, max(0, startProgress))))
        let endPixel = Int(ceil(Double(totalPixels) * min(1, max(0, endProgress))))
        var pixel = startPixel

        while pixel < endPixel {
            let row = pixel / width
            let column = pixel % width
            let rowEnd = min(endPixel, (row + 1) * width)

            context.fill(
                Path(
                    CGRect(
                        x: rect.minX + CGFloat(column),
                        y: rect.minY + CGFloat(row),
                        width: CGFloat(rowEnd - pixel),
                        height: 1
                    )
                ),
                with: .color(.lifePhone)
            )

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
    static let lifePhone = Color(
        red: 38.0 / 255.0,
        green: 166.0 / 255.0,
        blue: 91.0 / 255.0
    )
}
