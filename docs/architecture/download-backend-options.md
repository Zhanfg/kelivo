# ADR (provisional): cross-platform download backend options — W42 / #144

- **Status:** proposed research; no production backend switch approved.
- **Baseline:** `4df36834ca6bad272e66df8652c62c55f6314f4e` (`dev/upstream-first-20261117`).
- **Dependencies:** W41 / #143 Range fault-injection fixture; Parent #100; coordination #102.
- **Scope:** Android API 24–25, newer Android, iOS, Windows, macOS, and Linux.
- **Explicitly out of scope:** migrating the engine, editing `pubspec.yaml`, adding dependencies, changing CI, or asserting unmeasured throughput/size claims.

## Current evidence and reproducibility

The repository already has a single-connection Dart HTTP executor at `lib/core/services/jobs/executors/http_download_executor.dart`. W41 contributes `tool/benchmarks/download/range_fixture.py` and `test_range_fixture.py`, a deterministic HTTP fixture covering 200, 206, 416, `If-Range`, ETag changes, ignored Range, disconnects, and throttling. On this development environment the following completed successfully:

```sh
python3 -m unittest discover -s tool/benchmarks/download -p 'test_range_fixture.py' -v
# Ran 6 tests in 0.524s — OK (fixture contract only; NOT a backend throughput benchmark)
```

The fixture is bounded to at most 64 MiB per payload. These tests **do not** exercise real Kotlin, Dart, Rust, or aria2 client implementations; they validate the server fixture. No comparable APK/IPA/binary size, peak RSS, CPU, transfer throughput, battery, or maintenance-hour data have yet been collected. Do not rank performance by the test runtime above.

## Candidate matrix (risk assessment, not measured performance)

| Candidate | Android 24–25 | iOS | Windows / macOS / Linux | HTTP Range & resume | Build / package / maintenance cost |
| --- | --- | --- | --- | --- | --- |
| **Dart `dart:io`** (existing baseline) | Must validate exact Flutter/SDK minSdk on both APIs | Supported in Flutter native app | Existing Flutter desktop path | Implement/validate `206`, `Content-Range`, ETag and persistence ourselves | Lowest integration delta; no extra native artifact. Actual size and CPU **not measured**. |
| **Kotlin/JVM** | Android viable in principle; verify API-specific TLS/storage | No drop-in JVM runtime for iOS | JVM distribution required for desktop implementation | Library/engine-dependent; must benchmark real candidate | Android-first integration; cross-platform duplication or native bridge. Package cost **not measured**. |
| **Rust via FFI** | NDK target and `minSdkVersion` require explicit API 24/25 builds/tests | Native static library plus iOS signing/ABI integration | Separate target builds and FFI packaging | Library-dependent; integrity and safe pause/cancel must be tested | Larger toolchain/ABI matrix, potential native performance benefits **unproven**. |
| **aria2/libaria2 (C++)** | Native packaging and ABI/API24–25 validation required | Requires native linkage and iOS background-execution audit | Upstream project supports cross-platform CLI/core | Supports multi-connection and RPC; verify semantics with W41 fault fixture | Larger external component and native dependency/patch burden; size **not measured**. |

**Compatibility gate:** Do not equate the host project using `flutter.minSdkVersion` with evidence of an actual Android 24 or 25 run. iOS background transfer constraints, sandbox permissions, signed native frameworks and App Store policy must be separately verified. Desktop comparisons must specify CPU architecture and packaging format.

## Comparable benchmark protocol

1. Build **four isolated prototype clients**, identical request headers and retry policy, pinned dependency versions, consistent output checksum and temporary directory. No prototype becomes the production dispatcher without a separate approval.
2. For every client, test W41 fixture modes: plain `200`, byte range `206`, unsatisfiable `416`, server ignores range, `If-Range` mismatch, ETag changes between requests, early disconnect, throttle, and delayed body. On resume, validate SHA-256 of the **whole** downloaded file, not merely the final segment.
3. Execute Android 24 and 25 emulators **and** at least one physical Android device, plus iOS, Windows, macOS, Linux CI/hosts. If a platform cannot be executed, record `not tested` rather than inferring support.
4. Run a warm-up and at least ten timed trials per platform/backend/fixture; report median and p95 wall-clock throughput in MiB/s, peak RSS MiB, CPU time, failure rate, and battery impact where measurable. Record network shaping/latency, concurrency, power mode, toolchain SHA, OS version and hardware.
5. Measure release artifact **delta** (KB/MiB) relative to the same Flutter baseline: APK splits/AAB, iOS IPA, and each desktop distribution format. Include native symbols/strip configuration; do not compare compressed release sizes against unstripped debug builds.
6. Include maintainability: native ABI count, deterministic/offline rebuild, patch count, audit/update burden, license/SBOM, restart recovery, cancellation and corrupt-download handling. Require no new credentials/permissions.

### Benchmark record template

| Backend | Platform/API | Build SHA | Throughput median/p95 (MiB/s) | Peak RSS (MiB) | Release size delta (MiB) | Faults passed/total | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Dart baseline | Android API24 | not measured | not measured | not measured | not measured | not executed | pending |
| Dart baseline | Android API25 | not measured | not measured | not measured | not measured | not executed | pending |
| Kotlin | Android API24/25 | not built | not measured | not measured | not measured | not executed | pending |
| Rust FFI | five platforms | not built | not measured | not measured | not measured | not executed | pending |
| aria2/libaria2 | five platforms | not built | not measured | not measured | not measured | not executed | pending |

## Decision and rollback gates

**Interim decision:** keep the existing Dart implementation until comparable data exists. This is a *change-minimization decision*, not a declaration that Dart is fastest. Consider Rust FFI or aria2 only if measured gains are substantial and all required target/platform, resume-integrity, security, reproducibility and maintenance gates pass. Kotlin may be a device-specific adapter but is not a single shared iOS/desktop solution.

**Block merge of any engine switch** until: API24–25 compatibility proven, full W41 fault matrix passes for each supported target, checksum-on-resume proven, package size and RSS measured, licenses reviewed, incremental build jobs available, and rollback to previous Dart path exercised. The current ADR does not authorize an implementation change.

## Primary documentation

- Flutter supported deployment platforms: https://docs.flutter.dev/reference/supported-platforms
- Flutter native interop and platform integration: https://docs.flutter.dev/platform-integration
- Rust Android target and NDK API boundaries: https://doc.rust-lang.org/rustc/platform-support/android.html
- aria2 upstream project / JSON-RPC / C++: https://github.com/aria2/aria2
- aria2 official manual: https://aria2.github.io/manual/en/html/
