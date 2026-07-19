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
