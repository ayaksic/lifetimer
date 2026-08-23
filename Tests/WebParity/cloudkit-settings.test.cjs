const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../../Web/cloudkit-settings.js"), "utf8");
const storageSource = fs.readFileSync(path.join(__dirname, "../../Web/settings-storage.js"), "utf8");

function loadSync(database, configureCapture = () => {}, options = {}) {
  const container = {
    privateCloudDatabase: database,
    setUpAuth: async () => (
      options.identityProvider
        ? options.identityProvider()
        : { userRecordName: "test-user" }
    ),
    whenUserSignsIn: options.whenUserSignsIn || (() => new Promise(() => {})),
  };
  if (options.whenUserSignsOut) container.whenUserSignsOut = options.whenUserSignsOut;
  const window = {
    navigator: { onLine: true },
    LIFE_TIMER_CLOUDKIT_CONFIG: {
      containerIdentifier: "iCloud.yaksic.lifetimer",
      environment: "production",
      apiToken: "test-token",
    },
    CloudKit: {
      configure: configureCapture,
      getDefaultContainer: () => container,
    },
  };
  vm.runInNewContext(source, { window, Date, Number, TypeError });
  return window.LifeTimerCloudSync;
}

function loadStorage() {
  const window = {};
  vm.runInNewContext(storageSource, { window, Date, JSON, Number, TypeError, encodeURIComponent });
  return window.LifeTimerWebSettingsStorage;
}

function memoryStorage(initial = {}) {
  const values = new Map(Object.entries(initial));
  return {
    getItem: (key) => values.has(key) ? values.get(key) : null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: (key) => values.delete(key),
    values,
  };
}

function settings(lifetimeStart, unitPositionEnabled, updatedAt) {
  return {
    schemaVersion: 1,
    lifetimeStart: new Date(lifetimeStart),
    unitPositionEnabled,
    updatedAt: new Date(updatedAt),
  };
}

function cloudRecord(value, recordChangeTag = "remote") {
  return {
    recordName: "settings",
    recordType: "LifeTimerSettings",
    recordChangeTag,
    fields: {
      schemaVersion: { value: value.schemaVersion },
      lifetimeStart: { value: value.lifetimeStart.getTime() },
      unitPositionEnabled: { value: value.unitPositionEnabled ? 1 : 0 },
      updatedAt: { value: value.updatedAt.getTime() },
    },
  };
}

async function testTimestampEncoding() {
  let configured;
  let savedRecord;
  const database = {
    fetchRecords: async () => ({
      hasErrors: true,
      errors: [{ serverErrorCode: "NOT_FOUND", reason: "Record not found" }],
    }),
    saveRecords: async (record) => {
      savedRecord = record;
      return { hasErrors: false, records: [{ ...record, recordChangeTag: "saved" }] };
    },
  };
  const sync = loadSync(database, (value) => { configured = value; });
  const lifetimeStart = new Date("1978-02-08T03:04:00.000Z");
  const updatedAt = new Date("2026-07-11T20:57:52.000Z");
  const statuses = [];

  await sync.start({
    getLocalSettings: () => ({ schemaVersion: 1, lifetimeStart, unitPositionEnabled: true, updatedAt }),
    applyRemoteSettings: () => assert.fail("No remote record should exist"),
    setAccountIdentity: () => {},
    setStatus: (...args) => statuses.push(args),
  });

  assert.equal(configured.containers[0].apiTokenAuth.apiToken, "test-token");
  assert.equal(configured.containers[0].apiTokenAuth.persist, true);
  assert.equal(savedRecord.fields.lifetimeStart.value, lifetimeStart.getTime());
  assert.equal(savedRecord.fields.updatedAt.value, updatedAt.getTime());
  assert.equal(savedRecord.fields.unitPositionEnabled.value, 1);
  assert.deepEqual(Object.keys(savedRecord.fields).sort(), [
    "lifetimeStart",
    "schemaVersion",
    "unitPositionEnabled",
    "updatedAt",
  ]);
  assert.deepEqual(statuses.at(-1), ["synced"]);
}

