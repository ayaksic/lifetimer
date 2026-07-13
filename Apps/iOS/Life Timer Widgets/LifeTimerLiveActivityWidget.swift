import ActivityKit
import LifeTimerCore
import SwiftUI
import WidgetKit

@main
struct LifeTimerWidgets: WidgetBundle {
    var body: some Widget {
        if #available(iOSApplicationExtension 16.2, *) {
            LifeTimerHourLiveActivity()
        }
    }
}

@available(iOSApplicationExtension 16.2, *)
struct LifeTimerHourLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LifeTimerHourAttributes.self) { context in
            HourLockScreenView(context: context)
                .activityBackgroundTint(Color.lifeInk)
                .activitySystemActionForegroundColor(Color.lifeRemaining)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HourProgressBar(
                        start: context.attributes.hourStart,
                        end: context.attributes.hourEnd,
                        fallbackProgress: context.state.progress,
                        height: 16
                    )
                    .padding(.horizontal, 2)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HourProgressBar(
                        start: context.attributes.hourStart,
                        end: context.attributes.hourEnd,
                        fallbackProgress: context.state.progress,
                        height: 14
                    )
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                HourMiniProgressDot(
                    start: context.attributes.hourStart,
                    end: context.attributes.hourEnd,
                    fallbackProgress: context.state.progress,
                    size: 12
                )
            } compactTrailing: {
                HourMiniProgressBar(
                    start: context.attributes.hourStart,
                    end: context.attributes.hourEnd,
                    fallbackProgress: context.state.progress,
                    height: 8
                )
                .frame(width: 46)
            } minimal: {
                HourMiniProgressDot(
                    start: context.attributes.hourStart,
                    end: context.attributes.hourEnd,
                    fallbackProgress: context.state.progress,
                    size: 18
                )
            }
            .keylineTint(Color.lifeHeatYellow)
        }
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct HourLockScreenView: View {
    let context: ActivityViewContext<LifeTimerHourAttributes>

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            HourProgressBar(
                start: context.attributes.hourStart,
                end: context.attributes.hourEnd,
                fallbackProgress: context.state.progress,
                height: 16
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct HourProgressBar: View {
    let start: Date
    let end: Date
    let fallbackProgress: Double
    let height: CGFloat

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.lifeRemaining.opacity(0.18))

            HourGradientFill(progress: progress)

            HourQuarterTicks(height: height)
        }
        .clipShape(Capsule(style: .continuous))
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityLabel("Current hour progress")
    }

    private var progress: Double {
        max(fallbackProgress, hourProgress(at: Date(), start: start, end: end))
    }
}

private struct HourGradientFill: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            LinearGradient.lifeHeat
                .frame(width: geometry.size.width)
                .frame(maxHeight: .infinity)
                .mask(alignment: .leading) {
                    Capsule(style: .continuous)
                        .frame(width: geometry.size.width * progress)
                }
        }
    }
}

private struct HourQuarterTicks: View {
    let height: CGFloat

    private let fractions = [0.25, 0.5, 0.75]

    var body: some View {
        GeometryReader { geometry in
            ForEach(fractions, id: \.self) { fraction in
                Capsule(style: .continuous)
                    .fill(Color.lifeInk.opacity(0.5))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.lifeRemaining.opacity(0.28), lineWidth: 0.5)
                    }
                    .frame(width: 1, height: max(3, height * 0.68))
                    .position(
                        x: geometry.size.width * fraction,
                        y: geometry.size.height / 2
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct HourMiniProgressBar: View {
    let start: Date
    let end: Date
    let fallbackProgress: Double
    let height: CGFloat

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.lifeRemaining.opacity(0.16))

            HourMiniGradientFill(progress: progress)

            HourMiniTicks(height: height)
        }
        .clipShape(Capsule(style: .continuous))
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityLabel("Current hour progress")
    }

    private var progress: Double {
        max(fallbackProgress, hourProgress(at: Date(), start: start, end: end))
    }
}

private struct HourMiniGradientFill: View {
    let progress: Double

    var body: some View {
        Canvas { context, size in
            let clampedProgress = min(1, max(0, progress))
            let fillWidth = size.width * clampedProgress
            guard fillWidth > 0 else { return }

            let capsule = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            var fillContext = context
            fillContext.clip(to: Path(CGRect(x: 0, y: 0, width: fillWidth, height: size.height)))
            fillContext.fill(
                capsule,
                with: .linearGradient(
                    lifeHeatGradient,
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                )
            )
        }
        .allowsHitTesting(false)
    }
}

private struct HourMiniTicks: View {
    let height: CGFloat

    private let fractions = [0.25, 0.5, 0.75]

