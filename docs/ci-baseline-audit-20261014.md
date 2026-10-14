# Kelivo baseline repair — 2026-10-14

Repository baseline: `master@8c4126c722d2c869f76c9b090d270101941466b4`.
Working branch: `fix/ci-runtime-baseline-20261014`, draft PR #17.

## Confirmed breakages

- Fast ARM64 APK run [35898277606](https://github.com/Zhanfg/kelivo/actions/runs/35898277606) failed at `:app:fetchProot`: `proot_5.1.107.92` was no longer present in the rolling Termux main pool.
- CI run [35898277613](https://github.com/Zhanfg/kelivo/actions/runs/35898277613) passed analyzer/format/l10n but failed test shards 0, 1 and 2.
- Latest Actions API listing checked on 2026-10-14 still showed 2026-09-23 runs. No new run was visible for PR #17 at the time of writing. This is a **verification blocker**, not evidence of passing CI.

## Fixes proposed in PR #17

- Keep the original pinned Termux 5.1.107.92 ELF checksum inventory. Do not silently substitute 5.1.107.96; binaries from another build require a new audited checksum manifest.
- On warm builds, validate all selected-ABI ELF hashes rather than relying on file existence.
- On a Termux pool miss, recover from the earlier Kelivo test APKs (tag `story-test-v1.3.0-7e299c9b`) whose full APK SHA-256 values are pinned in `tool/restore_pinned_proot.py`, then validate each extracted ELF against `tool/proot_checksums.txt`.
- Preserve fail-closed behavior on missing or mismatched hashes.
- Add offline unit tests and a CI verifier for all supported ABIs.
- Correct the mobile Tool Descriptions entry order (after Logs, before Sponsor), matching existing regression coverage.

Historical release APK restoration is a **recovery path**, not the desired permanent CDN: it downloads large debug APKs. Once CI is available, publish the small, checksum-pinned native `.deb` artifacts under a dedicated immutable release and migrate the fallback to that source.

## Remaining test failures from the last completed CI

| Shard | Failing test file | Failure |
|---|---|---|
| 0 | `assistant_settings_edit_prompt_tab_time_test.dart` | Info-button tap missed its hit target; four ISO-format UI variants failed. |
| 0 | `timeline_step_memo_test.dart` | Collapsed tool steps exceeded render-object budget. |
| 1 | `message_list_view_card_visibility_test.dart` | Parked-stream height estimate exceeded the 20% error threshold (20.277%). |
| 2 | `chat_input_section_skills_test.dart` | Desktop Skills popover interaction failed on macOS, Windows and Linux variants. |
| 2 | `tool_schema_settings_entry_test.dart` | Mobile row order was wrong; code ordering updated in PR #17, not yet rerun. |

Some logged Provider/asset errors occurred in intentionally simulated error paths and are not independently established production defects.

## Exit criteria

1. PR #17 has new visible CI results and the integrity test passes on ARM, ARM64 and x86_64.
2. Full Flutter CI test matrix is green (no skipped failures).
3. Android ARM64 debug APK builds and uploads successfully.
4. APK is installed and smoke-tested on an Android device: launch, Chat, Story state persistence, Agent runtime initialization, MCP/Skills access, background/foreground return, and export/restore.
5. No merge to `master` until all gates above are satisfied.

## Pending verification

PR creation did not cause a visible Actions run in the checked repository history. Review repository Actions enablement/permissions and use the PR checks view to determine why. The connector used for this audit does not provide workflow-dispatch or enablement controls.
