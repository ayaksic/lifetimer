# Life Timer

This repository is the canonical home of the complete Life Timer product: the web app, iPhone app, widget and Live Activity, Watch app, complication, shared Swift package, settings schema, and cross-platform parity fixtures.

## Repository layout

```text
Apps/
  iOS/       iPhone app, widget, and Live Activity Xcode project
  watchOS/   Watch app and complication Xcode project
Sources/
  LifeTimerCore/   shared calendar, progress, settings, and CloudKit code
Tests/
  LifeTimerCoreTests/   Swift tests and shared parity fixtures
  WebParity/            JavaScript parity and CloudKit regression tests
Web/                    static GitHub Pages application
```

The native Xcode projects link `LifeTimerCore` directly from this repository root. Changes to shared behavior and every native consumer can therefore be reviewed and committed together.

## Validation

Run the complete clean-checkout gate from the repository root:

```sh
./scripts/verify-all.sh
```

This includes shared Swift/web tests, fake CloudKit adapter tests, contract and entitlement drift checks, generated web assembly, secret/history checks, and unsigned simulator builds for all four native surfaces. The smaller `./test.sh` command remains available for package/web-only iteration.

The native projects are:

- `Apps/iOS/Life Timer.xcodeproj`
- `Apps/watchOS/lifetimer.xcodeproj`

Build both projects after changes that touch the package, app shells, entitlements, or resources.

The first consolidated native release is version `1.0 (2)`. Increment `CURRENT_PROJECT_VERSION` across every app and extension target for each subsequent device release so installed builds can be identified reliably.

## Settings synchronization

Native hosts cache `LifeTimerSettings` in App Group `group.yaksic.lifetimer`. Each App Group is local to its Apple platform/device; it is not an iPhone-to-Watch transport. The iPhone and Watch apps mirror the newest timestamped settings record to the private CloudKit database in `iCloud.yaksic.lifetimer`. Opening either host app refreshes its local cache from CloudKit. The Watch complication reads its Watch-local cache and reloads timelines after host changes. The iOS extension is an hour Live Activity and does not consume lifetime settings.

There is no WatchConnectivity implementation. Cross-device convergence depends on CloudKit availability and host refresh. `lifetimeStart` and `unitPositionEnabled` synchronize; current period/page and flow/grid choice remain local session presentation and are never uploaded.

## Health sleep overlay

The iPhone/iPad app can read HealthKit sleep-analysis samples and paint them into the current timer page. Time in bed uses light blue; actual sleep stages use deep blue and render over any overlapping in-bed interval. Turn the overlay on from Diagnostics. Life Timer requests read-only access at that moment, queries only the visible timer range through the present, and keeps the returned intervals in memory.

The enable preference and rendered overlay are local presentation state. Sleep samples are never written, logged, added to the Life Timer CloudKit record, exposed to the web/Watch clients, or included in the App Group recovery handoff. An empty result can mean either no samples in the visible range or unavailable read access because HealthKit deliberately does not reveal read-denial status.

## Screen Time phone-use overlay

The iPhone/iPad app can also host Apple's Device Activity report extension over the timer. Enable `Show phone use` in Diagnostics to request individual Family Controls authorization. The green layer is restricted to iPhone activity and can be toggled independently from the blue HealthKit layer.

Apple keeps the underlying Screen Time records inside the sandboxed report extension; the Life Timer host receives the rendered overlay rather than activity records. Shorter pages use hourly duration buckets, the year uses daily buckets, and lifetime uses weekly buckets. A light green hatch spans each bucket, with density representing its aggregate phone-use duration. Screen Time does not provide exact session timestamps through this privacy-preserving report path, so the hatch deliberately avoids claiming exactly when within the bucket the phone was used.

The report extension reads only the existing lifetime start from `group.yaksic.lifetimer` so lifetime grid cells align with the host. It has no HealthKit or CloudKit entitlement. Development installation and distribution require Apple's Family Controls entitlement approval for the host and report-extension bundle identifiers.

The web app uses the same private CloudKit record through CloudKit JS. The production schema and API token are configured for `https://ayaksic.github.io`. Local file or localhost runs remain on-device. If the hosting origin changes, update the token's Allowed Origins entry in CloudKit Dashboard.

If CloudKit is unavailable, the web app remains functional with local browser settings and reports `On device`.

The iPhone and Watch host apps expose compact diagnostics, and the web sync indicator expands to show version/build/commit, settings revision, last sync, pending state, and environment/container metadata. See `OPERATIONS.md` for the authoritative propagation and recovery map.

## Web deployment

GitHub Actions assembles only the files under `Web/` that belong in the static site and deploys them to GitHub Pages. Native source, package source, tests, and project files are not included in the Pages artifact.

## Parity fixtures

`Tests/LifeTimerCoreTests/Fixtures/progress-v1.json` is intentionally consumed by both Swift Testing and the Node parity test. Add edge cases there whenever calendar behavior changes.

## Previous repositories

The histories of `ayaksic/lifetimer-swift` and `ayaksic/lifetimer-watch` were imported under `Apps/` without squashing. Those repositories are archived historical references; all ongoing Life Timer work belongs here.
