(function (root) {
  "use strict";

  const recordName = "settings";
  const recordType = "LifeTimerSettings";
  let database = null;
  let fetchedRecord = null;
  let callbacks = null;

  function field(record, name) {
    const value = record && record.fields && record.fields[name];
    return value && Object.prototype.hasOwnProperty.call(value, "value") ? value.value : null;
  }

  function decode(record) {
    const lifetimeStart = field(record, "lifetimeStart");
    const updatedAt = field(record, "updatedAt");
    if (lifetimeStart == null || updatedAt == null) return null;

    const lifetimeStartDate = new Date(lifetimeStart);
    const updatedAtDate = new Date(updatedAt);
    if (!Number.isFinite(lifetimeStartDate.getTime()) || !Number.isFinite(updatedAtDate.getTime())) {
      throw new TypeError("CloudKit returned an invalid Life Timer timestamp");
    }

    return {
      schemaVersion: Number(field(record, "schemaVersion") || 1),
      lifetimeStart: lifetimeStartDate,
      unitPositionEnabled: Boolean(field(record, "unitPositionEnabled")),
      updatedAt: updatedAtDate,
    };
  }

  function timestamp(value, fieldName) {
    const date = value instanceof Date ? value : new Date(value);
    const milliseconds = date.getTime();
    if (!Number.isFinite(milliseconds)) {
      throw new TypeError(`${fieldName} must be a valid date`);
    }
    return milliseconds;
  }

  function encode(settings) {
    const record = {
      recordName,
      recordType,
      fields: {
        schemaVersion: { value: settings.schemaVersion || 1 },
        lifetimeStart: { value: timestamp(settings.lifetimeStart, "lifetimeStart") },
        unitPositionEnabled: { value: settings.unitPositionEnabled ? 1 : 0 },
        updatedAt: { value: timestamp(settings.updatedAt, "updatedAt") },
      },
    };
    if (fetchedRecord && fetchedRecord.recordChangeTag) {
      record.recordChangeTag = fetchedRecord.recordChangeTag;
    }
    return record;
  }

  async function fetchRemote() {
    const response = await database.fetchRecords(recordName);
    if (response.hasErrors) {
      const error = response.errors && response.errors[0];
      if (error && (error.ckErrorCode === "NOT_FOUND" || error.serverErrorCode === "NOT_FOUND")) {
        fetchedRecord = null;
        return null;
      }
      throw error || new Error("CloudKit fetch failed");
    }
    fetchedRecord = response.records[0] || null;
    return decode(fetchedRecord);
  }

  async function save(settings) {
    if (!database) return;
    const response = await database.saveRecords(encode(settings));
    if (response.hasErrors) throw response.errors[0];
    fetchedRecord = response.records[0];
    callbacks.setStatus("synced");
  }

  async function reconcile() {
    callbacks.setStatus("syncing");
    const local = callbacks.getLocalSettings();
    const remote = await fetchRemote();

    if (!remote || local.updatedAt > remote.updatedAt) {
      await save(local);
    } else if (remote.updatedAt > local.updatedAt) {
      callbacks.applyRemoteSettings(remote);
    }
    callbacks.setStatus("synced");
  }

  async function start(nextCallbacks) {
    callbacks = nextCallbacks;
    const config = root.LIFE_TIMER_CLOUDKIT_CONFIG;
    if (!config || !config.apiToken || !root.CloudKit) {
      callbacks.setStatus("local");
      return;
    }

    root.CloudKit.configure({
      containers: [
        {
          containerIdentifier: config.containerIdentifier,
          apiTokenAuth: {
            apiToken: config.apiToken,
            persist: true,
          },
          environment: config.environment || "production",
        },
      ],
    });

    const container = root.CloudKit.getDefaultContainer();
    database = container.privateCloudDatabase;
    const identity = await container.setUpAuth();
    if (!identity) {
      callbacks.setStatus("sign-in");
      container.whenUserSignsIn().then(reconcile).catch(reportFailure);
      return;
    }

    await reconcile();
  }

  function reportFailure(error) {
    const status = root.navigator && root.navigator.onLine === false ? "offline" : "error";
    const detail = error && (error.reason || error.message || error.serverErrorCode || error.ckErrorCode);
    callbacks.setStatus(status, detail || "CloudKit request failed");
  }

  root.LifeTimerCloudSync = {
    start(nextCallbacks) {
      return start(nextCallbacks).catch(reportFailure);
    },
    save(settings) {
      return save(settings).catch(reportFailure);
    },
  };
})(window);
