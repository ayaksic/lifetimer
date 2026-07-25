#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const settingsContract = readJSON("contracts/life-timer-settings-v1.schema.json");
const webAssets = readJSON("contracts/web-assets.json");
const manifest = readJSON("project-ops.json");
const swiftSettings = read("Sources/LifeTimerCore/LifeTimerSettings.swift");
const swiftCloud = read("Sources/LifeTimerCore/LifeTimerCloudSettingsBridge.swift");
const webCloud = read("Web/cloudkit-settings.js");
const webIndex = read("Web/index.html");
const cloudConfig = read("Web/cloudkit-config.js");
const iOSProject = read("Apps/iOS/Life Timer.xcodeproj/project.pbxproj");
const iOSContentView = read("Apps/iOS/Life Timer/ContentView.swift");
const screenTimeExtensionInfo = read("Apps/iOS/Life Timer Screen Time Report/Info.plist");
const screenTimeExtensionRoot = read("Apps/iOS/Life Timer Screen Time Report/LifeTimerScreenTimeReportExtension.swift");
const screenTimeReport = read("Apps/iOS/Life Timer Screen Time Report/LifeTimerScreenTimeReport.swift");
const watchProject = read("Apps/watchOS/lifetimer.xcodeproj/project.pbxproj");

for (const [path, source] of [
  ["Web/build-info.js", read("Web/build-info.js")],
  ["Web/cloudkit-config.js", cloudConfig],
  ["Web/cloudkit-settings.js", webCloud],
  ["Web/life-timer-core.js", read("Web/life-timer-core.js")],
]) {
  try {
    new Function(source);
  } catch (error) {
    throw new Error(`${path}: JavaScript syntax error: ${error.message}`);
  }
}
const inlineScripts = [...webIndex.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((match) => match[1]);
assert(inlineScripts.length === 1, "index.html must contain exactly one inline application script");
try {
  new Function(inlineScripts[0]);
} catch (error) {
  throw new Error(`Web/index.html: JavaScript syntax error: ${error.message}`);
}

assert(manifest.schemaVersion === 3, "project-ops.json must use baseline schema version 3");
assert(manifest.id === "lifetimer" && manifest.family === "lifetimer", "canonical id/family drift");
assert(manifest.kind === "application", "Life Timer must remain an application manifest");
assert(manifest.recovery?.vaultHandoff?.applicationId === "lifetimer", "vault handoff must use canonical app id");
assert(manifest.security?.environments?.productionDataInNonProduction === false, "production data must be excluded from non-production");
assert(manifest.security?.logging?.sensitiveValuesExcluded === true, "diagnostics/logs must exclude sensitive values");

const requiredFields = settingsContract.required;
assert(JSON.stringify(requiredFields) === JSON.stringify(["schemaVersion", "lifetimeStart", "unitPositionEnabled", "updatedAt"]), "settings schema field drift");
for (const field of requiredFields) {
  assert(swiftSettings.includes(`var ${field}:`), `Swift settings missing ${field}`);
  assert(webCloud.includes(field), `web CloudKit adapter missing ${field}`);
}

const cloud = settingsContract["x-cloudKit"];
const cache = settingsContract["x-nativeCache"];
for (const [label, value, sources] of [
  ["CloudKit container", cloud.container, [swiftSettings, cloudConfig]],
  ["record type", cloud.recordType, [swiftSettings, swiftCloud, webCloud]],
  ["record name", cloud.recordName, [swiftSettings, swiftCloud, webCloud]],
  ["App Group", cache.appGroup, [swiftSettings]],
  ["native cache key", cache.key, [swiftSettings]],
]) {
  for (const source of sources) assert(source.includes(value), `${label} drift: ${value}`);
}
assert(cloud.environment === "production" && cloudConfig.includes('environment: "production"'), "web CloudKit environment drift");
assert(settingsContract["x-presentationState"].synchronized === false, "presentation state must remain local");

const applicationSources = [
  read("Apps/iOS/Life Timer/ContentView.swift"),
  read("Apps/watchOS/lifetimer Watch App/ContentView.swift"),
  webIndex,
].join("\n");
assert(!/^import\s+WatchConnectivity$/m.test(applicationSources), "WatchConnectivity was introduced without updating the sync contract");

const entitlementPaths = [
  "Apps/iOS/Life Timer/Life Timer.entitlements",
  "Apps/iOS/Life Timer Widgets/Life Timer Widgets.entitlements",
  "Apps/watchOS/lifetimer Watch App/lifetimer Watch App.entitlements",
  "Apps/watchOS/lifetimer Complication/lifetimer Complication.entitlements",
];
const iOSHostEntitlementPath = "Apps/iOS/Life Timer/Life Timer.entitlements";
let iOSHostEntitlement;
for (const path of entitlementPaths) {
  const entitlement = JSON.parse(execFileSync("plutil", ["-convert", "json", "-o", "-", path], { encoding: "utf8" }));
  assert(entitlement["com.apple.developer.icloud-container-environment"] === "Production", `${path}: CloudKit must remain Production`);
  assert(equal(entitlement["com.apple.developer.icloud-container-identifiers"], [cloud.container]), `${path}: iCloud container drift`);
  assert(equal(entitlement["com.apple.security.application-groups"], [cache.appGroup]), `${path}: App Group drift`);
  assert(equal(entitlement["com.apple.developer.icloud-services"], ["CloudKit"]), `${path}: CloudKit service drift`);
  if (path === iOSHostEntitlementPath) {
    iOSHostEntitlement = entitlement;
    assert(entitlement["com.apple.developer.healthkit"] === true, `${path}: HealthKit read capability missing`);
  } else {
    assert(entitlement["com.apple.developer.healthkit"] === undefined, `${path}: HealthKit must remain iOS-host-only`);
  }
}
const screenTimeEntitlementPath = "Apps/iOS/Life Timer Screen Time Report/Life Timer Screen Time Report.entitlements";
const screenTimeEntitlement = JSON.parse(
  execFileSync("plutil", ["-convert", "json", "-o", "-", screenTimeEntitlementPath], { encoding: "utf8" })
);
assert(iOSHostEntitlement["com.apple.developer.family-controls"] === true, `${iOSHostEntitlementPath}: Family Controls capability missing`);
assert(screenTimeEntitlement["com.apple.developer.family-controls"] === true, `${screenTimeEntitlementPath}: Family Controls capability missing`);
assert(equal(screenTimeEntitlement["com.apple.security.application-groups"], [cache.appGroup]), `${screenTimeEntitlementPath}: App Group drift`);
assert(screenTimeEntitlement["com.apple.developer.healthkit"] === undefined, `${screenTimeEntitlementPath}: HealthKit must remain host-only`);
assert(screenTimeEntitlement["com.apple.developer.icloud-services"] === undefined, `${screenTimeEntitlementPath}: Screen Time extension must not access CloudKit`);
assert(
  screenTimeExtensionInfo.includes("com.apple.deviceactivityui.report-extension")
    && iOSProject.includes("com.apple.product-type.extensionkit-extension"),
  "Device Activity report extension contract missing"
);
assert(
  /INFOPLIST_KEY_NSHealthShareUsageDescription = "[^"]*sleep[^"]*";/i.test(iOSProject),
  "iOS HealthKit sleep read usage description missing"
);
assert(
  /Rectangle\(\)[\s\S]*?\.fill\(Color\.black\.opacity\(0\.001\)\)[\s\S]*?\.contentShape\(Rectangle\(\)\)[\s\S]*?\.gesture\(swipeGesture\)[\s\S]*?\.zIndex\(100\)/.test(iOSContentView),
  "iOS timer interaction layer must remain above the Screen Time report"
);
assert(
  /DeviceActivityReport\([\s\S]*?\.id\(\s*ScreenTimeReportID\([\s\S]*?pageID:\s*pages\[pageIndex\]\.id[\s\S]*?referenceDate:\s*screenTimeReferenceDate[\s\S]*?lifetimeStart:\s*lifetimeStart/.test(iOSContentView),
  "Screen Time report identity must change with page and filter inputs"
);
assert(
  /OverlayQuickToggle\(\s*title:\s*"Sleep"[\s\S]*?sleepOverlay\.setEnabled/.test(iOSContentView)
    && /OverlayQuickToggle\(\s*title:\s*"Screen"[\s\S]*?screenTimeOverlay\.setEnabled/.test(iOSContentView),
  "main timer must expose direct Sleep and Screen overlay controls"
);
assert(
  (screenTimeExtensionRoot.match(/LifeTimerScreenTimeReport\(\)/g) ?? []).length === 1
    && screenTimeReport.includes('Self("life-timer-screen-time")')
    && !screenTimeReport.includes("contextName"),
  "Screen Time extension must use one stable report context"
);

for (const project of [iOSProject, watchProject]) {
  const versions = [...project.matchAll(/CURRENT_PROJECT_VERSION = ([^;]+);/g)].map((match) => match[1].trim());
  const marketing = [...project.matchAll(/MARKETING_VERSION = ([^;]+);/g)].map((match) => match[1].trim());
  assert(new Set(versions).size === 1, "native CURRENT_PROJECT_VERSION values must match within each project");
  assert(new Set(marketing).size === 1, "native MARKETING_VERSION values must match within each project");
}
assert(iOSProject.includes("Embed Life Timer Build Info") && watchProject.includes("Embed Life Timer Build Info"), "native build identity phase missing");

assert(webAssets.schemaVersion === 1, "web asset manifest schema drift");
assert(new Set(webAssets.assets).size === webAssets.assets.length, "duplicate web asset declaration");
assert(equal(webAssets.generatedAssets, ["build-info.js"]), "generated web artifact contract drift");
assert(webIndex.includes('src="build-info.js"'), "web release identity is not loaded");
assert(read("Web/build-info.js").includes('commit: "working-tree"'), "raw-source web identity must remain truthful");
assert(/apiToken:\s*"[a-f0-9]{64}"/.test(cloudConfig), "CloudKit JS token must retain the expected browser identifier shape");
assert(cloudConfig.includes("https://ayaksic.github.io"), "CloudKit token origin restriction must remain documented");

for (const scheme of [
  "Apps/iOS/Life Timer.xcodeproj/xcshareddata/xcschemes/Life Timer.xcscheme",
  "Apps/watchOS/lifetimer.xcodeproj/xcshareddata/xcschemes/lifetimer Watch App.xcscheme",
  "Apps/watchOS/lifetimer.xcodeproj/xcshareddata/xcschemes/lifetimer Complication.xcscheme",
]) {
  const xml = read(scheme);
  assert(xml.includes("BuildAction") && xml.includes("BuildableReference"), `shared scheme is incomplete: ${scheme}`);
}

console.log("Contracts, manifest, schemes, versions, entitlements, and generated-artifact declarations are aligned.");

function read(path) {
  return readFileSync(path, "utf8");
}

function readJSON(path) {
  return JSON.parse(read(path));
}

function equal(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
