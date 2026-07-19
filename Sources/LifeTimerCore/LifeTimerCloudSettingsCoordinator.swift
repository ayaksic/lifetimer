import Foundation

public protocol LifeTimerCloudSettingsAdapter: Sendable {
    func fetchSettings() async throws -> LifeTimerSettings?
    func saveSettings(_ settings: LifeTimerSettings) async throws
}

public actor LifeTimerCloudSettingsCoordinator {
    private let adapter: any LifeTimerCloudSettingsAdapter

    public init(adapter: any LifeTimerCloudSettingsAdapter) {
        self.adapter = adapter
    }

    public func synchronize(local: LifeTimerSettings) async throws -> LifeTimerSettings {
        guard let remote = try await adapter.fetchSettings() else {
            try await adapter.saveSettings(local)
            return local
        }

        if remote.updatedAt > local.updatedAt {
            return remote
        }

        if local.updatedAt > remote.updatedAt {
            try await adapter.saveSettings(local)
        }

        return local
    }
}
