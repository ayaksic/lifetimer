# Life Timer operations

Last reviewed: 2026-07-19

## Identity

| Item | Value |
|---|---|
| Product family | `lifetimer` (standalone) |
| Canonical application ID | `lifetimer` |
| Repository | `/Users/andrew/Documents/lifetimer` |
| Remote | `https://github.com/ayaksic/lifetimer.git` |
| Default branch | `main` |
| Manifest | `project-ops.json` |
| Production web URL | `https://ayaksic.github.io/lifetimer/` |
| Production source identity | GitHub Pages deployment metadata; verify separately from local `HEAD` |

Life Timer has no product, source, contract, fixture, planning, data, or release relationship with League Poker.

## Consolidated clients

| Client/service | Platform | Responsibility | Release path |
|---|---|---|---|
| `LifeTimerCore` | Swift package | Calendar/progress rules, settings schema/repository, CloudKit reconciliation, diagnostics | Included by native targets |
| Web | Static HTML/JS | Timer UI, local browser fallback, CloudKit JS settings sync | `.github/workflows/pages.yml` after an authorized push to `main` |
| Life Timer | iPhone/iPad | Full timer UI, local HealthKit sleep overlay, Screen Time report host, lifetime editing, shared settings host, Live Activity controls | Signed Xcode archive/install |
| Life Timer Screen Time Report | iOS ExtensionKit | Privacy-preserving iPhone activity-duration overlay | Embedded in the iOS app under `Extensions` |
| Life Timer WidgetsExtension | iOS extension | Hour Live Activity and Dynamic Island presentation | Embedded in the iOS app |
| Life Timer Watch App | watchOS | Full timer UI, local App Group settings host, CloudKit refresh | Signed Xcode archive/install |
| Life Timer complication | watchOS WidgetKit | Hour/day timeline snapshots and deep links | Embedded in the Watch app |

The imported `lifetimer-swift` and `lifetimer-watch` histories remain historical lineage inside this repository. Do not recreate the superseded repositories.

## Authority and synchronization map

| Concept | Authority | Consumers | Propagation/conflict rule |
|---|---|---|---|
| Calendar ranges, progress, labels, grids | `LifeTimerCore`; parity fixture is executable cross-language evidence | Swift apps/extensions and `Web/life-timer-core.js` | Swift and JS must pass the same fixture set before release |
| Lifetime start | Timestamped `LifeTimerSettings.lifetimeStart` | iPhone, Watch, web; extensions read a local cache where relevant | Newest valid `updatedAt` wins; local writes remain usable while offline and are retried later |
| Unit-position visibility | Timestamped `LifeTimerSettings.unitPositionEnabled` | iPhone, Watch, web | Same newest-revision rule as lifetime start |
| Current period/page and flow/grid view | Each client session (`@State pageIndex` or in-memory `activePeriod`) | Only the client being operated | Never uploaded; viewing a grid on one device does not change another device's presentation |
| HealthKit sleep overlay | HealthKit sleep-analysis samples authorized by the device owner | iPhone/iPad host only | Read-only, queried for the visible range, held in memory, and never synchronized or backed up by Life Timer |
| Screen Time phone-use overlay | Apple Device Activity report data authorized by the device owner | Sandboxed Screen Time report extension only | Extension renders aggregate duration; host does not receive activity records; local enable preference is not synchronized |
| Live Activity running state | ActivityKit on the iPhone | iPhone and its Live Activity extension | Device-local; not a CloudKit setting |
| Complication timeline | WidgetKit on the Watch | Watch face | Generated locally; host changes request `reloadAllTimelines`, and watchOS controls delivery/coalescing |

### Apple propagation details

- App Group: `group.yaksic.lifetimer`. It shares the JSON settings record `lifeTimer.settings.v1` between a host and extensions in that platform/device container. An iPhone App Group container is not a transport to the Watch.
- CloudKit: private database in `iCloud.yaksic.lifetimer`, production environment, record type `LifeTimerSettings`, record name `settings`. It is the cross-device/web propagation layer, not the sole offline store.
- WatchConnectivity: intentionally not implemented. There is no direct paired-phone queue or reachability path; a Watch must reach CloudKit during a host refresh to converge with a phone/web write.
- iPhone refresh: repository startup and each transition to active request CloudKit reconciliation.
- HealthKit: the iPhone/iPad host requests read-only sleep-analysis access only when the owner enables the Diagnostics toggle. Light blue represents in-bed samples; deep blue represents asleep samples. Overlapping samples from multiple sources are merged by category before totals or drawing.
- Screen Time: the iPhone/iPad host requests individual Family Controls authorization only when the owner enables the Diagnostics toggle. The report filter includes iPhone devices only. The Device Activity report extension renders hourly, daily, or weekly aggregate buckets as a light green hatch whose density represents duration. The current bucket is clipped at the report time so future timer space remains untouched; exact session timestamps are not exposed.
- Watch refresh: opening the Watch app starts/reconciles the repository and reloads complication timelines after local settings changes.
- Widget/complication: extensions consume their local App Group cache. They do not fetch CloudKit independently. Live Activity timing is device-local and does not use lifetime settings.
- Web: settings use browser local storage immediately. On the configured production origin, authenticated CloudKit JS reconciles the same private record. Localhost/file use remains local-only.

