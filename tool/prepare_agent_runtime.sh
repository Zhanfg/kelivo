#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p assets/agent_runtime build/agent-runtime
image_tar="build/agent-runtime/wolfi-image.tar"
rootfs="assets/agent_runtime/wolfi-arm64.tar.gz"

docker run --rm \
  -v "$ROOT:/work" \
  -w /work \
  cgr.dev/chainguard/apko:latest \
  build assets/agent_runtime/apko.yaml kelivo-agent-runtime:ci "$image_tar"

load_output="$(docker load < "$image_tar")"
printf '%s\n' "$load_output"
image="$(printf '%s\n' "$load_output" | sed -n 's/^Loaded image: //p' | tail -n 1)"
if [[ -z "$image" ]]; then
  echo "Unable to determine image name from docker load output" >&2
  exit 1
fi

cid="$(docker create --platform linux/arm64 "$image" /bin/sh)"
cleanup() {
  docker rm -f "$cid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker export "$cid" | gzip -9 > "$rootfs"
test -s "$rootfs"
echo "Embedded Agent runtime:"
ls -lh "$rootfs"
sha256sum "$rootfs"
