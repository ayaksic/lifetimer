import DeviceActivity
import ExtensionKit
import LifeTimerCore
import SwiftUI

extension DeviceActivityReport.Context {
    static func lifeTimerScreenTime(period: LifePeriod, style: TimerPageStyle) -> Self {
        Self("life-timer-screen-time-\(style.rawValue)-\(period.contextName)")
    }
}

struct LifeTimerScreenTimeConfiguration {
    let buckets: [LifeTimerUsageBucket]
    let lifetimeStart: Date
    let referenceDate: Date
}

struct LifeTimerScreenTimeReport: DeviceActivityReportScene {
    let period: LifePeriod
    let style: TimerPageStyle

    var context: DeviceActivityReport.Context {
        .lifeTimerScreenTime(period: period, style: style)
    }

    let content: (LifeTimerScreenTimeConfiguration) -> LifeTimerScreenTimeView

    init(period: LifePeriod, style: TimerPageStyle) {
        self.period = period
        self.style = style
        content = {
            LifeTimerScreenTimeView(
                configuration: $0,
                period: period,
                style: style
            )
        }
    }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> LifeTimerScreenTimeConfiguration {
        var buckets: [LifeTimerUsageBucket] = []

        for await activityData in data {
            for await segment in activityData.activitySegments {
                buckets.append(
                    LifeTimerUsageBucket(
                        dateInterval: segment.dateInterval,
                        activeDuration: segment.totalActivityDuration
                    )
                )
            }
        }

        let settingsRepository = LifeTimerSettingsRepository(
            defaults: LifeTimerSettingsStorage.appGroupDefaults,
            legacyDefaults: LifeTimerSettingsStorage.appGroupDefaults,
            useDefaultCloudCoordinator: false
        )

        return LifeTimerScreenTimeConfiguration(
            buckets: LifeTimerUsageBucket.aggregated(buckets),
            lifetimeStart: settingsRepository.current().lifetimeStart,
            referenceDate: Date()
        )
    }
}

private extension LifePeriod {
    var contextName: String {
        switch self {
        case .hour: "hour"
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        case .lifetime: "lifetime"
        }
    }
}
