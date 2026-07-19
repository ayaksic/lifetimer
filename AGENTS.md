# Life Timer working agreement

## Scope

This repository is the canonical home of the standalone `lifetimer` product family: the web app, iPhone app, iOS Live Activity/widget extension, Watch app, complication, shared Swift package, parity fixtures, and CloudKit settings adapter.

Life Timer is wholly unrelated to League Poker. Do not import, copy, or coordinate League Poker source, contracts, fixtures, terminology, plans, release processes, or data with this repository.

The prior Life Timer consolidation is complete. Preserve the current repository structure and imported histories; do not recreate or re-split superseded repositories.

## Before changing code

1. Read `OPERATIONS.md`, `project-ops.json`, and `docs/SECURITY_MODEL.md`.
2. Inspect the worktree and preserve unrelated changes.
3. Identify whether a change affects shared timer behavior, synchronized lifetime settings, or platform-local presentation.
4. Update all consumers of a shared contract in the same task, including fixtures when calendar behavior changes.
5. Keep the canonical application ID `lifetimer`; `apple-device-apps` is a Personal Data Vault recovery target, not an application or product family.

## Authority and synchronization

- `LifeTimerCore` and `Tests/LifeTimerCoreTests/Fixtures/progress-v1.json` define shared calendar/progress behavior.
- `lifetimeStart` and `unitPositionEnabled` are synchronized settings. The newest valid `updatedAt` revision wins.
- App Groups share the local settings cache only between a host and its extensions on the same Apple platform/device.
- Private CloudKit propagates settings between native devices and the signed-in web client.
- There is currently no WatchConnectivity transport. Do not claim immediate iPhone-to-Watch delivery.
- Page, period, flow/grid selection, navigation position, open sheets, and similar presentation state remain local unless a future versioned contract explicitly adds them.

## Verification

- `./scripts/verify-all.sh` is the repository-wide gate and must stay truthful from a clean checkout.
- CI runs the same gate on a macOS 26 runner with complete Git history.
- The gate covers Swift tests, web tests and assembly, shared-fixture parity, native CloudKit adapter tests without a live account, contract/schema checks, generated web artifacts, secret/history checks, entitlement checks, and simulator builds for iPhone, widget/Live Activity, Watch, and complication targets.
- Record substantial work and verification evidence in `CURRENT_TASK.md`.

## Credentials, data, and shipping

- Never commit private keys, account credentials, cookies, production exports, or CloudKit private data.
- The CloudKit JS API token in `Web/cloudkit-config.js` is a browser-visible, origin-restricted public identifier. Keep its allowed-origin restriction documented and never treat it as authority to access private records without Apple authentication.
- Never change CloudKit production schema/data, deploy the web app, install on iPhone/Watch, push, merge, create/archive repositories, or rotate credentials without explicit authorization.
- A successful local build is not proof of web deployment, device installation, CloudKit account sync, backup capture, or restore.
