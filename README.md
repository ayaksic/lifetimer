# Life Timer

This repository is the canonical home of the calendar/progress engine, parity fixtures, web app, and shared settings schema.

## Shared core

`LifeTimerCore` is a local Swift package consumed by the sibling `lifetimer-swift` and `lifetimer-watch` Xcode projects. Keep the three repositories checked out beside one another:

```text
lifetimer/
lifetimer-swift/
lifetimer-watch/
```

The native projects reference `../../lifetimer`, so the app, widget, Watch app, and complication all compile the same package source. Run all package and browser parity tests with:

```sh
./test.sh
```

## Settings synchronization

Native targets cache `LifeTimerSettings` in App Group `group.yaksic.lifetimer`. The iPhone and Watch apps mirror the newest timestamped settings record to the private CloudKit database in `iCloud.yaksic.lifetimer`. Widgets and complications read the local App Group cache; opening either host app refreshes it from CloudKit.

The web app uses the same private CloudKit record through CloudKit JS. The production schema and API token are configured; the token is restricted to `https://ayaksic.github.io`. Publish the static site at that origin before expecting web sign-in and sync to work. Local file or localhost runs remain on-device. If the hosting origin changes, update the token's Allowed Origins entry in CloudKit Dashboard.

If CloudKit is unavailable, the web app remains fully functional with local browser settings and reports `On device`.

## Parity fixtures

`Tests/LifeTimerCoreTests/Fixtures/progress-v1.json` is intentionally consumed by both Swift Testing and the Node parity test. Add edge cases there whenever calendar behavior changes.
