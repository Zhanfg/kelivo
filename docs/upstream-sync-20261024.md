# KELIVO upstream reconciliation — 2026-10-24

## Baselines

- Product base: `fix/ci-runtime-baseline-20261014`, PR #17, SHA `dfef10d9257dbbed9dae9e9e0c2994c46f9d9d43`.
- Fork master: `8c4126c722d2c869f76c9b090d270101941466b4` (2026-09-23).
- Official upstream: `Chevey339/kelivo` `199647a5d718ed47783dde405007e4c080efdec5` (2026-10-24 04:46 UTC), used as the **pinned integration target**.
- GitHub compare (`Zhanfg/kelivo master...Chevey339:master` at audit time): diverged; fork **265 ahead**, **694 behind**. These are commit-graph counts, not resolved or tested feature counts.
- Latest tagged upstream release observed: `v1.3.1` (2026-10-09); master has newer unreleased work.

## Integration policy

The fork's Story runtime, Agent/Pi/OMP bridge, model-provider extensions, MCP identity, mobile sandbox, signing/CI, and local-user data contracts are **local product features**, not disposable patches. Never use `git reset --hard upstream/master`, auto-resolve every merge conflict with `-X theirs`, or fast-forward `master`.

The companion Action checks a pinned full-upstream merge in an isolated runner. Conflicts are captured as a text artifact and job summary; **nothing from the full upstream merge is published automatically**.

Two narrower upstream commits are proposed for opportunistic cherry-pick into this integration branch only, if Git can apply them cleanly and CI analysis succeeds:
- `0169e760c0c369eaebfc1c55539f113a16992a25`: keep chat wallpaper masks aligned with sidebars.
- `9969ec9f9c6f5b548bfb1801e84ef53b1133b7ef`: save/revoke session shell permissions immediately.

Upstream commits are third-party source input. The Action avoids exposing write credentials while testing and obtains a scoped push credential only in the final publish step. A passing cherry-pick check does not imply device-level verification.

## Priorities after initial merge probe

1. Reconcile conflicts by domain, starting with security, databases/backup migrations, workspace approvals, MCP, provider protocols, and Story world-book compatibility.
2. Port the newer upstream user-facing browser, backup encryption and world-book transfer features only after dependency and schema reviews.
3. Keep Agent replay/continuation, crash recovery, package migration and guest secret isolation as **P0 release gates**.
4. Run Flutter/Dart, Android ABI/rootfs, and on-device Story/Agent regression suites on the integrated candidate before merging.
5. Preserve PR #17 as Draft until its own acceptance gates pass.

## Local changes in this branch

- Reject malformed or traversal-shaped Agent journal task IDs before forming disk paths.
- Add regression tests for malformed IDs and ensure the journal root remains untouched.

**This document is a synchronization record, not a claim that all upstream changes or a stable release have been integrated.**
