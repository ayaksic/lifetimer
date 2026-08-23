#if canImport(CloudKit)
import CloudKit
import Foundation

public actor LifeTimerCloudSettingsBridge: LifeTimerCloudSettingsAdapter {
    public static let shared = LifeTimerCloudSettingsBridge()

    private let container: CKContainer
    private let accountScopePrefix: String
    private let database: CKDatabase
    private let recordID = CKRecord.ID(recordName: LifeTimerSettingsStorage.cloudRecordName)

    public init(containerIdentifier: String = LifeTimerSettingsStorage.iCloudContainerIdentifier) {
        container = CKContainer(identifier: containerIdentifier)
        accountScopePrefix = "\(containerIdentifier)|Production|"
        database = container.privateCloudDatabase
    }

    public func currentAccountIdentifier() async throws -> String {
        accountScopePrefix + (try await container.userRecordID().recordName)
    }

    public func fetchSettings(for accountIdentifier: String) async throws -> LifeTimerSettings? {
        try await validateCurrentAccount(accountIdentifier)
        do {
            let record = try await database.record(for: recordID)
            try await validateCurrentAccount(accountIdentifier)
            return settings(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            try await validateCurrentAccount(accountIdentifier)
            return nil
        }
    }

    public func saveSettingsIfNewer(
        _ settings: LifeTimerSettings,
        for accountIdentifier: String
    ) async throws -> LifeTimerSettings {
        for _ in 0..<3 {
            try await validateCurrentAccount(accountIdentifier)
            var record: CKRecord
            do {
                record = try await database.record(for: recordID)
                try await validateCurrentAccount(accountIdentifier)
                guard let current = self.settings(from: record) else {
                    throw LifeTimerCloudSettingsBridgeError.invalidRecord
                }
                if current.updatedAt >= settings.updatedAt {
                    return current
                }
            } catch let error as CKError where error.code == .unknownItem {
                try await validateCurrentAccount(accountIdentifier)
                record = CKRecord(recordType: LifeTimerSettingsStorage.cloudRecordType, recordID: recordID)
            }

            record["schemaVersion"] = Int64(settings.schemaVersion) as CKRecordValue
            record["lifetimeStart"] = settings.lifetimeStart as CKRecordValue
            record["unitPositionEnabled"] = Int64(settings.unitPositionEnabled ? 1 : 0) as CKRecordValue
            record["updatedAt"] = settings.updatedAt as CKRecordValue

            do {
                try await validateCurrentAccount(accountIdentifier)
                let savedRecord = try await saveConditionally(record)
                try await validateCurrentAccount(accountIdentifier)
                guard let saved = self.settings(from: savedRecord) else {
                    throw LifeTimerCloudSettingsBridgeError.invalidRecord
                }
                return saved
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue
            }
        }

        throw LifeTimerCloudSettingsBridgeError.conflictRetryLimit
    }

    private func validateCurrentAccount(_ accountIdentifier: String) async throws {
        guard try await currentAccountIdentifier() == accountIdentifier else {
            throw LifeTimerCloudSettingsBridgeError.accountChanged
        }
    }

    private func saveConditionally(_ record: CKRecord) async throws -> CKRecord {
        let result = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard let saveResult = result.saveResults[recordID] else {
            throw LifeTimerCloudSettingsBridgeError.invalidSaveResult
        }
        return try saveResult.get()
    }

    private func settings(from record: CKRecord) -> LifeTimerSettings? {
        guard
            let schemaVersion = record["schemaVersion"] as? NSNumber,
            let lifetimeStart = record["lifetimeStart"] as? Date,
            let unitPositionEnabled = record["unitPositionEnabled"] as? NSNumber,
            let updatedAt = record["updatedAt"] as? Date
        else {
            return nil
        }

        return LifeTimerSettings(
            schemaVersion: schemaVersion.intValue,
            lifetimeStart: lifetimeStart,
            unitPositionEnabled: unitPositionEnabled.boolValue,
            updatedAt: updatedAt
        )
    }
}

private enum LifeTimerCloudSettingsBridgeError: Error {
    case accountChanged
    case conflictRetryLimit
    case invalidRecord
    case invalidSaveResult
}
#endif
