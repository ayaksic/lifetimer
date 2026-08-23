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
    public static let cloudAccountIdentifierKey = "lifeTimer.sync.cloudAccountIdentifier.v1"
    public static let cloudBootstrapAuthorizedKey = "lifeTimer.sync.cloudBootstrapAuthorized.v1"
    public static let unownedLocalKey = "lifeTimer.settings.unowned.v1"

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
    private var cloudReconciliationTail: Task<Void, Never>?
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
        self.cloudReconciliationTail = nil
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

        enqueueCloudReconciliation()
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
            if let accountIdentifier = activeCloudAccountIdentifier() {
                persist(next)
                setCloudBootstrapAuthorized(true, accountIdentifier: accountIdentifier)
            } else {
                persist(next)
            }
            if cloudCoordinator == nil {
                removeSyncValue(forKey: LifeTimerSettingsStorage.pendingRevisionKey)
            } else {
                setSyncDate(now, forKey: LifeTimerSettingsStorage.pendingRevisionKey)
            }
            syncStatus = cloudCoordinator == nil ? .onDevice : .syncing
            syncDetail = nil
            return next
        }

        settingsDidChange(next)
        enqueueCloudReconciliation()
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
        await enqueueCloudReconciliation().value
    }

    private func settingsDidChange(_ settings: LifeTimerSettings) {
        notificationCenter.post(name: Self.didChangeNotification, object: self)
    }

    @discardableResult
    private func enqueueCloudReconciliation() -> Task<Void, Never> {
        lock.withLock {
            let previous = cloudReconciliationTail
            let task = Task { [weak self] in
                if let previous {
                    await previous.value
                }
                await self?.performCloudReconciliation()
            }
            cloudReconciliationTail = task
            return task
        }
    }

    private func performCloudReconciliation() async {
        guard let cloudCoordinator else {
            updateSyncStatus(.onDevice, detail: nil)
            return
        }

        updateSyncStatus(.syncing, detail: nil)
        do {
            let accountIdentifier = try await cloudCoordinator.currentAccountIdentifier()
            let preparation = prepareCloudAccount(accountIdentifier)

            switch preparation {
            case .ready(let local):
                let resolved = try await cloudCoordinator.synchronize(
                    local: local,
                    for: accountIdentifier
                )
                try await cloudCoordinator.validateCurrentAccount(accountIdentifier)
                _ = merge(resolved)
                markSyncSucceeded(revision: resolved.updatedAt)
            case .remoteOnly:
                let remote = try await cloudCoordinator.fetchSettings(for: accountIdentifier)
                try await cloudCoordinator.validateCurrentAccount(accountIdentifier)
                guard let remote else {
                    updateSyncStatus(
                        .onDevice,
                        detail: "Cloud account has no saved settings"
                    )
                    return
                }
                replaceLocal(remote, for: accountIdentifier)
                markSyncSucceeded(revision: remote.updatedAt)
            }
        } catch {
            markSyncFailed(error)
        }
    }

    private func markSyncSucceeded(revision: Date) {
        lock.withLock {
            setSyncDate(Date.now, forKey: LifeTimerSettingsStorage.lastSuccessfulSyncKey)
            if let pending = date(forKey: LifeTimerSettingsStorage.pendingRevisionKey), pending <= revision {
                removeSyncValue(forKey: LifeTimerSettingsStorage.pendingRevisionKey)
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
        let lifetimeStartSource = defaults.object(forKey: LifeTimerSettingsStorage.legacyLifetimeStartKey) != nil
            ? defaults
            : legacyDefaults
        let unitPositionSource = defaults.object(forKey: LifeTimerSettingsStorage.legacyUnitPositionKey) != nil
            ? defaults
            : legacyDefaults
        let hasLifetimeStart = lifetimeStartSource.object(
            forKey: LifeTimerSettingsStorage.legacyLifetimeStartKey
        ) != nil
        let hasUnitPosition = unitPositionSource.object(
            forKey: LifeTimerSettingsStorage.legacyUnitPositionKey
        ) != nil

        guard hasLifetimeStart || hasUnitPosition else { return LifeTimerSettings() }

        let lifetimeStart = hasLifetimeStart
            ? Date(
                timeIntervalSinceReferenceDate: lifetimeStartSource.double(
                    forKey: LifeTimerSettingsStorage.legacyLifetimeStartKey
                )
            )
            : defaultLifetimeStart
        return LifeTimerSettings(
            lifetimeStart: lifetimeStart,
            unitPositionEnabled: hasUnitPosition
                ? unitPositionSource.bool(forKey: LifeTimerSettingsStorage.legacyUnitPositionKey)
                : false,
            updatedAt: .distantPast
        )
    }

    private func persist(_ settings: LifeTimerSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: LifeTimerSettingsStorage.localKey)
        if let accountIdentifier = activeCloudAccountIdentifier() {
            defaults.set(
                data,
                forKey: accountScopedKey(
                    LifeTimerSettingsStorage.localKey,
                    accountIdentifier: accountIdentifier
                )
            )
        }
    }

    private enum CloudAccountPreparation {
        case ready(LifeTimerSettings)
        case remoteOnly
    }

    private func prepareCloudAccount(_ accountIdentifier: String) -> CloudAccountPreparation {
        lock.withLock {
            let local = readLocal() ?? migrateLegacySettings()

            guard let activeAccountIdentifier = activeCloudAccountIdentifier() else {
                preserveUnownedProjection(local)
                return activateCloudAccount(accountIdentifier)
            }

            guard activeAccountIdentifier != accountIdentifier else {
                return cloudBootstrapAuthorized()
                    ? .ready(local)
                    : .remoteOnly
            }

            saveCurrentProjection(for: activeAccountIdentifier)
            return activateCloudAccount(accountIdentifier)
        }
    }

    private func preserveUnownedProjection(_ settings: LifeTimerSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: LifeTimerSettingsStorage.unownedLocalKey)
    }

    private func activateCloudAccount(_ accountIdentifier: String) -> CloudAccountPreparation {
        defaults.set(
            accountIdentifier,
            forKey: LifeTimerSettingsStorage.cloudAccountIdentifierKey
        )

        if let restored = restoreProjection(for: accountIdentifier) {
            return cloudBootstrapAuthorized()
                ? .ready(restored)
                : .remoteOnly
        }

        removeSyncValue(forKey: LifeTimerSettingsStorage.lastSuccessfulSyncKey)
        removeSyncValue(forKey: LifeTimerSettingsStorage.pendingRevisionKey)
        let initial = LifeTimerSettings()
        persist(initial)
        setCloudBootstrapAuthorized(false, accountIdentifier: accountIdentifier)
        return .remoteOnly
    }

    private func replaceLocal(_ settings: LifeTimerSettings, for accountIdentifier: String) {
        lock.withLock {
            if let activeAccountIdentifier = activeCloudAccountIdentifier() {
                if activeAccountIdentifier != accountIdentifier {
                    saveCurrentProjection(for: activeAccountIdentifier)
                }
            } else if let data = defaults.data(forKey: LifeTimerSettingsStorage.localKey) {
                defaults.set(data, forKey: LifeTimerSettingsStorage.unownedLocalKey)
            }
            defaults.set(
                accountIdentifier,
                forKey: LifeTimerSettingsStorage.cloudAccountIdentifierKey
            )
            removeSyncValue(forKey: LifeTimerSettingsStorage.lastSuccessfulSyncKey)
            removeSyncValue(forKey: LifeTimerSettingsStorage.pendingRevisionKey)
            persist(settings)
            setCloudBootstrapAuthorized(true, accountIdentifier: accountIdentifier)
        }
        settingsDidChange(settings)
    }

    private func saveCurrentProjection(for accountIdentifier: String) {
        if let data = defaults.data(forKey: LifeTimerSettingsStorage.localKey) {
            defaults.set(
                data,
                forKey: accountScopedKey(
                    LifeTimerSettingsStorage.localKey,
                    accountIdentifier: accountIdentifier
                )
            )
        }
        mirrorSyncValue(
            forKey: LifeTimerSettingsStorage.lastSuccessfulSyncKey,
            accountIdentifier: accountIdentifier
        )
        mirrorSyncValue(
            forKey: LifeTimerSettingsStorage.pendingRevisionKey,
            accountIdentifier: accountIdentifier
        )
        let scopedAuthorizationKey = accountScopedKey(
            LifeTimerSettingsStorage.cloudBootstrapAuthorizedKey,
            accountIdentifier: accountIdentifier
        )
        defaults.set(
            defaults.bool(forKey: LifeTimerSettingsStorage.cloudBootstrapAuthorizedKey),
            forKey: scopedAuthorizationKey
        )
    }

    private func restoreProjection(for accountIdentifier: String) -> LifeTimerSettings? {
        let settingsKey = accountScopedKey(
            LifeTimerSettingsStorage.localKey,
            accountIdentifier: accountIdentifier
        )
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? decoder.decode(LifeTimerSettings.self, from: data) else {
            return nil
        }

        defaults.set(data, forKey: LifeTimerSettingsStorage.localKey)
        restoreSyncValue(
            forKey: LifeTimerSettingsStorage.lastSuccessfulSyncKey,
            accountIdentifier: accountIdentifier
        )
        restoreSyncValue(
            forKey: LifeTimerSettingsStorage.pendingRevisionKey,
            accountIdentifier: accountIdentifier
        )
        let scopedAuthorizationKey = accountScopedKey(
            LifeTimerSettingsStorage.cloudBootstrapAuthorizedKey,
            accountIdentifier: accountIdentifier
        )
        defaults.set(
            defaults.bool(forKey: scopedAuthorizationKey),
            forKey: LifeTimerSettingsStorage.cloudBootstrapAuthorizedKey
        )
        return settings
    }

    private func activeCloudAccountIdentifier() -> String? {
        defaults.string(forKey: LifeTimerSettingsStorage.cloudAccountIdentifierKey)
    }

    private func cloudBootstrapAuthorized() -> Bool {
        defaults.bool(forKey: LifeTimerSettingsStorage.cloudBootstrapAuthorizedKey)
    }

    private func setCloudBootstrapAuthorized(
        _ authorized: Bool,
        accountIdentifier: String
    ) {
        defaults.set(
            authorized,
            forKey: LifeTimerSettingsStorage.cloudBootstrapAuthorizedKey
        )
        defaults.set(
            authorized,
            forKey: accountScopedKey(
                LifeTimerSettingsStorage.cloudBootstrapAuthorizedKey,
                accountIdentifier: accountIdentifier
            )
        )
    }

    private func setSyncDate(_ date: Date, forKey key: String) {
        defaults.set(date.timeIntervalSince1970, forKey: key)
        if let accountIdentifier = activeCloudAccountIdentifier() {
            defaults.set(
                date.timeIntervalSince1970,
                forKey: accountScopedKey(key, accountIdentifier: accountIdentifier)
            )
        }
    }

    private func removeSyncValue(forKey key: String) {
        defaults.removeObject(forKey: key)
        if let accountIdentifier = activeCloudAccountIdentifier() {
            defaults.removeObject(
                forKey: accountScopedKey(key, accountIdentifier: accountIdentifier)
            )
        }
    }

    private func mirrorSyncValue(forKey key: String, accountIdentifier: String) {
        let scopedKey = accountScopedKey(key, accountIdentifier: accountIdentifier)
        if let value = defaults.object(forKey: key) {
            defaults.set(value, forKey: scopedKey)
        } else {
            defaults.removeObject(forKey: scopedKey)
        }
    }

    private func restoreSyncValue(forKey key: String, accountIdentifier: String) {
        let scopedKey = accountScopedKey(key, accountIdentifier: accountIdentifier)
        if let value = defaults.object(forKey: scopedKey) {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func accountScopedKey(_ key: String, accountIdentifier: String) -> String {
        let encodedAccount = Data(accountIdentifier.utf8).base64EncodedString()
        return "\(key).account.\(encodedAccount)"
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
