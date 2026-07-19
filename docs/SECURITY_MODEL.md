# Life Timer security model

Last reviewed: 2026-07-19

## Profile and assets

- Profile: `public-content-private-admin`, posture `exception-documented`, ASVS target `ASVS-5.0-L1`.
- The timer and static assets are public. The sensitive asset is the owner's lifetime settings record, chiefly the lifetime start date/time.
- Local stores are browser local storage or `group.yaksic.lifetimer` App Group preferences. Cross-device propagation uses the authenticated user's private CloudKit database in production container `iCloud.yaksic.lifetimer`.
- Synthetic parity fixtures contain no production/private settings.

## Boundaries and controls

| Threat/failure | Asset at risk | Control and executable proof | Residual risk |
|---|---|---|---|
| Anonymous web visitor | Private settings | CloudKit private database requires Apple authentication; adapter tests cover signed-out/local and error behavior | Apple/CloudKit service behavior is not end-to-end tested locally |
| Malicious origin reusing JS token | CloudKit requests | Token is intentionally public but restricted in CloudKit Dashboard to `https://ayaksic.github.io` | Allowed-origin configuration requires manual production review |
| Lost device/browser state | Lifetime settings | CloudKit mirror plus Personal Data Vault App Group capture | Application-native export/import is missing |
| Stale/offline client | Newest settings revision | Timestamp reconciliation and pending/last-sync diagnostics | Clock skew can make last-writer selection incorrect |
| Accidental entitlement drift | Container/group access | `scripts/check-contracts.mjs` parses all four entitlement files | Provisioning and real account access remain device-only checks |
| Secret/private-data commit | Credentials or user data | `node scripts/security-check.mjs --history` scans live/untracked files and complete history without printing values | Pattern scans cannot prove absence of every novel secret format |
| Supply-chain change | Static/native build | Swift package has no external dependencies; web has no package dependency and loads Apple CloudKit JS from Apple's CDN | CDN availability and platform changes remain external dependencies |

## Authentication and authorization

The timer does not require an account. Cloud sync uses Apple-managed CloudKit JS/native account authentication. The app stores no password, session token, or custom authorization database. Private-database authorization is derived from the authenticated Apple identity; the client does not send an owner ID to choose a tenant.

There is no application operator/support/break-glass access. Support must not request Apple passwords, cookies, private record payloads, signing keys, or production exports.

## Browser-visible CloudKit token exception

`Web/cloudkit-config.js` necessarily contains the CloudKit JS API token delivered to browsers. It is not treated as a private credential because private record access still requires Apple authentication and the token must be restricted to the production GitHub Pages origin. The secret scanner allows only that exact file/field shape; other assigned token values fail the gate.

Changing the Pages origin or CloudKit token requires an explicit production action and manual Allowed Origins verification in CloudKit Dashboard.

## Data lifecycle and logging

- Retention follows local browser/App Group persistence and Apple private CloudKit retention until owner deletion/account removal.
- No native export/import exists. Deletion can be performed by clearing local app/browser data and separately deleting the private CloudKit record/account data; document and verify any productized delete flow before claiming it is automatic.
- The application does not log settings payloads, Apple credentials, cookies, or record contents. Diagnostics expose metadata only: schema/revision, sync status/time, environment/container, and release identity.
- Production data must not enter fixtures, screenshots, logs, Git, or simulator tests.

## Verification matrix

| Control | Command | Current status |
|---|---|---|
| Current tree/history/private-data scan | `node scripts/security-check.mjs --history` | Executable |
| Manifest/security declaration | `node scripts/check-contracts.mjs` | Executable |
| Entitlement/container parity | `node scripts/check-contracts.mjs` | Executable |
| Native CloudKit reconcile/error paths | `swift test` with fake adapter | Executable, no live account |
| Web CloudKit encode/error paths | `node Tests/WebParity/cloudkit-settings.test.cjs` | Executable, fake database |
| Origin restriction | CloudKit Dashboard manual review | Manual/device-production only |
| Personal Data Vault restore | Vault runbook | External/manual; not implied by this gate |

## Incident response

1. Contain the affected Pages deployment, Apple credential, or signing capability without destroying evidence.
2. Record affected source commit, environment/container, time window, and metadata only—never copy private settings payloads into an incident log.
3. Preserve a private recovery artifact through Personal Data Vault when safe.
4. Rotate/restrict the narrowest affected credential or identifier and verify the retired access fails.
5. Remove private material from ordinary Git refs only with a separate reviewed history-rewrite plan.
6. Re-run the complete repository gate, verify production origin/account boundaries, and separately prove restore readiness.
