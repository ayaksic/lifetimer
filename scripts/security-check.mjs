#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";

const scanHistory = process.argv.includes("--history");
const findings = new Map();
const secretRules = [
  ["private-key", /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/],
  ["aws-access-key", /\bAKIA[0-9A-Z]{16}\b/],
  ["github-token", /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b/],
  ["openai-key", /\bsk-[A-Za-z0-9_-]{20,}\b/],
  ["stripe-live-key", /\b(?:sk|rk)_live_[A-Za-z0-9]{16,}\b/],
  ["assigned-secret", /(?:['"](?:password|token|secret|api[_-]?key|private[_-]?key)['"]\s*(?:=>|:)|\b(?:password|token|secret|api[_-]?key|private[_-]?key)\b\s*=)\s*['"]([^'"]{8,})['"]/i],
];

verifyManifest();
scanCurrentTree();
if (scanHistory) scanGitHistory();

if (findings.size > 0) {
  console.error("Security gate found material that must be removed or explicitly redesigned:");
  for (const finding of findings.values()) console.error(`- ${finding.location} [${finding.rule}]`);
  process.exit(1);
}
console.log(`Security gate passed for the live worktree${scanHistory ? " and complete Git history" : ""}; no credential values were printed.`);

function verifyManifest() {
  let manifest;
  try {
    manifest = JSON.parse(readFileSync("project-ops.json", "utf8"));
  } catch {
    addFinding("project-ops.json", "missing-or-invalid-security-manifest");
    return;
  }
  if (manifest.schemaVersion !== 3 || !isObject(manifest.security)) {
    addFinding("project-ops.json", "security-schema-v3-required");
    return;
  }
  if (!['adopting', 'complete', 'exception-documented'].includes(manifest.security.posture)) {
    addFinding("project-ops.json", "security-posture-required");
  }
  if (manifest.security?.environments?.productionDataInNonProduction !== false) {
    addFinding("project-ops.json", "production-data-nonproduction-must-be-false");
  }
  if (manifest.security?.logging?.sensitiveValuesExcluded !== true) {
    addFinding("project-ops.json", "sensitive-log-values-must-be-excluded");
  }
}

function scanCurrentTree() {
  const paths = git(["ls-files", "-co", "--exclude-standard", "-z"]).stdout.split("\0").filter(Boolean);
  for (const path of paths) {
    if (!existsSync(path)) continue;
    scanPath(path, path);
    const stats = statSync(path);
    if (!stats.isFile() || stats.size > 5 * 1024 * 1024) continue;
    const contents = readFileSync(path);
    if (contents.includes(0)) continue;
    scanText(contents.toString("utf8"), path);
  }
}

function scanGitHistory() {
  if (git(["rev-parse", "--is-shallow-repository"]).stdout.trim() === "true") {
    addFinding("git-history", "complete-history-required-fetch-depth-zero");
    return;
  }
  const patch = git(["log", "-p", "--all", "--no-ext-diff", "--no-color", "--format=commit:%H"], true).stdout;
  let commit = "history";
  let path = "unknown";
  for (const line of patch.split("\n")) {
    if (line.startsWith("commit:")) commit = line.slice(7, 19);
    else if (line.startsWith("+++ b/")) path = line.slice(6);
    else if (line.startsWith("+") && !line.startsWith("+++")) scanLine(line.slice(1), `${commit}:${path}`);
  }
  const objects = git(["rev-list", "--objects", "--all"], true).stdout;
  for (const line of objects.split("\n")) {
    const separator = line.indexOf(" ");
    if (separator === -1) continue;
    const path = line.slice(separator + 1);
    if (path) scanPath(path, `history:${path}`);
  }
}

function scanPath(path, location) {
  const normalized = path.replaceAll("\\", "/");
  const lower = normalized.toLowerCase();
  if (isSafeFixturePath(lower)) return;
  if (/(^|\/)\.env(?:\.[^/]+)?$/.test(lower) && !/\.(?:example|sample|template)$/.test(lower)) addFinding(location, "private-environment-file");
  if (/(^|\/)(?:config\.local\.php|credentials\.json|serviceaccount[^/]*\.json)$/.test(lower)) addFinding(location, "private-config-path");
  if (/\.(?:pem|key|p12|pfx|mobileprovision)$/.test(lower)) addFinding(location, "private-key-material-path");
  if (/(^|\/)(?:data|backups?|exports?|archive)\/.*\.(?:json|sql|csv|sqlite|db)$/.test(lower)) addFinding(location, "private-runtime-data-path");
}

function scanText(text, path) {
  text.split("\n").forEach((line, index) => scanLine(line, `${path}:${index + 1}`));
}

function scanLine(line, location) {
  for (const [rule, pattern] of secretRules) {
    const match = line.match(pattern);
    if (!match || isPlaceholder(match[1] ?? match[0])) continue;
    if (rule === "assigned-secret" && isAllowedBrowserCloudKitToken(line, location)) continue;
    addFinding(location, rule);
  }
}

function isAllowedBrowserCloudKitToken(line, location) {
  return location.includes("Web/cloudkit-config.js") && /^\s*apiToken:\s*"[a-f0-9]{64}",?\s*$/.test(line);
}

function addFinding(location, rule) {
  findings.set(`${location}\0${rule}`, { location, rule });
}

function isSafeFixturePath(path) {
  return /(^|\/)(?:test|tests|fixtures?|examples?|samples?|templates?|synthetic|sanitized)(\/|[-_.])/.test(path);
}

function isPlaceholder(value) {
  return /change-me|replace-with|same-long|must-not-be-stored|your[_-]|example|fixture|synthetic|placeholder|long.random|test[_-]|process\.env|getenv|\$\(|\$\{|<[^>]+>|^X-[A-Za-z-]+$/i.test(value);
}

function git(args, allowFailure = false) {
  const result = spawnSync("git", args, { encoding: "utf8", maxBuffer: 1024 * 1024 * 256 });
  if (!allowFailure && result.status !== 0) throw new Error(result.stderr || `git ${args.join(" ")} failed`);
  return result;
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
