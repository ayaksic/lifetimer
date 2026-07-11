#if canImport(CloudKit)
import CloudKit
import Foundation

public actor LifeTimerCloudSettingsBridge {
    public static let shared = LifeTimerCloudSettingsBridge()

    private let database: CKDatabase
    private let recordID = CKRecord.ID(recordName: LifeTimerSettingsStorage.cloudRecordName)

    public init(containerIdentifier: String = LifeTimerSettingsStorage.iCloudContainerIdentifier) {
        database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    public func synchronize(repository: LifeTimerSettingsRepository) async {
        let local = repository.current()

        do {
            let record = try await database.record(for: recordID)
            guard let remote = settings(from: record) else {
                await save(local)
                return
            }

            let resolved = repository.merge(remote)
            if resolved.updatedAt > remote.updatedAt {
                await save(resolved)
            }
        } catch let error as CKError where error.code == .unknownItem {
            await save(local)
        } catch {
            // Keep the App Group cache authoritative while offline. A later
            // foreground refresh retries CloudKit without blocking the timer.
        }
    }

    public func save(_ settings: LifeTimerSettings) async {
        do {
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
        } catch {
            // CloudKit retries happen on the next write or foreground refresh.
        }
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
