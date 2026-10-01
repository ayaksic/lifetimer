# lifetimer semantic-version baseline

Adopted locally on 2026-10-01: **1.7.4**, for source through `6ac13452d09fbe99a2cead682fa405a72995e194`.

This is a retrospective estimate, not a claim these numbered releases were published. Complete first-parent history was reviewed, with imported histories where applicable. Initial usable application is the 1.0 era. Minor increments represent grouped capabilities, not commit counts; related fixes belong to their batch. No intentional breaking application contract was established, so MAJOR remains 1. Do not rewrite history or create historical release tags.

| Batch | Capability | Commit anchors |
| --- | --- | --- |
| 1 | Grid and audio | `c0961d4` |
| 2 | iOS/Watch port | `9cb3580` |
| 3 | Watch complications | `fbbc317,9d14303` |
| 4 | Live Activity | `fed00c6,b873aaf` |
| 5 | Dark mode/audio refinements | `5951ff4` |
| 6 | Shared settings and CloudKit sync | `7fbda44,a600509` |
| 7 | HealthKit/Screen Time overlays and controls | `eaefc51,4542251,c475c91` |

Four trailing repair batches: persistence/sync 9753bc3, spacing 50952a8, Watch flow 8ab46a0, 32-bit raster 6ac1345. Imported native history was reviewed; consolidation is not a new beginning.

## Version authority

`Version.xcconfig` owns `APP_RELEASE_VERSION`. Native targets inherit it; scripts and generated web/package surfaces derive it. Platform build numbers and immutable commits remain separate. Update this source and CHANGELOG.md together for future releases. No deployment or installation is implied by this local adoption.

Derived labels can be refreshed with `python3 scripts/sync-version.py` and verified with `--check` (the `Scripts` spelling is canonical for Codex Pace and Sobriety Timer). Keep these generated copies synchronized when changing the authoritative source.
