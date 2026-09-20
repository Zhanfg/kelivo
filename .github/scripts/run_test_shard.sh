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

echo "Shard ${SHARD}/${SHARD_COUNT}: ${#selected[@]} of ${#all_files[@]} test files"
printf '  %s\n' "${selected[@]}"

set +e
flutter test --concurrency=1 --reporter expanded "${selected[@]}" 2>&1 | tee /tmp/shard.log
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 0 ]; then
  echo "::group::Shard ${SHARD} failure tail"
  tail -n 200 /tmp/shard.log
  echo "::endgroup::"
fi

exit "$status"
