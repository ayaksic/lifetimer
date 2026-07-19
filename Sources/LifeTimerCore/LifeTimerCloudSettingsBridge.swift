#if canImport(CloudKit)
import CloudKit
import Foundation

public actor LifeTimerCloudSettingsBridge: LifeTimerCloudSettingsAdapter {
    public static let shared = LifeTimerCloudSettingsBridge()

    private let database: CKDatabase
    private let recordID = CKRecord.ID(recordName: LifeTimerSettingsStorage.cloudRecordName)

    public init(containerIdentifier: String = LifeTimerSettingsStorage.iCloudContainerIdentifier) {
        database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    public func fetchSettings() async throws -> LifeTimerSettings? {
        do {
            return settings(from: try await database.record(for: recordID))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    public func saveSettings(_ settings: LifeTimerSettings) async throws {
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: LifeTimerSettingsStorage.cloudRecordType, recordID: recordID)
        }

        record["schemaVersion"] = Int64(settings.schemaVersion) as CKRecordValue
        record["lifetimeStart"] = settings.lifetimeStart as CKRecordValue
        record["unitPositionEnabled"] = Int64(settings.unitPositionEnabled ? 1 : 0) as CKRecordValue
        record["updatedAt"] = settings.updatedAt as CKRecordValue
        _ = try await database.save(record)
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
#endif