async function testTruthfulErrorStatus() {
  const database = {
    fetchRecords: async () => ({
      hasErrors: true,
      errors: [{ serverErrorCode: "NOT_FOUND", reason: "Record not found" }],
    }),
    saveRecords: async () => ({
      hasErrors: true,
      errors: [{ serverErrorCode: "BAD_REQUEST", reason: "Invalid value" }],
    }),
  };
  const sync = loadSync(database, () => {});
  const statuses = [];

  await sync.start({
    getLocalSettings: () => ({
      schemaVersion: 1,
      lifetimeStart: new Date("1978-02-08T03:04:00.000Z"),
      unitPositionEnabled: false,
      updatedAt: new Date("2026-07-11T20:57:52.000Z"),
    }),
    applyRemoteSettings: () => {},
    setAccountIdentity: () => {},
    setStatus: (...args) => statuses.push(args),
  });

  assert.deepEqual(statuses.at(-1), ["error", "Invalid value"]);
}

async function testReconcileDoesNotOverwriteAnEditMadeWhileFetchAwaits() {
  const beforeFetch = settings(
    "1985-04-17T08:41:00.000Z",
    false,
    "2026-01-01T00:00:00.000Z",
  );
  const remote = settings(
    "1990-01-01T00:00:00.000Z",
    true,
    "2026-02-01T00:00:00.000Z",
  );
  const editDuringFetch = settings(
    "2000-01-01T00:00:00.000Z",
    false,
    "2026-03-01T00:00:00.000Z",
  );
  let local = beforeFetch;
  let resolveFetch;
  let announceFetch;
  const fetchStarted = new Promise((resolve) => { announceFetch = resolve; });
  let savedRecord;
  const database = {
    fetchRecords: () => {
      announceFetch();
      return new Promise((resolve) => { resolveFetch = resolve; });
    },
    saveRecords: async (record) => {
      savedRecord = record;
      return { hasErrors: false, records: [{ ...record, recordChangeTag: "saved" }] };
    },
  };
  const sync = loadSync(database);
  const start = sync.start({
    getLocalSettings: () => local,
    applyRemoteSettings: () => assert.fail("The edit made during fetch must remain authoritative"),
    setAccountIdentity: () => {},
    setStatus: () => {},
  });

  await fetchStarted;
  local = editDuringFetch;
  resolveFetch({ hasErrors: false, records: [cloudRecord(remote)] });
  await start;

  assert.equal(savedRecord.fields.updatedAt.value, editDuringFetch.updatedAt.getTime());
  assert.equal(savedRecord.fields.lifetimeStart.value, editDuringFetch.lifetimeStart.getTime());
}

async function testSignOutObservationIsArmedBeforeInitialFetch() {
  const local = settings(
    "1985-04-17T08:41:00.000Z",
    false,
    "2026-01-01T00:00:00.000Z",
  );
  let signOutObservationArmed = false;
  let fetchObservedArmed = false;
  const sync = loadSync({
    fetchRecords: async () => {
      fetchObservedArmed = signOutObservationArmed;
      return { hasErrors: false, records: [cloudRecord(local)] };
    },
    saveRecords: async () => assert.fail("Equal settings should not save"),
  }, () => {}, {
    identityProvider: () => ({ userRecordName: "account-a" }),
    whenUserSignsOut: () => {
      signOutObservationArmed = true;
      return new Promise(() => {});
    },
  });

  await sync.start({
    getLocalSettings: () => local,
    applyRemoteSettings: () => assert.fail("Equal settings should not apply"),
    setAccountIdentity: () => {},
    setStatus: () => {},
  });

  assert.equal(fetchObservedArmed, true);
}

async function testIdentityChangeDuringFetchCannotApplyIntoPriorAccountCache() {
  const accountALocal = settings(
    "1978-02-08T03:04:00.000Z",
    true,
    "2026-01-01T00:00:00.000Z",
  );
  const accountBLocal = settings(
    "1985-04-17T08:41:00.000Z",
    false,
    "1970-01-01T00:00:00.000Z",
  );
  const accountBRemote = settings(
    "1999-09-09T09:09:00.000Z",
    false,
    "2026-02-01T00:00:00.000Z",
  );
  let identity = "account-a";
  let activeIdentity = null;
  let resolveFirstFetch;
  let announceFirstFetch;
  const firstFetchStarted = new Promise((resolve) => { announceFirstFetch = resolve; });
  let fetchCount = 0;
  const applied = [];
  let saveCount = 0;
  const sync = loadSync({
    fetchRecords: () => {
      fetchCount += 1;
      if (fetchCount === 1) {
        announceFirstFetch();
        return new Promise((resolve) => { resolveFirstFetch = resolve; });
      }
      return Promise.resolve({ hasErrors: false, records: [cloudRecord(accountBRemote)] });
    },
    saveRecords: async () => {
      saveCount += 1;
      return { hasErrors: false, records: [] };
    },
  }, () => {}, { identityProvider: () => ({ userRecordName: identity }) });

  const start = sync.start({
    getLocalSettings: () => activeIdentity === "account-b" ? accountBLocal : accountALocal,
    applyRemoteSettings: (value) => applied.push({ identity: activeIdentity, value }),
    setAccountIdentity: (value) => { activeIdentity = value; },
    setStatus: () => {},
  });
  await firstFetchStarted;
  identity = "account-b";
  resolveFirstFetch({ hasErrors: false, records: [cloudRecord(accountBRemote)] });
  await start;

  assert.equal(activeIdentity, "account-b");
  assert.equal(saveCount, 0);
  assert.equal(applied.length, 1);
  assert.equal(applied[0].identity, "account-b");
  assert.equal(applied[0].value.updatedAt.getTime(), accountBRemote.updatedAt.getTime());
}

