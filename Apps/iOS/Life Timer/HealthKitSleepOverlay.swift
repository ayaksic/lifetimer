import Combine
import HealthKit
import LifeTimerCore

@MainActor
final class HealthKitSleepOverlay: ObservableObject {
    enum Status: Equatable {
        case unavailable
        case off
        case loading
        case ready
        case noData
        case error(String)
    }

    static let enabledPreferenceKey = "lifeTimer.sleepOverlay.enabled"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var intervals: [LifeTimerOverlayInterval] = []
    @Published private(set) var queriedRange: DateInterval?
    @Published private(set) var status: Status

    private let healthStore: HKHealthStore
    private let defaults: UserDefaults

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        defaults: UserDefaults = .standard
    ) {
        self.healthStore = healthStore
        self.defaults = defaults

        let healthDataAvailable = HKHealthStore.isHealthDataAvailable()
        let enabled = healthDataAvailable && defaults.bool(forKey: Self.enabledPreferenceKey)
        isEnabled = enabled
        status = healthDataAvailable ? (enabled ? .loading : .off) : .unavailable
    }

    var isAvailable: Bool {
        status != .unavailable
    }

    var statusLabel: String {
        switch status {
        case .unavailable:
            return "Unavailable"
        case .off:
            return "Off"
        case .loading:
            return "Loading"
        case .ready:
            return "On"
        case .noData:
            return "On · no samples"
        case .error:
            return "Needs attention"
        }
    }

    var statusDetail: String? {
        guard case .error(let detail) = status else { return nil }
        return detail
    }

    var asleepDuration: TimeInterval {
        LifeTimerOverlayInterval.totalDuration(
            of: .asleep,
            in: intervals,
            clippedTo: queriedRange
        )
    }

    var inBedDuration: TimeInterval {
        LifeTimerOverlayInterval.totalDuration(
            of: .inBed,
            in: intervals,
            clippedTo: queriedRange
        )
    }

    func setEnabled(_ enabled: Bool) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            isEnabled = false
            status = .unavailable
            return
        }

        if !enabled {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledPreferenceKey)
            intervals = []
            queriedRange = nil
            status = .off
            return
        }

        status = .loading

        do {
            let sleepType = HKCategoryType(.sleepAnalysis)
            try await healthStore.requestAuthorization(toShare: [], read: [sleepType])
            isEnabled = true
            defaults.set(true, forKey: Self.enabledPreferenceKey)
        } catch {
            isEnabled = false
            defaults.set(false, forKey: Self.enabledPreferenceKey)
            intervals = []
            queriedRange = nil
            status = .error(error.localizedDescription)
        }
    }

    func refresh(period: LifePeriod, now: Date, lifetimeStart: Date) async {
        guard isEnabled else {
            intervals = []
            queriedRange = nil
            status = HKHealthStore.isHealthDataAvailable() ? .off : .unavailable
            return
        }

        let fullRange = period.range(containing: now, lifetimeStart: lifetimeStart)
        let queryEnd = min(now, fullRange.end)
        guard queryEnd > fullRange.start else {
            intervals = []
            queriedRange = DateInterval(start: fullRange.start, end: fullRange.start)
            status = .noData
            return
        }

        let range = DateInterval(start: fullRange.start, end: queryEnd)
        intervals = []
        queriedRange = range
        status = .loading

        do {
            let sleepType = HKCategoryType(.sleepAnalysis)
            let datePredicate = HKQuery.predicateForSamples(
                withStart: range.start,
                end: range.end,
                options: []
            )
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: sleepType, predicate: datePredicate)],
                sortDescriptors: []
            )
            let samples = try await descriptor.result(for: healthStore)
            guard !Task.isCancelled else { return }

            intervals = LifeTimerOverlayInterval.merged(samples.compactMap(Self.interval))
            status = intervals.isEmpty ? .noData : .ready
        } catch {
            guard !Task.isCancelled else { return }
            intervals = []
            queriedRange = range
            status = .error(error.localizedDescription)
        }
    }

    private static func interval(for sample: HKCategorySample) -> LifeTimerOverlayInterval? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }

        let kind: LifeTimerOverlayKind
        if value == .inBed {
            kind = .inBed
        } else if HKCategoryValueSleepAnalysis.allAsleepValues.contains(value) {
            kind = .asleep
        } else {
            return nil
        }

        guard sample.endDate > sample.startDate else { return nil }
        return LifeTimerOverlayInterval(kind: kind, start: sample.startDate, end: sample.endDate)
    }
}
