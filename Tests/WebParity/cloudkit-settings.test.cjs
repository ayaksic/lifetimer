const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../../Web/cloudkit-settings.js"), "utf8");

function loadSync(database, configureCapture) {
  const container = {
    privateCloudDatabase: database,
    setUpAuth: async () => ({ userRecordName: "test-user" }),
  };
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
    setStatus: (...args) => statuses.push(args),
  });

  assert.deepEqual(statuses.at(-1), ["error", "Invalid value"]);
}

Promise.all([testTimestampEncoding(), testTruthfulErrorStatus()])
  .then(() => console.log("CloudKit web settings: timestamp and error handling passed"))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