async function testAuthenticatedIdentitySelectsItsCacheBeforeReconcile() {
  const accountALocal = settings(
    "1978-02-08T03:04:00.000Z",
    true,
    "2026-03-01T00:00:00.000Z",
  );
  const accountBLocal = settings(
    "1985-04-17T08:41:00.000Z",
    false,
    "1970-01-01T00:00:00.000Z",
  );
  const accountBRemote = settings(
    "1999-09-09T09:09:00.000Z",
    false,
    "2026-02-01T00:00:00.000Z",
  );
  let activeIdentity = "account-a";
  let applied;
  let saveCount = 0;
  const sync = loadSync({
    fetchRecords: async () => ({ hasErrors: false, records: [cloudRecord(accountBRemote)] }),
    saveRecords: async () => {
      saveCount += 1;
      return { hasErrors: false, records: [] };
    },
  }, () => {}, { identityProvider: () => ({ userRecordName: "account-b" }) });

  await sync.start({
    getLocalSettings: () => activeIdentity === "account-b" ? accountBLocal : accountALocal,
    applyRemoteSettings: (value) => { applied = value; },
    setAccountIdentity: (value) => { activeIdentity = value; },
    setStatus: () => {},
  });

  assert.equal(activeIdentity, "account-b");
  assert.equal(saveCount, 0);
  assert.equal(applied.updatedAt.getTime(), accountBRemote.updatedAt.getTime());
}

async function testIdentityChangeDiscardsPriorAccountSave() {
  const accountALocal = settings(
    "1978-02-08T03:04:00.000Z",
    true,
    "2026-03-01T00:00:00.000Z",
  );
  const accountARemote = settings(
    "1978-02-08T03:04:00.000Z",
    true,
    "2026-03-01T00:00:00.000Z",
  );
  const accountBLocal = settings(
    "1985-04-17T08:41:00.000Z",
    false,
    "1970-01-01T00:00:00.000Z",
  );
  const accountBRemote = settings(
    "1999-09-09T09:09:00.000Z",
    false,
    "2026-04-01T00:00:00.000Z",
  );
  let identity = "account-a";
  let activeIdentity = "account-a";
  let remote = accountARemote;
  const saved = [];
  let applied;
  const sync = loadSync({
    fetchRecords: async () => ({ hasErrors: false, records: [cloudRecord(remote)] }),
    saveRecords: async (record) => {
      saved.push(record);
      return { hasErrors: false, records: [{ ...record, recordChangeTag: "saved" }] };
    },
  }, () => {}, { identityProvider: () => ({ userRecordName: identity }) });

  await sync.start({
    getLocalSettings: () => activeIdentity === "account-b" ? accountBLocal : accountALocal,
    applyRemoteSettings: (value) => { applied = value; },
    setAccountIdentity: (value) => { activeIdentity = value; },
    setStatus: () => {},
  });
  identity = "account-b";
  remote = accountBRemote;
  await sync.save(accountALocal);

  assert.equal(activeIdentity, "account-b");
  assert.equal(saved.length, 0);
  assert.equal(applied.updatedAt.getTime(), accountBRemote.updatedAt.getTime());
}

