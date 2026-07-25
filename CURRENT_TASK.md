# Current task: HealthKit and Screen Time overlays

Status: complete; repository release and exact-commit physical-iPhone installation authorized
Updated: 2026-07-24

## Goal

Add independently controlled overlays to the iPhone/iPad app: HealthKit time in bed/asleep in contrasting blues and iPhone Screen Time duration in contrasting green.

## Implemented behavior

- Diagnostics has separate local `Show sleep data` and `Show phone use` toggles.
- The HealthKit toggle requests read-only sleep-analysis access. In-bed intervals render light blue and asleep intervals render deep blue.
- The Screen Time toggle requests individual Family Controls authorization and hosts an Apple Device Activity report extension over the timer.
- Screen Time is filtered to iPhone devices. It uses hourly duration buckets for hour/day/week/month, daily buckets for year, and weekly buckets for lifetime.
- Flow pages map overlays into the visible period; grid pages map them into their corresponding timer cells.
- Sleep samples refresh when the page or lifetime start changes and when the app becomes active. Screen Time authorization is rechecked when the app becomes active.
- Turning either toggle off immediately removes only that overlay.

## Privacy and accuracy

- HealthKit remains authoritative. Sleep query results are merged and held in memory only.
- Apple keeps Screen Time records inside the report extension. The host app receives only the extension-rendered view, not the underlying activity records.
- The report extension reads the existing lifetime start from the shared App Group only to align lifetime grid cells. It has no HealthKit or CloudKit entitlement.
- Screen Time supplies aggregate duration per reporting bucket, not exact session timestamps. A light green hatch spans each bucket, with density representing duration without inventing exact placement.
- Only the two local enable preferences persist. Neither overlay is added to the synchronized Life Timer settings contract.

## Verification target

- Seven Swift package tests pass, covering sleep interval merging/clipping, grid alignment, and Screen Time bucket aggregation/clamping.
- The complete iOS host, widget, and Screen Time report-extension graph passes the unsigned simulator build.
- `node scripts/check-contracts.mjs` passes and enforces the host/extension capability boundaries.
- `./scripts/verify-all.sh` passes all nine repository-wide release stages.
- A signed build for Andrew's iPhone passes, including embedded-extension validation. The signed host has HealthKit and Family Controls; the report extension has Family Controls and the App Group, with no HealthKit or CloudKit.
- The signed app installs, launches, and remains running on Andrew's iPhone 16 Pro Max.
- Owner interaction remains necessary to grant both permissions and compare the resulting overlays with Health and Settings > Screen Time.

## Release boundaries

- Push to `main` triggers the repository's GitHub Pages deployment; live commit identity is read back separately from device proof.
- Physical installation is verified with a signed build, install receipt, launch result, and running process.
- Family Controls development/distribution signing depends on Apple provisioning approval for both the host and report extension bundle IDs. A provisioning rejection is an external installation blocker, not permission to replace the privacy-preserving report extension with an unsupported data path.
