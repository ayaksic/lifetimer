# Current task: HealthKit and Screen Time overlays

Status: current-device Screen Time filter fix implemented; version 1.0 (11) commit, push, and iPhone installation authorized; physical-device data comparison pending
Updated: 2026-07-26

## Goal

Add independently controlled overlays to the iPhone/iPad app: HealthKit time in bed/asleep in contrasting blues and current-device Screen Time duration in contrasting green.

## Implemented behavior

- Diagnostics has separate local `Show sleep data` and `Show screen-on time` toggles.
- The main timer has compact, labeled `Sleep` and `Screen` controls at top-right so routine overlay changes do not require opening Diagnostics.
- The HealthKit toggle requests read-only sleep-analysis access. In-bed intervals render light blue and asleep intervals render deep blue.
- The Screen Time toggle requests individual Family Controls authorization and hosts an Apple Device Activity report extension over the timer.
- Screen Time is filtered to the device currently running Life Timer. Leaving Apple's optional device selector unset excludes Screen Time shared by other devices; a model filter such as `.iPhone` would instead aggregate every shared device of that model. The overlay uses hourly duration buckets for hour/day/week/month, daily buckets for year, and weekly buckets for lifetime.
- Flow pages map overlays into the visible period; grid pages map them into their corresponding timer cells.
- Sleep samples refresh when the page or lifetime start changes and when the app becomes active. Screen Time authorization is rechecked when the app becomes active.
- Turning either toggle off immediately removes only that overlay.

## Privacy and accuracy

- HealthKit remains authoritative. Sleep query results are merged and held in memory only.
- Apple keeps Screen Time records inside the report extension. The host app receives only the extension-rendered view, not the underlying activity records.
- The report extension reads the existing lifetime start from the shared App Group only to align lifetime grid cells. It has no HealthKit or CloudKit entitlement.
- Screen Time supplies aggregate screen-on duration per reporting bucket, not exact session timestamps. A soft, sparse green hatch spans only elapsed bucket time, with density representing duration without inventing exact placement or painting the future.
- HealthKit sleep and Screen Time screen-on records are independent. Green may overlap blue when some screen-on duration was reported within the same bucket; it does not claim continuous phone use across that interval.
- A compact Screen badge shows reported screen-on duration divided by elapsed time represented on the current page.
- A host-owned minimally rendered interaction layer remains above Apple's report view so iOS cannot discard its hit-testing surface and page swipes, double taps, and long presses continue to work while the overlay is enabled.
- One stable Device Activity report context and report view are used for every page. Before a page change, the host writes only the selected presentation to the existing App Group, then updates the report filter without forcing the remote report process to be destroyed and recreated.
- Apple's remote report is a sibling of the animated timer rather than a child of its timeline. While Screen is enabled, hour/day pages refresh at five frames per second and week-or-longer pages refresh once per second.
- The extension batches each of the four possible hatch densities into one clipped diagonal path per visible timer region instead of issuing thousands of individual one-pixel fills.
- Only the two local enable preferences persist. Neither overlay is added to the synchronized Life Timer settings contract.

## Verification target

- Eight Swift package tests pass, covering sleep interval merging/clipping, grid alignment, Screen Time bucket aggregation/clamping, and presentation persistence.
- The complete iOS host, widget, and Screen Time report-extension graph passes the unsigned simulator build.
- `node scripts/check-contracts.mjs` passes and enforces the host/extension capability boundaries.
- `./scripts/verify-all.sh` passes all nine repository-wide release stages.
- A signed build for Andrew's iPhone passes, including embedded-extension validation. The signed host has HealthKit and Family Controls; the report extension has Family Controls and the App Group, with no HealthKit or CloudKit.
- The signed app installs, launches, and remains running on Andrew's iPhone 16 Pro Max.
- Owner interaction remains necessary to grant both permissions and compare the resulting overlays with Health and Settings > Screen Time.
- Current-device filtering must be compared with Settings > Screen Time while the current device—not All Devices—is selected.
- This corrective iPhone release advances the host, widget, and Screen Time report extension together from build 10 to build 11.

## Release boundaries

- Push to `main` triggers the repository's GitHub Pages deployment; live commit identity is read back separately from device proof.
- Physical installation is verified with a signed build, install receipt, launch result, and running process.
- Family Controls development/distribution signing depends on Apple provisioning approval for both the host and report extension bundle IDs. A provisioning rejection is an external installation blocker, not permission to replace the privacy-preserving report extension with an unsupported data path.
