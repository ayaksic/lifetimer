import Foundation
import LifeTimerCore

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

struct LifeTimerLiveActivityStatus {
    let isRunning: Bool
    let isAvailable: Bool
}

enum LifeTimerLiveActivityManager {
    static func refresh() async -> LifeTimerLiveActivityStatus {
        #if canImport(ActivityKit) && os(iOS)
        if #available(iOS 16.2, *) {
            return LifeTimerLiveActivityStatus(
                isRunning: !Activity<LifeTimerHourAttributes>.activities.isEmpty,
                isAvailable: ActivityAuthorizationInfo().areActivitiesEnabled
            )
        }
        #endif

        return LifeTimerLiveActivityStatus(isRunning: false, isAvailable: false)
    }

    static func startHourTimer(now: Date) async -> LifeTimerLiveActivityStatus {
        #if canImport(ActivityKit) && os(iOS)
        guard #available(iOS 16.2, *) else { return await refresh() }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return await refresh()
        }

        await endHourTimer()

        let interval = LifePeriod.hour.range(containing: now, lifetimeStart: defaultLifetimeStart)
        let attributes = LifeTimerHourAttributes(hourStart: interval.start, hourEnd: interval.end)
        let state = LifeTimerHourAttributes.ContentState(generatedAt: now)
        let content = ActivityContent(
            state: state,
            staleDate: interval.end,
            relevanceScore: 1
        )

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            print("Unable to start Life Timer Live Activity: \(error.localizedDescription)")
        }
        #endif

        return await refresh()
    }

    static func endHourTimer() async -> LifeTimerLiveActivityStatus {
        #if canImport(ActivityKit) && os(iOS)
        guard #available(iOS 16.2, *) else { return await refresh() }

        for activity in Activity<LifeTimerHourAttributes>.activities {
            let content = ActivityContent(
                state: LifeTimerHourAttributes.ContentState(generatedAt: Date()),
                staleDate: nil
            )
            await activity.end(content, dismissalPolicy: .immediate)
        }
        #endif

        return await refresh()
    }
}
