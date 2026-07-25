import Foundation
import LifeTimerCore
import SwiftUI

struct LifeTimerScreenTimeView: View {
    let configuration: LifeTimerScreenTimeConfiguration

    private var period: LifePeriod {
        configuration.presentation.period
    }

    private var style: TimerPageStyle {
        configuration.presentation.style
    }

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
                .padding(.top, 50)
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
        var coveragePaths = [Path](repeating: Path(), count: 5)
        var hasCoverage = [Bool](repeating: false, count: 5)

        for bucket in buckets {
            let activityFraction = bucket.activityFraction(through: visibleEnd)
            guard bucket.dateInterval.intersects(dateRange), activityFraction > 0 else { continue }

            let start = max(bucket.dateInterval.start, dateRange.start)
            let end = min(bucket.dateInterval.end, visibleEnd)
            guard end > start else { continue }

            let density = hatchDensity(for: activityFraction)
            coveragePaths[density].addPath(
                linearProgressPath(
                    in: rect,
                    startProgress: start.timeIntervalSince(dateRange.start) / dateRange.duration,
                    endProgress: end.timeIntervalSince(dateRange.start) / dateRange.duration
                )
            )
            hasCoverage[density] = true
        }

        let hatchPath = diagonalHatchPath(in: rect)

        for density in 1...4 where hasCoverage[density] {
            context.drawLayer { layer in
                layer.clip(to: coveragePaths[density])
                layer.stroke(
                    hatchPath,
                    with: .color(.lifePhone.opacity(0.46)),
                    style: StrokeStyle(lineWidth: CGFloat(density), lineCap: .butt)
                )
            }
        }
    }

    private func hatchDensity(for activityFraction: Double) -> Int {
        min(4, max(1, Int(ceil(activityFraction * 4))))
    }

    private func linearProgressPath(
        in rect: CGRect,
        startProgress: Double,
        endProgress: Double
    ) -> Path {
        let width = max(1, Int(rect.width.rounded(.down)))
        let height = max(1, Int(rect.height.rounded(.down)))
        let totalPixels = width * height
        let startPixel = min(
            totalPixels,
            max(0, Int(floor(Double(totalPixels) * min(1, max(0, startProgress)))))
        )
        let endPixel = min(
            totalPixels,
            max(0, Int(ceil(Double(totalPixels) * min(1, max(0, endProgress)))))
        )
        guard endPixel > startPixel else { return Path() }

        let startRow = startPixel / width
        let startColumn = startPixel % width
        let endRow = (endPixel - 1) / width
        let endColumn = endPixel - endRow * width
        var path = Path()

        if startRow == endRow {
            path.addRect(
                CGRect(
                    x: rect.minX + CGFloat(startColumn),
                    y: rect.minY + CGFloat(startRow),
                    width: CGFloat(endColumn - startColumn),
                    height: 1
                )
            )
            return path
        }

        path.addRect(
            CGRect(
                x: rect.minX + CGFloat(startColumn),
                y: rect.minY + CGFloat(startRow),
                width: CGFloat(width - startColumn),
                height: 1
            )
        )

        let fullRowCount = endRow - startRow - 1
        if fullRowCount > 0 {
            path.addRect(
                CGRect(
                    x: rect.minX,
                    y: rect.minY + CGFloat(startRow + 1),
                    width: CGFloat(width),
                    height: CGFloat(fullRowCount)
                )
            )
        }

        path.addRect(
            CGRect(
                x: rect.minX,
                y: rect.minY + CGFloat(endRow),
                width: CGFloat(endColumn),
                height: 1
            )
        )

        return path
    }

    private func diagonalHatchPath(in rect: CGRect) -> Path {
        let spacing: CGFloat = 12
        var path = Path()
        var x = rect.minX - rect.height

        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            x += spacing
        }

        return path
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
