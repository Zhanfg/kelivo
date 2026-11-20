# msg-006 baseline-only CI control

This temporary pull request is a CI control against
`dev/upstream-first-20261117` at
`da1441f4fdf5a3d26fef64e8f7d38a023e1f1930`.

The marker document does not change application or test source code,
Dart dependencies, GitHub Actions, or any runtime configuration.

Its only purpose is to trigger the *same* `.github/workflows/pr-check.yml`
through `pull_request` and measure the already-existing baseline test failures.

The PR is Draft and must never be merged.