async function testUndatedAccountDefaultDoesNotCreateACloudRecord() {
  const accountDefault = settings(
    "1985-04-17T08:41:00.000Z",
    false,
    "1970-01-01T00:00:00.000Z",
  );
  let saveCount = 0;
  const sync = loadSync({
    fetchRecords: async () => ({
      hasErrors: true,
      errors: [{ serverErrorCode: "NOT_FOUND", reason: "Record not found" }],
    }),
    saveRecords: async () => {
      saveCount += 1;
      return { hasErrors: false, records: [] };
    },
  }, () => {}, { identityProvider: () => ({ userRecordName: "account-b" }) });

  await sync.start({
    getLocalSettings: () => accountDefault,
    applyRemoteSettings: () => assert.fail("No remote record exists"),
    setAccountIdentity: () => {},
    setStatus: () => {},
  });

  assert.equal(saveCount, 0);
}

async function testSignedOutSettingsStayLocalUntilAnIdentityIsSelected() {
  const anonymousLocal = settings(
    "1978-02-08T03:04:00.000Z",
    true,
    "2026-05-01T00:00:00.000Z",
  );
  const accountBLocal = settings(
    "1985-04-17T08:41:00.000Z",
    false,
    "1970-01-01T00:00:00.000Z",
  );
  const accountBRemote = settings(
    "1999-09-09T09:09:00.000Z",
    false,
    "2026-04-01T00:00:00.000Z",
  );
  let resolveSignIn;
  const signIn = new Promise((resolve) => { resolveSignIn = resolve; });
  let identity = null;
  let activeIdentity = null;
  let saveCount = 0;
  let resolveApplied;
  const applied = new Promise((resolve) => { resolveApplied = resolve; });
  const sync = loadSync({
    fetchRecords: async () => ({ hasErrors: false, records: [cloudRecord(accountBRemote)] }),
    saveRecords: async () => {
      saveCount += 1;
      return { hasErrors: false, records: [] };
    },
  }, () => {}, {
    identityProvider: () => identity ? { userRecordName: identity } : null,
    whenUserSignsIn: () => signIn,
  });

  await sync.start({
    getLocalSettings: () => activeIdentity === "account-b" ? accountBLocal : anonymousLocal,
    applyRemoteSettings: (value) => resolveApplied(value),
    setAccountIdentity: (value) => { activeIdentity = value; },
    setStatus: () => {},
  });
  await sync.save(anonymousLocal);
  assert.equal(saveCount, 0);

  identity = "account-b";
  resolveSignIn({ userRecordName: identity });
  const remote = await applied;
  assert.equal(activeIdentity, "account-b");
  assert.equal(saveCount, 0);
  assert.equal(remote.updatedAt.getTime(), accountBRemote.updatedAt.getTime());
}

async function testSignOutSwitchesBackToAnonymousBeforeAnotherSave() {
  const accountA = settings(
    "1978-02-08T03:04:00.000Z",
    true,
    "2026-05-01T00:00:00.000Z",
  );
  let resolveSignOut;
  const signOut = new Promise((resolve) => { resolveSignOut = resolve; });
  let activeIdentity = null;
  let saveCount = 0;
  let resolveAnonymousSelected;
  const anonymousSelected = new Promise((resolve) => { resolveAnonymousSelected = resolve; });
  const sync = loadSync({
    fetchRecords: async () => ({ hasErrors: false, records: [cloudRecord(accountA)] }),
    saveRecords: async () => {
      saveCount += 1;
      return { hasErrors: false, records: [] };
    },
  }, () => {}, {
    identityProvider: () => ({ userRecordName: "account-a" }),
    whenUserSignsOut: () => signOut,
  });

  await sync.start({
    getLocalSettings: () => accountA,
    applyRemoteSettings: () => {},
    setAccountIdentity: (value) => {
      activeIdentity = value;
      if (value === null) resolveAnonymousSelected();
    },
    setStatus: () => {},
  });
  resolveSignOut();
  await anonymousSelected;
  await sync.save(accountA);

  assert.equal(activeIdentity, null);
  assert.equal(saveCount, 0);
}

