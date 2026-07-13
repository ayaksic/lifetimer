const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const core = require("../../Web/life-timer-core.js");

const fixturePath = path.join(__dirname, "../LifeTimerCoreTests/Fixtures/progress-v1.json");
const fixtures = JSON.parse(fs.readFileSync(fixturePath, "utf8"));

for (const fixture of fixtures) {
  assert.equal(
    fixture.timeZone,
    process.env.TZ,
    `Run web parity tests with TZ=${fixture.timeZone}`,
  );

  const now = new Date(fixture.now);
  const lifetimeStart = new Date(fixture.lifetimeStart);
  const progress = core.progress(fixture.period, now, lifetimeStart);
  assert.ok(Math.abs(progress - fixture.progress) < 1e-9, `${fixture.name}: progress`);
  assert.equal(
    core.unitPositionLabel(fixture.period, now, lifetimeStart),
    fixture.unitPosition,
    `${fixture.name}: unit position`,
  );
}

console.log(`Web parity: ${fixtures.length} fixtures passed`);
