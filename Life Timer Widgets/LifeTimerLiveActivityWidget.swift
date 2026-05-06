import ActivityKit
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
                        height: 16
                    )
                    .padding(.horizontal, 2)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HourProgressBar(
                        start: context.attributes.hourStart,
                        end: context.attributes.hourEnd,
                        height: 14
                    )
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Circle()
                    .fill(LinearGradient.lifeHeat)
                    .frame(width: 8, height: 8)
            } compactTrailing: {
                HourProgressBar(
                    start: context.attributes.hourStart,
                    end: context.attributes.hourEnd,
                    height: 7
                )
                .frame(width: 42)
            } minimal: {
                HourRemainingDot()
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
    let height: CGFloat

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.lifeRemaining.opacity(0.18))

            LinearGradient.lifeHeat
                .mask {
                    ProgressView(timerInterval: start...end, countsDown: false)
                        .progressViewStyle(.linear)
                        .labelsHidden()
                        .tint(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                        .scaleEffect(x: 1, y: max(1, height / 4), anchor: .center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(Capsule(style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityLabel("Current hour progress")
    }
}

private struct HourRemainingDot: View {
    var body: some View {
        Circle()
            .fill(LinearGradient.lifeHeat)
        .frame(width: 18, height: 18)
    }
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
