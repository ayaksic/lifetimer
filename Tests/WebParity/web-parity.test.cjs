const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const core = require("../../Web/life-timer-core.js");

const fixturePath = path.join(__dirname, "../LifeTimerCoreTests/Fixtures/progress-v1.json");
const fixtures = JSON.parse(fs.readFileSync(fixturePath, "utf8"));
const webSource = fs.readFileSync(path.join(__dirname, "../../Web/index.html"), "utf8");

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

const panelRule = webSource.match(/\.lifetime-panel \{[\s\S]*?\n      \}/)?.[0] ?? "";
const labelRule = webSource.match(/\.lifetime-panel label \{[\s\S]*?\n      \}/)?.[0] ?? "";
const actionsRule = webSource.match(/\.lifetime-actions \{[\s\S]*?\n      \}/)?.[0] ?? "";

assert.match(panelRule, /display: grid;/);
assert.match(panelRule, /gap: 0\.5rem;/);
assert.match(labelRule, /margin: 0;/);
assert.doesNotMatch(labelRule, /margin-bottom:/);
assert.match(actionsRule, /margin: 0;/);
assert.doesNotMatch(actionsRule, /margin-top:/);

console.log(`Web parity: ${fixtures.length} fixtures passed`);