The revision is a client timestamp, so badly skewed device clocks can select the wrong winner. There is no atomic server sequence or field-level merge in schema v1.

## Local setup

Required tools: Xcode 26 with iOS/watchOS simulators, Swift, Node.js, Git, and standard macOS command-line tools. No package install or private credential is required for tests or unsigned simulator builds.

```bash
git clone https://github.com/ayaksic/lifetimer.git
cd lifetimer
./scripts/verify-all.sh
```

## Verify everything

```bash
./scripts/verify-all.sh
```

This is intentionally a macOS gate because it includes all four native simulator build surfaces. It does not sign, install, deploy, contact a live CloudKit account, mutate production, or prove device behavior.

## Build/run targets

| Surface | Project/scheme | Expected proof |
|---|---|---|
| iPhone app | `Apps/iOS/Life Timer.xcodeproj`, `Life Timer` | Unsigned iOS Simulator build; includes extension embedding |
| iOS widget/Live Activity | same project, `Life Timer WidgetsExtension` | Unsigned extension simulator build |
| Watch app | `Apps/watchOS/lifetimer.xcodeproj`, `lifetimer Watch App` | Unsigned watchOS Simulator build |
| Complication | same project, `lifetimer Complication` | Unsigned WidgetKit extension simulator build |
| Web | `node scripts/build-web.mjs --output <directory>` | Complete allowlisted static artifact with generated build identity |

## Release and rollback

Release steps and stop conditions are in `docs/RELEASE_CHECKLIST.md`. Deployment or installation always requires explicit authorization.

- Web rollback: redeploy a previously verified Git commit through the Pages workflow. Do not edit the live Pages artifact by hand.
- Native rollback: rebuild/reinstall a previously tagged/verified source revision with a monotonically higher build number when Apple installation rules require it.
- Shared settings rollback: code rollback does not roll back the private CloudKit record. Preserve forward decoding and migrate settings explicitly; never replace the production record with a fixture.
- CloudKit schema rollback: do not delete production fields/record types. Use additive compatibility and a separately authorized migration.

## Production verification

No production verification is performed by the repository-wide local gate. After an authorized release:

1. Confirm the Pages deployment references the intended commit and the web diagnostics show production plus that commit.
2. Load the production URL and test timer rendering without signing in.
3. With the owner-authorized Apple account, verify a settings revision syncs across the intended clients without changing local page/grid selection.
4. Confirm the installed iPhone and Watch builds show the intended version/build/commit and production CloudKit container.
5. Confirm complication/Live Activity refresh behavior on physical devices.
6. If the sleep overlay is part of the release, enable it on the owner-authorized iPhone, grant the intended Health access window, and compare the day/week overlay and totals with the Health app.
7. Enable the Screen Time overlay, approve access, compare aggregate green duration with Settings > Screen Time, verify the shorter pages use hourly buckets, and toggle both overlays independently.

## Diagnostics and release identity

Host apps expose a compact diagnostics sheet and the web sync panel expands to show:

- version/build and source commit;
- runtime environment and CloudKit environment/container;
- settings schema/revision;
- last successful sync and pending state.

The source commit is injected into a native bundle resource by `scripts/embed-native-build-info.sh` and into web artifacts by `scripts/build-web.mjs`. A raw local web source load truthfully reports a working-tree identity.

## Credentials

| Credential/identifier | Purpose | Private location | Scope |
|---|---|---|---|
| CloudKit JS API token | Select CloudKit web container | Public `Web/cloudkit-config.js` by design | Must remain restricted in CloudKit Dashboard to `https://ayaksic.github.io` |
| Apple/iCloud user authentication | Access owner private database | Apple-managed browser/device account state | Private database for the signed-in user |
| Apple signing identity/profiles | Build/install native releases | Developer account, Keychain, Xcode-managed profiles | Life Timer bundle IDs, App Group, iCloud container |
| GitHub Pages OIDC token | Publish Pages artifact | Ephemeral GitHub Actions permission | Pages deployment only |

