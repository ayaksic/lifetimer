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
    if (!lifetimeStart || !updatedAt) return null;

    return {
      schemaVersion: Number(field(record, "schemaVersion") || 1),
      lifetimeStart: new Date(lifetimeStart),
      unitPositionEnabled: Boolean(field(record, "unitPositionEnabled")),
      updatedAt: new Date(updatedAt),
    };
  }

  function encode(settings) {
    const record = {
      recordName,
      recordType,
      fields: {
        schemaVersion: { value: settings.schemaVersion || 1 },
        lifetimeStart: { value: settings.lifetimeStart },
        unitPositionEnabled: { value: settings.unitPositionEnabled ? 1 : 0 },
        updatedAt: { value: settings.updatedAt },
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
          apiToken: config.apiToken,
          environment: config.environment || "production",
        },
      ],
    });

    const container = root.CloudKit.getDefaultContainer();
    database = container.privateCloudDatabase;
    const identity = await container.setUpAuth();
    if (!identity) {
      callbacks.setStatus("sign-in");
      container.whenUserSignsIn().then(reconcile).catch(() => callbacks.setStatus("offline"));
      return;
    }

    await reconcile();
  }

  root.LifeTimerCloudSync = {
    start(nextCallbacks) {
      start(nextCallbacks).catch(() => nextCallbacks.setStatus("offline"));
    },
    save(settings) {
      save(settings).catch(() => callbacks && callbacks.setStatus("offline"));
    },
  };
})(window);
