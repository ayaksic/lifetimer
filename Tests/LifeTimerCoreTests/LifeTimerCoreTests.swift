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

        let repository = LifeTimerSettingsRepository(defaults: defaults, legacyDefaults: legacyDefaults)
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
    }

    private func localDate(_ value: String, timeZone: TimeZone) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return try #require(formatter.date(from: value))
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