Never record credential values, cookies, signing material, or CloudKit private records in Git or logs.

## Security model

The public timer works without authentication. Private settings sync is mediated by Apple authentication and CloudKit private-database authorization. See `docs/SECURITY_MODEL.md`; `node scripts/security-check.mjs --history` verifies the worktree and complete history without printing matched values.

## Backup and restore

| Layer | Current truth |
|---|---|
| Application-native export | Missing; Life Timer has no user-triggered export/import or isolated restore command |
| Local authoritative cache | App Group preference `lifeTimer.settings.v1`; losing it is survivable only if another current copy exists |
| Health sleep overlay | HealthKit remains authoritative; Life Timer stores only a local enable preference and holds queried samples in memory |
| Screen Time phone-use overlay | Screen Time remains authoritative inside Apple's report extension; Life Timer stores only a local enable preference and does not export activity records |
| Cloud propagation copy | Private CloudKit mirror; useful for convergence but not independently proven as a backup/restore system |
| Personal Data Vault handoff | Registered under canonical application ID `lifetimer` in bundle target `apple-device-apps` |
| Captured source | `group.yaksic.lifetimer` App Group preference container |
| Vault integrity check | The capture verifies the plist contains `lifeTimer.settings.v1`, then validates archive/hash metadata |
| Off-site layers | Personal Data Vault's iCloud archive and encrypted Google Drive portfolio copy; health is owned/reported by that repository |
| Restore proof | Personal Data Vault runbook/staging restore probe, not this repository's local test gate |

The handoff is intentionally one-way operational recovery coverage; Life Timer does not call or embed Personal Data Vault. Check current health and perform restoration only through `/Users/andrew/Documents/personal-data-vault/RECOVERY_RUNBOOK.md`. A registered mapping is not proof that the latest backup is healthy.

Read-only evidence captured during this baseline review: the latest `apple-device-apps` manifest completed successfully at `2026-07-19T19:15:54Z`, validated one Life Timer settings record, and passed archive/hash checks. The encrypted Google Drive vault manifest completed successfully at `2026-07-19T19:20:35Z` with its repository data check and restore probe. The most recent scheduled aggregate health report available during review was green at `2026-07-19T17:51:43Z`; it predates those newer manifests, so it is retained as a separate health snapshot rather than used to relabel them.

## Likely failures

| Symptom | Likely cause | Safe first check |
|---|---|---|
| Settings differ across devices | CloudKit unavailable, different Apple IDs, pending write, or skewed clocks | Open diagnostics on both hosts; compare revision, last sync, pending, environment/container |
| Watch did not update after phone edit | No WatchConnectivity path; Watch has not refreshed from CloudKit | Open Watch host with network access, then inspect its diagnostics |
| Complication is stale | watchOS timeline throttling or host has not reloaded local timelines | Open Watch app and compare local settings revision |
| Web says On device | Non-production origin, missing CloudKit JS/config, signed-out user, or offline state | Expand web diagnostics; check origin/environment without exposing tokens |
| Native build lacks commit | Build-info phase did not run or Git unavailable to Xcode | Inspect the built `LifeTimerBuildInfo.plist` resource and build log for `Embed Life Timer Build Info` |
| Gate fails entitlement drift | One target lost the shared App Group/iCloud production declarations | Compare all four entitlements; do not change production schema |
| Sleep overlay is empty | No samples in the visible range, limited Health history, or read access unavailable | Compare the same period in Health and review Life Timer access in Settings; the app cannot distinguish denial from an empty result |
| Screen Time toggle is denied | Family Controls authorization was denied/revoked, or the signed profile lacks the entitlement | Review Screen Time authorization and the host/report-extension provisioning profiles; do not substitute the EU-only direct data-access API |

## Never do this

- Do not import anything from League Poker or describe it as related.
- Do not recreate or split the consolidated repositories.
- Do not treat App Group storage as cross-device transport or claim WatchConnectivity exists.
- Do not sync page/grid selection unless a separately reviewed contract intentionally changes product behavior.
- Do not persist, log, upload, or copy HealthKit sleep samples into CloudKit, App Group settings, fixtures, screenshots, or recovery artifacts.
- Do not copy Device Activity records out of the Screen Time report extension or imply bucketed duration is an exact session timeline.
- Do not replace private CloudKit data with fixtures or mutate the production schema during testing.
- Do not claim that a build proves deploy, installation, CloudKit account sync, backup, or restore.
