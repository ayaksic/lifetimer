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

Run the shared Swift and browser tests from the repository root:

```sh
./test.sh
```

The native projects are:

- `Apps/iOS/Life Timer.xcodeproj`
- `Apps/watchOS/lifetimer.xcodeproj`

Build both projects after changes that touch the package, app shells, entitlements, or resources.

The first consolidated native release is version `1.0 (2)`. Increment `CURRENT_PROJECT_VERSION` across every app and extension target for each subsequent device release so installed builds can be identified reliably.

## Settings synchronization

Native targets cache `LifeTimerSettings` in App Group `group.yaksic.lifetimer`. The iPhone and Watch apps mirror the newest timestamped settings record to the private CloudKit database in `iCloud.yaksic.lifetimer`. Widgets and complications read the local App Group cache; opening either host app refreshes it from CloudKit.

The web app uses the same private CloudKit record through CloudKit JS. The production schema and API token are configured for `https://ayaksic.github.io`. Local file or localhost runs remain on-device. If the hosting origin changes, update the token's Allowed Origins entry in CloudKit Dashboard.

If CloudKit is unavailable, the web app remains functional with local browser settings and reports `On device`.

## Web deployment

GitHub Actions assembles only the files under `Web/` that belong in the static site and deploys them to GitHub Pages. Native source, package source, tests, and project files are not included in the Pages artifact.

## Parity fixtures

`Tests/LifeTimerCoreTests/Fixtures/progress-v1.json` is intentionally consumed by both Swift Testing and the Node parity test. Add edge cases there whenever calendar behavior changes.

## Previous repositories

The histories of `ayaksic/lifetimer-swift` and `ayaksic/lifetimer-watch` were imported under `Apps/` without squashing. Those repositories are archived historical references; all ongoing Life Timer work belongs here.
