# Life Timer release and rollback checklist

## Stop conditions

Do not deploy Pages, change CloudKit production schema/data, install on iPhone/Watch, push, merge, or create/archive repositories without explicit authorization for that external action.

## Before the change

- [ ] Confirm whether the change affects shared behavior, synchronized lifetime settings, or only local presentation.
- [ ] Identify all consuming clients/extensions and update shared fixtures first when behavior changes.
- [ ] Confirm `git status --short` and preserve unrelated changes/imported history.
- [ ] Review `OPERATIONS.md` authority, sync, recovery, and danger notes.
- [ ] Increment `CURRENT_PROJECT_VERSION` consistently for every affected native target; change marketing version deliberately.
- [ ] Preserve schema-v1 decoding and additive CloudKit compatibility.

## Verification

- [ ] Run `./scripts/verify-all.sh` from a complete checkout.
- [ ] Confirm Swift package tests and both JavaScript suites pass.
- [ ] Confirm CloudKit adapter tests use fakes and do not require or contact a live account.
- [ ] Confirm shared fixture parity, settings schema, web asset manifest, and generated build identity pass drift checks.
- [ ] Confirm App Group/iCloud production entitlements match across iPhone, Watch, and extensions.
- [ ] Confirm the HealthKit entitlement remains on the iOS host only and the built app contains the sleep read usage description.
- [ ] Confirm Family Controls is present on the iOS host and Screen Time report extension, while the extension has App Group access only—no HealthKit or CloudKit.
- [ ] Confirm the ExtensionKit report is embedded in the app's `Extensions` directory, not `PlugIns`.
- [ ] Confirm unsigned simulator builds pass for iPhone, iOS widget/Live Activity, Watch, and complication schemes.
- [ ] Review the diff and security scan output; no credential/private-data value should be printed.
- [ ] Require green clean-checkout CI before merge.

## Authorized web release

- [ ] Record the pre-release Pages commit and a known-good artifact.
- [ ] Push only after explicit authorization; `.github/workflows/pages.yml` deploys on `main`.
- [ ] Confirm the artifact contains only `contracts/web-assets.json` allowlisted files plus generated `build-info.js`.
- [ ] Confirm Pages reports the intended commit/environment and the timer works signed out.
- [ ] If settings behavior changed, verify owner-authorized CloudKit sync without syncing page/grid selection.

### Web rollback

1. Select the previously verified Git commit; do not hand-edit the live artifact.
2. Re-run the Pages workflow for that source only after explicit rollback authorization.
3. Verify build diagnostics, timer behavior, CloudKit status, and asset completeness.

## Authorized native release/install

- [ ] Build/archive the exact verified commit using the shared schemes.
- [ ] Confirm version/build/commit, environment/container, settings revision, last sync, and pending state in each host app.
- [ ] Install only explicitly authorized devices.
- [ ] Run the device-only acceptance checks below.

### Native rollback

1. Select a previously verified compatible source revision.
2. Preserve forward settings decoding; a binary rollback does not revert the CloudKit record.
3. Use a higher build number if required for installation/distribution.
4. Rebuild, install, and execute the full device acceptance set after explicit authorization.

## CloudKit safety

- Never delete or rename production record types/fields as a rollback.
- Use additive fields and old-client compatibility before a schema promotion.
- Back up/recovery-check current owner settings before any separately authorized migration.
- Treat the browser-visible origin-restricted API token as an identifier, not private-record authority.

## Device-only acceptance checks

These cannot be proven by simulator builds:

- [ ] iPhone and Watch are signed into the intended Apple account and show production container `iCloud.yaksic.lifetimer`.
- [ ] Edit lifetime start on one host, observe pending clear/last sync advance, then open the other host and verify the same revision arrives.
- [ ] Change flow/grid/page on one device and confirm the other device's presentation does not change.
- [ ] Make a setting change offline, confirm pending state, restore connectivity, and verify convergence.
- [ ] Confirm App Group delivery from each host to its own extension surface.
- [ ] Confirm Watch complication timelines refresh and deep links open hour/day flow pages.
- [ ] Start/end the iPhone Live Activity and verify Lock Screen/Dynamic Island rendering through an hour boundary.
- [ ] Enable the Health sleep overlay on the owner-authorized iPhone, compare day/week positions and asleep/in-bed totals with Health, then verify disabling it immediately clears the overlay.
- [ ] Enable the Screen Time screen-on overlay, approve individual access, compare green aggregate duration with Settings > Screen Time, verify page gestures still work, and verify disabling it immediately clears only the green layer.
- [ ] Confirm the Screen Time host/report-extension provisioning profiles contain the Family Controls entitlement before calling device installation complete.
- [ ] Confirm installed version/build/commit match the released source.
- [ ] Check current Personal Data Vault health separately and perform a restore drill only under its runbook.
