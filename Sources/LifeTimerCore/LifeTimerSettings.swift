import Foundation

public struct LifeTimerSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var lifetimeStart: Date
    public var unitPositionEnabled: Bool
    public var updatedAt: Date

    public init(
        schemaVersion: Int = currentSchemaVersion,
        lifetimeStart: Date = defaultLifetimeStart,
        unitPositionEnabled: Bool = false,
        updatedAt: Date = .distantPast
    ) {
        self.schemaVersion = schemaVersion
        self.lifetimeStart = lifetimeStart
        self.unitPositionEnabled = unitPositionEnabled
        self.updatedAt = updatedAt
    }
}

public enum LifeTimerSettingsStorage {
    public static let appGroupIdentifier = "group.yaksic.lifetimer"
    public static let iCloudContainerIdentifier = "iCloud.yaksic.lifetimer"
    public static let cloudRecordType = "LifeTimerSettings"
    public static let cloudRecordName = "settings"
    public static let localKey = "lifeTimer.settings.v1"
    public static let legacyLifetimeStartKey = "lifeTimerLifetimeStart"
    public static let legacyUnitPositionKey = "lifeTimerUnitPositionEnabled"

    public static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}

public final class LifeTimerSettingsRepository: @unchecked Sendable {
    public static let shared = LifeTimerSettingsRepository()
    public static let didChangeNotification = Notification.Name("LifeTimerSettingsRepository.didChange")

    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var started = false

    public init(
        defaults: UserDefaults = LifeTimerSettingsStorage.appGroupDefaults,
        legacyDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
        self.notificationCenter = notificationCenter
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .millisecondsSince1970
        self.decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    public func start() {
        let shouldStart = lock.withLock {
            guard !started else { return false }
            started = true
            if readLocal() == nil {
                persist(migrateLegacySettings())
            }
            return true
        }

        guard shouldStart else { return }

        #if canImport(CloudKit)
        Task {
            await LifeTimerCloudSettingsBridge.shared.synchronize(repository: self)
        }
        #endif
    }

    public func current() -> LifeTimerSettings {
        lock.withLock {
            readLocal() ?? migrateLegacySettings()
        }
    }

    @discardableResult
    public func update(
        lifetimeStart: Date? = nil,
        unitPositionEnabled: Bool? = nil,
        now: Date = .now
    ) -> LifeTimerSettings {
        let next = lock.withLock {
            var next = readLocal() ?? migrateLegacySettings()
            if let lifetimeStart {
                next.lifetimeStart = lifetimeStart
            }
            if let unitPositionEnabled {
                next.unitPositionEnabled = unitPositionEnabled
            }
            next.schemaVersion = LifeTimerSettings.currentSchemaVersion
            next.updatedAt = now
            persist(next)
            return next
        }

        settingsDidChange(next, pushToCloud: true)
        return next
    }

    @discardableResult
    public func merge(_ incoming: LifeTimerSettings) -> LifeTimerSettings {
        let result = lock.withLock { () -> (settings: LifeTimerSettings, changed: Bool) in
            let local = readLocal() ?? migrateLegacySettings()
            guard incoming.updatedAt > local.updatedAt else { return (local, false) }
            persist(incoming)
            return (incoming, true)
        }

        if result.changed {
            settingsDidChange(result.settings, pushToCloud: false)
        }
        return result.settings
    }

    public func refreshFromCloud() async {
        #if canImport(CloudKit)
        await LifeTimerCloudSettingsBridge.shared.synchronize(repository: self)
        #endif
    }

    private func settingsDidChange(_ settings: LifeTimerSettings, pushToCloud: Bool) {
        notificationCenter.post(name: Self.didChangeNotification, object: self)

        #if canImport(CloudKit)
        if pushToCloud {
            Task {
                await LifeTimerCloudSettingsBridge.shared.save(settings)
            }
        }
        #endif
    }

    private func readLocal() -> LifeTimerSettings? {
        guard let data = defaults.data(forKey: LifeTimerSettingsStorage.localKey) else { return nil }
        return try? decoder.decode(LifeTimerSettings.self, from: data)
    }

    private func migrateLegacySettings() -> LifeTimerSettings {
        let source = defaults.object(forKey: LifeTimerSettingsStorage.legacyLifetimeStartKey) != nil
            || defaults.object(forKey: LifeTimerSettingsStorage.legacyUnitPositionKey) != nil
            ? defaults
            : legacyDefaults
        let hasLifetimeStart = source.object(forKey: LifeTimerSettingsStorage.legacyLifetimeStartKey) != nil
        let hasUnitPosition = source.object(forKey: LifeTimerSettingsStorage.legacyUnitPositionKey) != nil

        guard hasLifetimeStart || hasUnitPosition else { return LifeTimerSettings() }

        let lifetimeStart = hasLifetimeStart
            ? Date(timeIntervalSinceReferenceDate: source.double(forKey: LifeTimerSettingsStorage.legacyLifetimeStartKey))
            : defaultLifetimeStart
        return LifeTimerSettings(
            lifetimeStart: lifetimeStart,
            unitPositionEnabled: source.bool(forKey: LifeTimerSettingsStorage.legacyUnitPositionKey),
            updatedAt: .now
        )
    }

    private func persist(_ settings: LifeTimerSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: LifeTimerSettingsStorage.localKey)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
