import Foundation

public protocol LifeTimerCloudSettingsAdapter: Sendable {
    func currentAccountIdentifier() async throws -> String
    func fetchSettings(for accountIdentifier: String) async throws -> LifeTimerSettings?
    func saveSettingsIfNewer(
        _ settings: LifeTimerSettings,
        for accountIdentifier: String
    ) async throws -> LifeTimerSettings
}

enum LifeTimerCloudSettingsCoordinatorError: Error {
    case accountChanged
}

public actor LifeTimerCloudSettingsCoordinator {
    private let adapter: any LifeTimerCloudSettingsAdapter

    public init(adapter: any LifeTimerCloudSettingsAdapter) {
        self.adapter = adapter
    }

    public func currentAccountIdentifier() async throws -> String {
        try await adapter.currentAccountIdentifier()
    }

    public func validateCurrentAccount(_ accountIdentifier: String) async throws {
        guard try await adapter.currentAccountIdentifier() == accountIdentifier else {
            throw LifeTimerCloudSettingsCoordinatorError.accountChanged
        }
    }

    public func fetchSettings(for accountIdentifier: String) async throws -> LifeTimerSettings? {
        try await adapter.fetchSettings(for: accountIdentifier)
    }

    public func synchronize(
        local: LifeTimerSettings,
        for accountIdentifier: String
    ) async throws -> LifeTimerSettings {
        guard let remote = try await adapter.fetchSettings(for: accountIdentifier) else {
            return try await adapter.saveSettingsIfNewer(local, for: accountIdentifier)
        }

        if remote.updatedAt > local.updatedAt {
            return remote
        }

        guard local.updatedAt > remote.updatedAt else { return local }
        return try await adapter.saveSettingsIfNewer(local, for: accountIdentifier)
    }
}
