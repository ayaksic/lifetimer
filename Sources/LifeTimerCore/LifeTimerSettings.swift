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

public struct LifeTimerSyncDiagnostics: Equatable, Sendable {
    public enum Status: String, Sendable {
        case onDevice = "On device"
        case syncing = "Syncing"
        case synced = "Synced"
        case error = "Sync error"
    }

    public let status: Status
    public let settingsRevision: Date
    public let lastSuccessfulSync: Date?
    public let pendingSettingsRevision: Date?
    public let detail: String?

    public var isPending: Bool { pendingSettingsRevision != nil }
}

public struct LifeTimerReleaseIdentity: Equatable, Sendable {
    public let version: String
    public let build: String
    public let commit: String
    public let runtimeEnvironment: String
    public let cloudKitEnvironment: String
    public let cloudKitContainer: String

    public static func current(bundle: Bundle = .main) -> LifeTimerReleaseIdentity {
        let buildInfo: [String: Any]
        if let url = bundle.url(forResource: "LifeTimerBuildInfo", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dictionary = plist as? [String: Any] {
            buildInfo = dictionary
        } else {
            buildInfo = [:]
        }

        return LifeTimerReleaseIdentity(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            commit: buildInfo["commit"] as? String ?? "not embedded",
            runtimeEnvironment: buildInfo["runtimeEnvironment"] as? String ?? "unknown",
            cloudKitEnvironment: buildInfo["cloudKitEnvironment"] as? String ?? "Production",
            cloudKitContainer: buildInfo["cloudKitContainer"] as? String
                ?? LifeTimerSettingsStorage.iCloudContainerIdentifier
        )
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
    public static let lastSuccessfulSyncKey = "lifeTimer.sync.lastSuccessful.v1"
    public static let pendingRevisionKey = "lifeTimer.sync.pendingRevision.v1"

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
    private let cloudCoordinator: LifeTimerCloudSettingsCoordinator?
    private let lock = NSLock()
    private var started = false
    private var syncStatus: LifeTimerSyncDiagnostics.Status
    private var syncDetail: String?

    public init(
        defaults: UserDefaults = LifeTimerSettingsStorage.appGroupDefaults,
        legacyDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        cloudCoordinator: LifeTimerCloudSettingsCoordinator? = nil,
        useDefaultCloudCoordinator: Bool = true
    ) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
        self.notificationCenter = notificationCenter
        #if canImport(CloudKit)
        self.cloudCoordinator = cloudCoordinator ?? (useDefaultCloudCoordinator
            ? LifeTimerCloudSettingsCoordinator(adapter: LifeTimerCloudSettingsBridge.shared)
            : nil)
        self.syncStatus = self.cloudCoordinator == nil ? .onDevice : .syncing
        #else
        self.cloudCoordinator = cloudCoordinator
        self.syncStatus = cloudCoordinator == nil ? .onDevice : .syncing
        #endif
        self.syncDetail = nil
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

        Task {
            await synchronizeFromCloud()
        }
    }

    public func current() -> LifeTimerSettings {
        lock.withLock {
            readLocal() ?? migrateLegacySettings()
        }
    }

    public func diagnostics() -> LifeTimerSyncDiagnostics {
        lock.withLock {
            let settings = readLocal() ?? migrateLegacySettings()
            return LifeTimerSyncDiagnostics(
                status: syncStatus,
                settingsRevision: settings.updatedAt,
                lastSuccessfulSync: date(forKey: LifeTimerSettingsStorage.lastSuccessfulSyncKey),
                pendingSettingsRevision: date(forKey: LifeTimerSettingsStorage.pendingRevisionKey),
                detail: syncDetail
            )
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
            if cloudCoordinator == nil {
                defaults.removeObject(forKey: LifeTimerSettingsStorage.pendingRevisionKey)
            } else {
                defaults.set(now.timeIntervalSince1970, forKey: LifeTimerSettingsStorage.pendingRevisionKey)
            }
            syncStatus = cloudCoordinator == nil ? .onDevice : .syncing
            syncDetail = nil
            return next
        }

        settingsDidChange(next)
        Task {
            await pushToCloud(next)
        }
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
            settingsDidChange(result.settings)
        }
        return result.settings
    }

    public func refreshFromCloud() async {
        await synchronizeFromCloud()
    }

    private func settingsDidChange(_ settings: LifeTimerSettings) {
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }

    private func synchronizeFromCloud() async {
        guard let cloudCoordinator else {
            updateSyncStatus(.onDevice, detail: nil)
            return
        }

        updateSyncStatus(.syncing, detail: nil)
        let local = current()
        do {
            let resolved = try await cloudCoordinator.synchronize(local: local)
            _ = merge(resolved)
            markSyncSucceeded(revision: resolved.updatedAt)
        } catch {
            markSyncFailed(error)
        }
    }

    private func pushToCloud(_ settings: LifeTimerSettings) async {
        guard let cloudCoordinator else {
            updateSyncStatus(.onDevice, detail: nil)
            return
        }

        do {
            let resolved = try await cloudCoordinator.synchronize(local: settings)
            _ = merge(resolved)
            markSyncSucceeded(revision: resolved.updatedAt)
        } catch {
            markSyncFailed(error)
        }
    }

    private func markSyncSucceeded(revision: Date) {
        lock.withLock {
            defaults.set(Date.now.timeIntervalSince1970, forKey: LifeTimerSettingsStorage.lastSuccessfulSyncKey)
            if let pending = date(forKey: LifeTimerSettingsStorage.pendingRevisionKey), pending <= revision {
                defaults.removeObject(forKey: LifeTimerSettingsStorage.pendingRevisionKey)
            }
            syncStatus = .synced
            syncDetail = nil
        }
        settingsDidChange(current())
    }

    private func markSyncFailed(_ error: Error) {
        updateSyncStatus(.error, detail: String(describing: type(of: error)))
    }

    private func updateSyncStatus(_ status: LifeTimerSyncDiagnostics.Status, detail: String?) {
        lock.withLock {
            syncStatus = status
            syncDetail = detail
        }
        settingsDidChange(current())
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

    private func date(forKey key: String) -> Date? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
