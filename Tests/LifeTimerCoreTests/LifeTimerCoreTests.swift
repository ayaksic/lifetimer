import Foundation
import Testing
@testable import LifeTimerCore

@Suite("Life Timer calendar parity", .serialized)
struct LifeTimerCoreTests {
    @Test("Shared fixtures match Swift calculations")
    func sharedFixtures() throws {
        let fixtureURL = try #require(
            Bundle.module.url(forResource: "progress-v1", withExtension: "json", subdirectory: "Fixtures")
        )
        let data = try Data(contentsOf: fixtureURL)
        let fixtures = try JSONDecoder().decode([Fixture].self, from: data)

        for fixture in fixtures {
            let timeZone = try #require(TimeZone(identifier: fixture.timeZone))
            let previousTimeZone = NSTimeZone.default
            NSTimeZone.default = timeZone
            defer { NSTimeZone.default = previousTimeZone }
            let now = try localDate(fixture.now, timeZone: timeZone)
            let lifetimeStart = try localDate(fixture.lifetimeStart, timeZone: timeZone)
            let period = try #require(LifePeriod(rawValue: fixture.period))
            let result = period.progress(at: now, lifetimeStart: lifetimeStart)

            #expect(abs(result - fixture.progress) < 0.000000001, "Fixture: \(fixture.name)")
            #expect(period.unitPositionLabel(at: now, lifetimeStart: lifetimeStart) == fixture.unitPosition)
        }
    }

    @Test("Newer settings win and legacy defaults migrate")
    func settingsRepository() throws {
        let suiteName = "LifeTimerCoreTests.\(UUID().uuidString)"
        let legacySuiteName = "LifeTimerCoreTests.Legacy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let legacyDefaults = try #require(UserDefaults(suiteName: legacySuiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        }

        let legacyStart = Date(timeIntervalSince1970: 123_456)
        legacyDefaults.set(
            legacyStart.timeIntervalSinceReferenceDate,
            forKey: LifeTimerSettingsStorage.legacyLifetimeStartKey
        )
        legacyDefaults.set(true, forKey: LifeTimerSettingsStorage.legacyUnitPositionKey)

        let repository = LifeTimerSettingsRepository(
            defaults: defaults,
            legacyDefaults: legacyDefaults,
            useDefaultCloudCoordinator: false
        )
        #expect(repository.current().lifetimeStart == legacyStart)
        #expect(repository.current().unitPositionEnabled)

        let local = repository.update(unitPositionEnabled: false, now: Date(timeIntervalSince1970: 200))
        let older = LifeTimerSettings(
            lifetimeStart: Date(timeIntervalSince1970: 10),
            unitPositionEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(repository.merge(older) == local)

        let newer = LifeTimerSettings(
            lifetimeStart: Date(timeIntervalSince1970: 300),
            unitPositionEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        #expect(repository.merge(newer) == newer)
        #expect(repository.current() == newer)
        #expect(repository.diagnostics().status == .onDevice)
        #expect(!repository.diagnostics().isPending)
    }

    @Test("CloudKit adapter reconciliation does not require a live account")
    func cloudKitAdapterReconciliation() async throws {
        let local = LifeTimerSettings(
            lifetimeStart: Date(timeIntervalSince1970: 100),
            unitPositionEnabled: false,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let missingAdapter = FakeCloudSettingsAdapter(remote: nil)
        let missingCoordinator = LifeTimerCloudSettingsCoordinator(adapter: missingAdapter)
        #expect(try await missingCoordinator.synchronize(local: local) == local)
        #expect(await missingAdapter.savedSettings() == [local])

        let newer = LifeTimerSettings(
            lifetimeStart: Date(timeIntervalSince1970: 300),
            unitPositionEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let newerAdapter = FakeCloudSettingsAdapter(remote: newer)
        let newerCoordinator = LifeTimerCloudSettingsCoordinator(adapter: newerAdapter)
        #expect(try await newerCoordinator.synchronize(local: local) == newer)
        #expect(await newerAdapter.savedSettings().isEmpty)

        let older = LifeTimerSettings(
            lifetimeStart: Date(timeIntervalSince1970: 50),
            unitPositionEnabled: true,
            updatedAt: Date(timeIntervalSince1970: 50)
        )
        let olderAdapter = FakeCloudSettingsAdapter(remote: older)
        let olderCoordinator = LifeTimerCloudSettingsCoordinator(adapter: olderAdapter)
        #expect(try await olderCoordinator.synchronize(local: local) == local)
        #expect(await olderAdapter.savedSettings() == [local])

        let failingCoordinator = LifeTimerCloudSettingsCoordinator(
            adapter: FakeCloudSettingsAdapter(remote: nil, failure: FakeCloudError.unavailable)
        )
        await #expect(throws: FakeCloudError.self) {
            _ = try await failingCoordinator.synchronize(local: local)
        }
    }

    @Test("Sync diagnostics preserve pending writes until a successful adapter round trip")
    func syncDiagnostics() async throws {
        let suiteName = "LifeTimerCoreTests.Diagnostics.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let failing = LifeTimerCloudSettingsCoordinator(
            adapter: FakeCloudSettingsAdapter(remote: nil, failure: FakeCloudError.unavailable)
        )
        let offlineRepository = LifeTimerSettingsRepository(
            defaults: defaults,
            legacyDefaults: defaults,
            cloudCoordinator: failing,
            useDefaultCloudCoordinator: false
        )
        let revision = Date(timeIntervalSince1970: 500)
        _ = offlineRepository.update(unitPositionEnabled: true, now: revision)
        await offlineRepository.refreshFromCloud()
        #expect(offlineRepository.diagnostics().status == .error)
        #expect(offlineRepository.diagnostics().pendingSettingsRevision == revision)

        let successful = LifeTimerCloudSettingsCoordinator(
            adapter: FakeCloudSettingsAdapter(remote: offlineRepository.current())
        )
        let recoveredRepository = LifeTimerSettingsRepository(
            defaults: defaults,
            legacyDefaults: defaults,
            cloudCoordinator: successful,
            useDefaultCloudCoordinator: false
        )
        await recoveredRepository.refreshFromCloud()
        #expect(recoveredRepository.diagnostics().status == .synced)
        #expect(!recoveredRepository.diagnostics().isPending)
        #expect(recoveredRepository.diagnostics().lastSuccessfulSync != nil)
    }

    @Test("Overlay intervals merge by kind and clip without double counting")
    func overlayIntervals() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let intervals = [
            LifeTimerOverlayInterval(
                kind: .inBed,
                start: start,
                end: start.addingTimeInterval(3_600)
            ),
            LifeTimerOverlayInterval(
                kind: .inBed,
                start: start.addingTimeInterval(1_800),
                end: start.addingTimeInterval(5_400)
            ),
            LifeTimerOverlayInterval(
                kind: .asleep,
                start: start.addingTimeInterval(900),
                end: start.addingTimeInterval(4_500)
            ),
        ]

        let merged = LifeTimerOverlayInterval.merged(intervals)
        #expect(merged.count == 2)
        #expect(merged.first(where: { $0.kind == .inBed })?.duration == 5_400)
        #expect(merged.first(where: { $0.kind == .asleep })?.duration == 3_600)

        let clippedRange = DateInterval(
            start: start.addingTimeInterval(1_800),
            end: start.addingTimeInterval(3_600)
        )
        #expect(
            LifeTimerOverlayInterval.totalDuration(
                of: .inBed,
                in: intervals,
                clippedTo: clippedRange
            ) == 1_800
        )
        #expect(
            LifeTimerOverlayInterval.totalDuration(
                of: .asleep,
                in: intervals,
                clippedTo: clippedRange
            ) == 1_800
        )
    }

    @Test("Grid date intervals align overlays with visible cells")
    func gridDateIntervals() throws {
        let timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = timeZone
        defer { NSTimeZone.default = previousTimeZone }

        let now = try localDate("2026-07-24T16:00:00-04:00", timeZone: timeZone)
        let lifetimeStart = try localDate("1985-04-17T03:41:00-05:00", timeZone: timeZone)

        let day = LifePeriod.day.gridDateIntervals(containing: now, lifetimeStart: lifetimeStart)
        #expect(day.count == 24)
        #expect(day.first?.start == LifePeriod.day.range(containing: now, lifetimeStart: lifetimeStart).start)
        #expect(day.last?.end == LifePeriod.day.range(containing: now, lifetimeStart: lifetimeStart).end)

        let year = LifePeriod.year.gridDateIntervals(containing: now, lifetimeStart: lifetimeStart)
        #expect(year.count == 12)
        #expect(LifePeriod.calendar.component(.month, from: year[6].start) == 7)

        let lifetime = LifePeriod.lifetime.gridDateIntervals(containing: now, lifetimeStart: lifetimeStart)
        #expect(lifetime.count == 80)
        #expect(LifePeriod.calendar.component(.year, from: try #require(lifetime.first?.start)) == 1985)
        #expect(LifePeriod.calendar.component(.year, from: try #require(lifetime.last?.start)) == 2064)
    }

    @Test("Screen Time usage buckets aggregate and clamp without inventing duration")
    func usageBuckets() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let hour = DateInterval(start: start, duration: 3_600)
        let nextHour = DateInterval(start: hour.end, duration: 3_600)

        let buckets = LifeTimerUsageBucket.aggregated([
            LifeTimerUsageBucket(dateInterval: hour, activeDuration: 1_200),
            LifeTimerUsageBucket(dateInterval: hour, activeDuration: 3_000),
            LifeTimerUsageBucket(dateInterval: nextHour, activeDuration: -50),
        ])

        #expect(buckets.count == 2)
        #expect(buckets[0].activeDuration == 3_600)
        #expect(buckets[0].activityFraction == 1)
        #expect(buckets[1].activeDuration == 0)
        #expect(buckets[1].activityFraction == 0)

        let currentHour = LifeTimerUsageBucket(
            dateInterval: hour,
            activeDuration: 600
        )
        #expect(
            currentHour.activityFraction(
                through: hour.start.addingTimeInterval(1_200)
            ) == 0.5
        )
        #expect(
            currentHour.activityFraction(
                through: hour.start.addingTimeInterval(-1)
            ) == 0
        )

        let representedFraction = LifeTimerUsageBucket.representedActivityFraction(
            in: [
                LifeTimerUsageBucket(dateInterval: hour, activeDuration: 600),
                LifeTimerUsageBucket(dateInterval: nextHour, activeDuration: 300),
            ],
            range: DateInterval(start: hour.start, end: nextHour.end),
            through: hour.end.addingTimeInterval(1_800)
        )
        #expect(abs(representedFraction - (900.0 / 5_400.0)) < 0.000_001)

        let clippedFraction = LifeTimerUsageBucket.representedActivityFraction(
            in: [
                LifeTimerUsageBucket(dateInterval: hour, activeDuration: 1_200),
            ],
            range: DateInterval(
                start: hour.start.addingTimeInterval(1_800),
                end: hour.end
            ),
            through: hour.end
        )
        #expect(abs(clippedFraction - (600.0 / 1_800.0)) < 0.000_001)
    }

    @Test("Screen Time presentation survives report-process boundaries")
    func screenTimePresentation() throws {
        let suiteName = "LifeTimerCoreTests.ScreenTimePresentation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(
            LifeTimerScreenTimePresentationStore.current(defaults: defaults)
                == TimerPage(period: .hour, style: .flow)
        )

        let page = TimerPage(period: .year, style: .grid)
        LifeTimerScreenTimePresentationStore.save(page, defaults: defaults)
        #expect(LifeTimerScreenTimePresentationStore.current(defaults: defaults) == page)
    }

    private func localDate(_ value: String, timeZone: TimeZone) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return try #require(formatter.date(from: value))
    }
}

private enum FakeCloudError: Error {
    case unavailable
}

private actor FakeCloudSettingsAdapter: LifeTimerCloudSettingsAdapter {
    private let remote: LifeTimerSettings?
    private let failure: FakeCloudError?
    private var saved: [LifeTimerSettings] = []

    init(remote: LifeTimerSettings?, failure: FakeCloudError? = nil) {
        self.remote = remote
        self.failure = failure
    }

    func fetchSettings() async throws -> LifeTimerSettings? {
        if let failure { throw failure }
        return remote
    }

    func saveSettings(_ settings: LifeTimerSettings) async throws {
        if let failure { throw failure }
        saved.append(settings)
    }

    func savedSettings() -> [LifeTimerSettings] {
        saved
    }
}

private struct Fixture: Decodable {
    let name: String
    let timeZone: String
    let now: String
    let lifetimeStart: String
    let period: Int
    let progress: Double
    let unitPosition: String
}
