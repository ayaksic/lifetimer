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
                .activityBackgroundTint(Color.lifeRemaining)
                .activitySystemActionForegroundColor(Color.lifeInk)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hour")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Color.lifeMuted)
                        Text(context.attributes.hourStart, style: .time)
                            .font(.caption.monospacedDigit().weight(.bold))
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Remaining")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Color.lifeMuted)
                        HourCountdownText(
                            start: context.attributes.hourStart,
                            end: context.attributes.hourEnd,
                            font: .caption.monospacedDigit().weight(.bold)
                        )
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HourProgressView(
                        start: context.attributes.hourStart,
                        end: context.attributes.hourEnd,
                        showLabel: false
                    )
                }
            } compactLeading: {
                Text("Hr")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.lifeInk)
            } compactTrailing: {
                HourCountdownText(
                    start: context.attributes.hourStart,
                    end: context.attributes.hourEnd,
                    font: .caption2.monospacedDigit().weight(.bold)
                )
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Color.lifeLive)
            }
        }
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct HourLockScreenView: View {
    let context: ActivityViewContext<LifeTimerHourAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Life Timer")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color.lifeInk)
                    Text("Current hour")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.lifeMuted)
                }

                Spacer()

                HourCountdownText(
                    start: context.attributes.hourStart,
                    end: context.attributes.hourEnd,
                    font: .title2.monospacedDigit().weight(.heavy)
                )
            }

            HourProgressView(
                start: context.attributes.hourStart,
                end: context.attributes.hourEnd,
                showLabel: true
            )
        }
        .padding(.vertical, 6)
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct HourCountdownText: View {
    let start: Date
    let end: Date
    let font: Font

    var body: some View {
        Text(
            timerInterval: start...end,
            pauseTime: end,
            countsDown: true,
            showsHours: false
        )
        .font(font)
        .foregroundStyle(Color.lifeInk)
    }
}

@available(iOSApplicationExtension 16.2, *)
private struct HourProgressView: View {
    let start: Date
    let end: Date
    let showLabel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressView(timerInterval: start...end, countsDown: false)
                .tint(Color.lifeElapsed)

            if showLabel {
                HStack {
                    Text(start, style: .time)
                    Spacer()
                    Text(end, style: .time)
                }
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(Color.lifeMuted)
            }
        }
    }
}

private extension Color {
    static let lifeElapsed = Color(red: 182.0 / 255.0, green: 106.0 / 255.0, blue: 95.0 / 255.0)
    static let lifeRemaining = Color(red: 251.0 / 255.0, green: 248.0 / 255.0, blue: 243.0 / 255.0)
    static let lifeLive = Color(red: 215.0 / 255.0, green: 255.0 / 255.0, blue: 47.0 / 255.0)
    static let lifeInk = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0)
    static let lifeMuted = Color(red: 22.0 / 255.0, green: 19.0 / 255.0, blue: 18.0 / 255.0).opacity(0.62)
}
