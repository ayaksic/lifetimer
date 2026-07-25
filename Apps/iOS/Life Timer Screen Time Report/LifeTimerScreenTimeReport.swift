import DeviceActivity
import ExtensionKit
import LifeTimerCore
import SwiftUI

extension DeviceActivityReport.Context {
    static let lifeTimerScreenTime = Self("life-timer-screen-time")
}

struct LifeTimerScreenTimeConfiguration {
    let buckets: [LifeTimerUsageBucket]
    let lifetimeStart: Date
    let referenceDate: Date
    let presentation: TimerPage
}

struct LifeTimerScreenTimeReport: DeviceActivityReportScene {
    var context: DeviceActivityReport.Context {
        .lifeTimerScreenTime
    }

    let content: (LifeTimerScreenTimeConfiguration) -> LifeTimerScreenTimeView

    init() {
        content = { configuration in
            LifeTimerScreenTimeView(configuration: configuration)
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
            referenceDate: Date(),
            presentation: LifeTimerScreenTimePresentationStore.current()
        )
    }
}
