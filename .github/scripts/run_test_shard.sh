#!/usr/bin/env bash
#
# Runs one shard of the `test/` suite.
#
# Sharding is done by test *file*: `flutter test` already runs each file in its
# own isolate, so splitting by file preserves isolation while cutting wall-clock
# time roughly by the shard count.
#
# Usage:
#   SHARD=0 SHARD_COUNT=4 .github/scripts/run_test_shard.sh
#
set -euo pipefail

: "${SHARD:?SHARD is required}"
: "${SHARD_COUNT:?SHARD_COUNT is required}"
TEST_CONCURRENCY="${TEST_CONCURRENCY:-2}"

mapfile -t all_files < <(find test -type f -name '*_test.dart' | sort)

if [ "${#all_files[@]}" -eq 0 ]; then
  echo "No test files found." >&2
  exit 1
fi

selected=()
for i in "${!all_files[@]}"; do
  if (( i % SHARD_COUNT == SHARD )); then
    selected+=("${all_files[$i]}")
  fi
done

if [ "${#selected[@]}" -eq 0 ]; then
  # Guard against accidentally running the whole suite (bare `flutter test`
  # discovers every file under test/) and against out-of-range shard numbers.
  echo "Shard ${SHARD}/${SHARD_COUNT} has no test files; nothing to run."
  exit 0
fi

echo "Shard ${SHARD}/${SHARD_COUNT}: ${#selected[@]} of ${#all_files[@]} test files"
printf '  %s\n' "${selected[@]}"

set +e
flutter test --concurrency="$TEST_CONCURRENCY" --reporter expanded "${selected[@]}" 2>&1 | tee /tmp/shard.log
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 0 ]; then
  echo "::group::Shard ${SHARD} failure tail"
  tail -n 200 /tmp/shard.log
  echo "::endgroup::"
fi

exit "$status"