async function testSignOutInvalidatesAnIdentityCheckAlreadyInFlight() {
  const accountA = settings(
    "1978-02-08T03:04:00.000Z",
    true,
    "2026-05-01T00:00:00.000Z",
  );
  let resolveSignOut;
  const signOut = new Promise((resolve) => { resolveSignOut = resolve; });
  let resolveIdentityCheck;
  const identityCheck = new Promise((resolve) => { resolveIdentityCheck = resolve; });
  let identityRequestCount = 0;
  let activeIdentity = null;
  const selectedIdentities = [];
  let saveCount = 0;
  let resolveAnonymousSelected;
  const anonymousSelected = new Promise((resolve) => { resolveAnonymousSelected = resolve; });
  const sync = loadSync({
    fetchRecords: async () => ({ hasErrors: false, records: [cloudRecord(accountA)] }),
    saveRecords: async () => {
      saveCount += 1;
      return { hasErrors: false, records: [] };
    },
  }, () => {}, {
    identityProvider: () => {
      identityRequestCount += 1;
      return identityRequestCount <= 2
        ? { userRecordName: "account-a" }
        : identityCheck;
    },
    whenUserSignsOut: () => signOut,
  });

  await sync.start({
    getLocalSettings: () => accountA,
    applyRemoteSettings: () => {},
    setAccountIdentity: (value) => {
      activeIdentity = value;
      selectedIdentities.push(value);
      if (value === null) resolveAnonymousSelected();
    },
    setStatus: () => {},
  });
  const pendingSave = sync.save(accountA);
  resolveSignOut();
  await anonymousSelected;
  resolveIdentityCheck({ userRecordName: "account-a" });
  await pendingSave;

  assert.equal(activeIdentity, null);
  assert.deepEqual(selectedIdentities, ["account-a", null]);
  assert.equal(saveCount, 0);
}

function testUndatedLegacyCacheCannotFabricateAWinningRevision() {
  const storage = memoryStorage({
    lifeTimerLifetimeStart: "1978-02-08T03:04",
    lifeTimerUnitPositionEnabled: "true",
  });
  const repository = loadStorage();
  const migrated = repository.load(storage, null);

  assert.equal(migrated.updatedAt.getTime(), 0);
  assert.equal(migrated.unitPositionEnabled, true);
  assert.equal(migrated.lifetimeStart.getFullYear(), 1978);
}

function testSettingsCacheIsScopedByAuthenticatedIdentity() {
  const storage = memoryStorage();
  const repository = loadStorage();
  const accountA = settings(
    "1978-02-08T03:04:00.000Z",
    true,
    "2026-03-01T00:00:00.000Z",
  );
  repository.save(storage, "account-a", accountA);

  const accountB = repository.load(storage, "account-b");
  assert.equal(accountB.updatedAt.getTime(), 0);
  assert.equal(accountB.lifetimeStart.toISOString(), "1985-04-17T08:41:00.000Z");
  assert.equal(accountB.unitPositionEnabled, false);
}

function testLifetimeStartRoundTripsAsAnExactInstant() {
  const storage = memoryStorage();
  const repository = loadStorage();
  const secondDSTFoldWithPrecision = settings(
    "2026-11-01T06:30:59.987Z",
    true,
    "2026-11-01T07:00:00.123Z",
  );
  repository.save(storage, null, secondDSTFoldWithPrecision);

  const reloaded = repository.load(storage, null);
  assert.equal(reloaded.lifetimeStart.getTime(), secondDSTFoldWithPrecision.lifetimeStart.getTime());
  assert.equal(reloaded.updatedAt.getTime(), secondDSTFoldWithPrecision.updatedAt.getTime());
  assert.equal(repository.defaultLifetimeStart().toISOString(), "1985-04-17T08:41:00.000Z");
}

Promise.all([
  testTimestampEncoding(),
  testTruthfulErrorStatus(),
  testReconcileDoesNotOverwriteAnEditMadeWhileFetchAwaits(),
  testSignOutObservationIsArmedBeforeInitialFetch(),
  testIdentityChangeDuringFetchCannotApplyIntoPriorAccountCache(),
  testAuthenticatedIdentitySelectsItsCacheBeforeReconcile(),
  testIdentityChangeDiscardsPriorAccountSave(),
  testUndatedAccountDefaultDoesNotCreateACloudRecord(),
  testSignedOutSettingsStayLocalUntilAnIdentityIsSelected(),
  testSignOutSwitchesBackToAnonymousBeforeAnotherSave(),
  testSignOutInvalidatesAnIdentityCheckAlreadyInFlight(),
  Promise.resolve().then(testUndatedLegacyCacheCannotFabricateAWinningRevision),
  Promise.resolve().then(testSettingsCacheIsScopedByAuthenticatedIdentity),
  Promise.resolve().then(testLifetimeStartRoundTripsAsAnExactInstant),
])
  .then(() => console.log("CloudKit web settings: identity, reconciliation, and exact storage passed"))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
