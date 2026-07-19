#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const webRoot = join(root, "Web");
const manifest = JSON.parse(readFileSync(join(root, "contracts/web-assets.json"), "utf8"));
const options = parseArguments(process.argv.slice(2));
const temporary = !options.output;
const output = options.output
  ? resolve(root, options.output)
  : mkdtempSync(join(tmpdir(), "lifetimer-web-"));

try {
  prepareOutput(output, temporary);
  for (const asset of manifest.assets) {
    const source = join(webRoot, asset);
    if (!existsSync(source) || !statSync(source).isFile()) {
      throw new Error(`Missing web asset declared by contract: ${asset}`);
    }
    copyFileSync(source, join(output, basename(asset)));
  }

  const identity = buildIdentity(options);
  writeFileSync(
    join(output, "build-info.js"),
    `window.LIFE_TIMER_BUILD_INFO = ${JSON.stringify(identity, null, 2)};\n`,
    "utf8",
  );

  verifyArtifact(output, manifest);
  console.log(`Web artifact verified: ${manifest.assets.length + manifest.generatedAssets.length} files (${identity.commit})`);
} finally {
  if (temporary) rmSync(output, { recursive: true, force: true });
}
function parseArguments(args) {
  const result = { output: null, commit: null, environment: null };
  for (let index = 0; index < args.length; index += 1) {
    const key = args[index];
    if (!["--output", "--commit", "--environment"].includes(key)) {
      throw new Error(`Unknown argument: ${key}`);
    }
    const value = args[index + 1];
    if (!value || value.startsWith("--")) throw new Error(`Missing value for ${key}`);
    result[key.slice(2)] = value;
    index += 1;
  }
  return result;
}

function prepareOutput(directory, temporary) {
  if (temporary) return;
  if (!existsSync(directory)) {
    mkdirSync(directory, { recursive: true });
    return;
  }
  if (!statSync(directory).isDirectory()) throw new Error(`Output is not a directory: ${directory}`);
  if (readdirSync(directory).length > 0) {
    throw new Error(`Refusing to overwrite non-empty output directory: ${directory}`);
  }
}

function buildIdentity(options) {
  const commit = options.commit || gitCommit();
  const environment = options.environment || "local-source";
  return {
    version: "web",
    build: process.env.GITHUB_RUN_NUMBER || "source",
    commit,
    environment,
  };
}

function gitCommit() {
  const commit = execFileSync("git", ["rev-parse", "--short=12", "HEAD"], {
    cwd: root,
    encoding: "utf8",
  }).trim();
  const dirty = execFileSync("git", ["status", "--porcelain"], {
    cwd: root,
    encoding: "utf8",
  }).trim();
  return dirty ? `${commit}-dirty` : commit;
}

function verifyArtifact(directory, assetManifest) {
  const expected = [...assetManifest.assets, ...assetManifest.generatedAssets].sort();
  const actual = readdirSync(directory).sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Web artifact drift: expected ${expected.join(", ")}; found ${actual.join(", ")}`);
  }

  const index = readFileSync(join(directory, "index.html"), "utf8");
  for (const script of ["build-info.js", "life-timer-core.js", "cloudkit-config.js", "cloudkit-settings.js"]) {
    if (!index.includes(`src="${script}"`)) throw new Error(`index.html does not load ${script}`);
  }
}