    var body: some View {
        GeometryReader { geometry in
            ForEach(fractions, id: \.self) { fraction in
                Capsule(style: .continuous)
                    .fill(Color.lifeInk.opacity(0.32))
                    .frame(width: 0.75, height: max(2, height * 0.5))
                    .position(
                        x: geometry.size.width * fraction,
                        y: geometry.size.height / 2
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct HourMiniProgressDot: View {
    let start: Date
    let end: Date
    let fallbackProgress: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.lifeRemaining.opacity(0.22), lineWidth: max(1.5, size * 0.14))

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progressColor(for: progress),
                    style: StrokeStyle(
                        lineWidth: max(1.5, size * 0.14),
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(progressColor(for: progress))
                .frame(width: max(3, size * 0.34), height: max(3, size * 0.34))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Current hour progress")
    }

    private var progress: Double {
        max(fallbackProgress, hourProgress(at: Date(), start: start, end: end))
    }
}

private func hourProgress(at date: Date, start: Date, end: Date) -> Double {
    let duration = max(1, end.timeIntervalSince(start))
    let elapsed = date.timeIntervalSince(start)
    return min(1, max(0, elapsed / duration))
}

private extension Color {
    static let lifeHeatMidnight = Color(red: 25.0 / 255.0, green: 25.0 / 255.0, blue: 112.0 / 255.0)
    static let lifeHeatTeal = Color(red: 0.0 / 255.0, green: 116.0 / 255.0, blue: 128.0 / 255.0)
    static let lifeHeatGreen = Color(red: 0.0 / 255.0, green: 190.0 / 255.0, blue: 96.0 / 255.0)
    static let lifeHeatLime = Color(red: 172.0 / 255.0, green: 230.0 / 255.0, blue: 48.0 / 255.0)
    static let lifeHeatYellow = Color(red: 255.0 / 255.0, green: 224.0 / 255.0, blue: 48.0 / 255.0)
    static let lifeHeatGold = Color(red: 255.0 / 255.0, green: 186.0 / 255.0, blue: 32.0 / 255.0)
    static let lifeHeatOrange = Color(red: 255.0 / 255.0, green: 149.0 / 255.0, blue: 0.0 / 255.0)
    static let lifeHeatVermilion = Color(red: 255.0 / 255.0, green: 82.0 / 255.0, blue: 32.0 / 255.0)
    static let lifeHeatRed = Color(red: 255.0 / 255.0, green: 36.0 / 255.0, blue: 36.0 / 255.0)
    static let lifeRemaining = Color(red: 251.0 / 255.0, green: 248.0 / 255.0, blue: 243.0 / 255.0)
    static let lifeInk = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0)
    static let lifeMutedLight = Color(red: 251.0 / 255.0, green: 248.0 / 255.0, blue: 243.0 / 255.0).opacity(0.68)
}

private extension LinearGradient {
    static let lifeHeat = LinearGradient(
        stops: [
            .init(color: .lifeHeatMidnight, location: 0.00),
            .init(color: .lifeHeatTeal, location: 0.12),
            .init(color: .lifeHeatGreen, location: 0.25),
            .init(color: .lifeHeatLime, location: 0.40),
            .init(color: .lifeHeatYellow, location: 0.55),
            .init(color: .lifeHeatGold, location: 0.68),
            .init(color: .lifeHeatOrange, location: 0.78),
            .init(color: .lifeHeatVermilion, location: 0.90),
            .init(color: .lifeHeatRed, location: 1.00)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

private let lifeHeatGradient = Gradient(stops: [
    .init(color: .lifeHeatMidnight, location: 0.00),
    .init(color: .lifeHeatTeal, location: 0.12),
    .init(color: .lifeHeatGreen, location: 0.25),
    .init(color: .lifeHeatLime, location: 0.40),
    .init(color: .lifeHeatYellow, location: 0.55),
    .init(color: .lifeHeatGold, location: 0.68),
    .init(color: .lifeHeatOrange, location: 0.78),
    .init(color: .lifeHeatVermilion, location: 0.90),
    .init(color: .lifeHeatRed, location: 1.00)
])

private struct HeatColorStop {
    let progress: Double
    let red: Double
    let green: Double
    let blue: Double
}

private let heatColorStops = [
    HeatColorStop(progress: 0.00, red: 25, green: 25, blue: 112),
    HeatColorStop(progress: 0.12, red: 0, green: 116, blue: 128),
    HeatColorStop(progress: 0.25, red: 0, green: 190, blue: 96),
    HeatColorStop(progress: 0.40, red: 172, green: 230, blue: 48),
    HeatColorStop(progress: 0.55, red: 255, green: 224, blue: 48),
    HeatColorStop(progress: 0.68, red: 255, green: 186, blue: 32),
    HeatColorStop(progress: 0.78, red: 255, green: 149, blue: 0),
    HeatColorStop(progress: 0.90, red: 255, green: 82, blue: 32),
    HeatColorStop(progress: 1.00, red: 255, green: 36, blue: 36)
]

private func progressColor(for progress: Double) -> Color {
    let clampedProgress = min(1, max(0, progress))
    guard var previousStop = heatColorStops.first else {
        return .lifeHeatYellow
    }

    for nextStop in heatColorStops.dropFirst() {
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
