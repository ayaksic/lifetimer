(function (root) {
  "use strict";

  const recordName = "settings";
  const recordType = "LifeTimerSettings";
  let container = null;
  let database = null;
  let fetchedRecord = null;
  let callbacks = null;
  let accountIdentity = null;
  let identityGeneration = 0;

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
        return { record: null, settings: null };
      }
      throw error || new Error("CloudKit fetch failed");
    }
    const record = response.records[0] || null;
    return { record, settings: decode(record) };
  }

  async function saveRecord(settings, generation = identityGeneration) {
    if (!database) return false;
    callbacks.setStatus("syncing");
    const response = await database.saveRecords(encode(settings));
    if (response.hasErrors) throw response.errors[0];
    if (generation !== identityGeneration) return false;
    fetchedRecord = response.records[0];
    callbacks.setStatus("synced");
    return true;
  }

  async function revalidateIdentity(generation) {
    const identity = await container.setUpAuth();
    if (generation !== identityGeneration) return false;
    const currentIdentity = identityKey(identity);
    if (!currentIdentity) {
      enterSignedOutState();
      return false;
    }
    if (currentIdentity !== accountIdentity) {
      selectIdentity(identity);
      observeSignOut();
      await reconcile();
      return false;
    }
    return true;
  }

  async function reconcile() {
    const generation = identityGeneration;
    callbacks.setStatus("syncing");
    const fetched = await fetchRemote();
    if (generation !== identityGeneration) return;
    if (!await revalidateIdentity(generation)) return;
    fetchedRecord = fetched.record;
    const remote = fetched.settings;
    const local = callbacks.getLocalSettings();

    if (!remote && local.updatedAt.getTime() > 0) {
      if (!await saveForCurrentIdentity(local)) return;
    } else if (remote && local.updatedAt > remote.updatedAt) {
      if (!await saveForCurrentIdentity(local)) return;
    } else if (remote && remote.updatedAt > local.updatedAt) {
      callbacks.applyRemoteSettings(remote);
    }
    callbacks.setStatus("synced");
  }

  function identityKey(identity) {
    const value = identity && identity.userRecordName;
    return typeof value === "string" && value.trim() ? value.trim() : null;
  }

  function selectIdentity(identity) {
    const nextIdentity = identityKey(identity);
    if (!nextIdentity) {
      throw new TypeError("CloudKit did not provide a stable user identity");
    }
    if (nextIdentity !== accountIdentity) {
      accountIdentity = nextIdentity;
      identityGeneration += 1;
      fetchedRecord = null;
      callbacks.setAccountIdentity(nextIdentity);
    }
  }

  function waitForSignIn() {
    if (!container || typeof container.whenUserSignsIn !== "function") return;
    container.whenUserSignsIn()
      .then(async (identity) => {
        selectIdentity(identity);
        observeSignOut();
        await reconcile();
      })
      .catch(reportFailure);
  }

  function enterSignedOutState() {
    if (accountIdentity !== null) {
      accountIdentity = null;
      identityGeneration += 1;
      fetchedRecord = null;
    }
    callbacks.setAccountIdentity(null);
    callbacks.setStatus("sign-in");
    waitForSignIn();
  }

  function observeSignOut() {
    if (!container || typeof container.whenUserSignsOut !== "function") return;
    const observedIdentity = accountIdentity;
    container.whenUserSignsOut()
      .then(() => {
        if (observedIdentity === accountIdentity) enterSignedOutState();
      })
      .catch(reportFailure);
  }

  async function saveForCurrentIdentity(settings) {
    if (!database || !container) return false;
    if (!accountIdentity) {
      callbacks.setStatus("sign-in");
      return false;
    }

    const generation = identityGeneration;
    const expectedIdentity = accountIdentity;
    const identity = await container.setUpAuth();
    if (generation !== identityGeneration || expectedIdentity !== accountIdentity) return false;
    const currentIdentity = identityKey(identity);
    if (!currentIdentity) {
      enterSignedOutState();
      return false;
    }
    if (currentIdentity !== accountIdentity) {
      selectIdentity(identity);
      observeSignOut();
      await reconcile();
      return false;
    }
    return saveRecord(settings, generation);
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

    container = root.CloudKit.getDefaultContainer();
    database = container.privateCloudDatabase;
    const identity = await container.setUpAuth();
    if (!identity) {
      enterSignedOutState();
      return;
    }

    selectIdentity(identity);
    observeSignOut();
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
      return saveForCurrentIdentity(settings).catch(reportFailure);
    },
  };
})(window);
