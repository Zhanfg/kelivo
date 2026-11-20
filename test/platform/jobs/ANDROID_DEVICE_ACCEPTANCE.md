# W12 / #114: Android background job survival acceptance matrix

This file documents required **future** device tests. Dart `android_job_survival_test.dart` tests a wire-level simulation only. The VPS cannot prove OS process survival, Doze, alarm exactness, foreground service constraints, notification permissions, or an OEM background policy.

| Scenario | Minimum environments | Action | Required evidence | Status |
| --- | --- | --- | --- | --- |
| App swiped from recents | Android API24, 26, 31, 34+, physical OEM device | Begin resumable Job then swipe app | timestamps, persisted Job ID, process PID before/after, recovery & checksum | NOT TESTED |
| OS process death | Android API24/25 and API34+ | terminate process externally (not force-stop) | explicit interrupted/unknown result, no duplicate side effect | NOT TESTED |
| Force-stop | Physical Android | force-stop then manually relaunch | no unsupported automatic restart claim; recover only after user opens app | NOT TESTED |
| Doze / idle | Android emulator and physical device | `adb shell dumpsys deviceidle force-idle` then observe | Job receipts, delay, battery mode, elapsed time | NOT TESTED |
| Network lost / restored | Wi-Fi + cellular physical | disconnect and reconnect during transfer | verified bytes, retries, checksum, data cost | NOT TESTED |
| Battery saver / OEM restriction | Representative OEM physical device | enable extreme battery/background restriction | restriction diagnosis, actual resumed state, warning | NOT TESTED |
| Notification / foreground service | API26+ and 33+ | revoke notifications, begin allowed foreground work | service lifecycle, Android exceptions, status, permission handling | NOT TESTED |
| Reboot | Physical Android | persist active job then restart phone | persisted state readback, no automatic replay of non-idempotent work | NOT TESTED |

Capture anonymized OS/build, API level, exact steps, timestamps, command exit status, sanitized logs, job transition snapshots, hash of output, and pass/fail/blocked for each case. Never include tokens, personal files or private paths. Avoid claiming `adb force-stop` equals process kill: these exercise different Android behaviors. Respect platform background restrictions; no permission bypass.

Run contract-only tests: `flutter test test/platform/jobs/android_job_survival_test.dart`. This does **not** close issue #114; the device matrix must be filled after real testing.
