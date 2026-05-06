//
//  LiveActivityManager.swift
//  Life Timer
//
//  Created by Andrew Yaksic on 5/5/26.
//

import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

struct LifeTimerLiveActivityStatus {
    let isRunning: Bool
    let isAvailable: Bool
}

enum LifeTimerLiveActivityManager {
    static func refresh(now: Date = Date()) async -> LifeTimerLiveActivityStatus {
        #if canImport(ActivityKit) && os(iOS)
        if #available(iOS 16.2, *) {
            await restartExpiredHourTimerIfNeeded(now: now)
            await updateCurrentHourTimers(now: now)

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

        await endExistingHourTimers()
        requestHourTimer(now: now)

        #endif

        return await refresh()
    }

    #if canImport(ActivityKit) && os(iOS)
    @available(iOS 16.2, *)
    private static func requestHourTimer(now: Date) {
        let interval = LifePeriod.hour.range(containing: now, lifetimeStart: defaultLifetimeStart)
        let attributes = LifeTimerHourAttributes(hourStart: interval.start, hourEnd: interval.end)
        let state = LifeTimerHourAttributes.ContentState(
            generatedAt: now,
            progress: hourProgress(at: now, start: interval.start, end: interval.end)
        )
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
    }

    @available(iOS 16.2, *)
    private static func restartExpiredHourTimerIfNeeded(now: Date) async {
        let activities = Activity<LifeTimerHourAttributes>.activities
        guard !activities.isEmpty else { return }

        let hasCurrentHourActivity = activities.contains { activity in
            activity.attributes.hourStart <= now && now < activity.attributes.hourEnd
        }
        guard !hasCurrentHourActivity else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        await endExistingHourTimers()
        requestHourTimer(now: now)
    }

    @available(iOS 16.2, *)
    private static func updateCurrentHourTimers(now: Date) async {
        for activity in Activity<LifeTimerHourAttributes>.activities {
            guard activity.attributes.hourStart <= now && now < activity.attributes.hourEnd else { continue }

            let content = ActivityContent(
                state: LifeTimerHourAttributes.ContentState(
                    generatedAt: now,
                    progress: hourProgress(at: now, start: activity.attributes.hourStart, end: activity.attributes.hourEnd)
                ),
                staleDate: activity.attributes.hourEnd,
                relevanceScore: 1
            )
            await activity.update(content)
        }
    }

    @available(iOS 16.2, *)
    private static func endExistingHourTimers() async {
        for activity in Activity<LifeTimerHourAttributes>.activities {
            let now = Date()
            let content = ActivityContent(
                state: LifeTimerHourAttributes.ContentState(
                    generatedAt: now,
                    progress: hourProgress(at: now, start: activity.attributes.hourStart, end: activity.attributes.hourEnd)
                ),
                staleDate: nil
            )
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }
    #endif

    static func endHourTimer() async -> LifeTimerLiveActivityStatus {
        #if canImport(ActivityKit) && os(iOS)
        guard #available(iOS 16.2, *) else { return await refresh() }

        await endExistingHourTimers()

        return LifeTimerLiveActivityStatus(
            isRunning: false,
            isAvailable: ActivityAuthorizationInfo().areActivitiesEnabled
        )
        #endif

        return LifeTimerLiveActivityStatus(isRunning: false, isAvailable: false)
    }

    #if canImport(ActivityKit) && os(iOS)
    private static func hourProgress(at date: Date, start: Date, end: Date) -> Double {
        let duration = max(1, end.timeIntervalSince(start))
        let elapsed = date.timeIntervalSince(start)
        return min(1, max(0, elapsed / duration))
    }
    #endif
}
