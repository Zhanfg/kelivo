#!/usr/bin/env bash
# Restore the pinned Termux PRoot runtime from the checked-in archive.
# Usage: ./tool/fetch_proot.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKSUMS_FILE="$SCRIPT_DIR/proot_checksums.txt"
ARCHIVE="$REPO_ROOT/dependencies/termux/proot-5.1.107.92.tar.xz"
JNI_LIBS="$REPO_ROOT/android/app/src/main/jniLibs"

TERMUX_POOL="${TERMUX_POOL:-https://packages.termux.dev/apt/termux-main/pool/main}"

# Rolling Termux versions. Override with env vars if the pool moves again.
PROOT_VERSION="${PROOT_VERSION:-5.1.107.92}"
TALLOC_VERSION="${TALLOC_VERSION:-2.4.3}"
SHMEM_VERSION="${SHMEM_VERSION:-0.7}"

# termux-arch:android-abi
ALL_ABIS=(
  "arm:armeabi-v7a"
  "aarch64:arm64-v8a"
  "x86_64:x86_64"
)

ABIS=()
if [[ -n "${KELIVO_ANDROID_ABIS:-}" ]]; then
  IFS=',' read -r -a requested_abis <<< "$KELIVO_ANDROID_ABIS"
  for pair in "${ALL_ABIS[@]}"; do
    android_abi="${pair##*:}"
    for requested in "${requested_abis[@]}"; do
      if [[ "$android_abi" == "${requested//[[:space:]]/}" ]]; then
        ABIS+=("$pair")
        break
      fi
    done
  done
  if [[ "${#ABIS[@]}" -eq 0 ]]; then
    echo "error: KELIVO_ANDROID_ABIS selected no supported ABI: $KELIVO_ANDROID_ABIS" >&2
    exit 1
  fi
else
  ABIS=("${ALL_ABIS[@]}")
fi

selected_abi() {
  local candidate="$1"
  local pair
  for pair in "${ABIS[@]}"; do
    [[ "${pair##*:}" == "$candidate" ]] && return 0
  done
  return 1
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

TMPDIR_FETCH="$(mktemp -d "${TMPDIR:-/tmp}/kelivo-proot.XXXXXX")"
trap 'rm -rf "$TMPDIR_FETCH"' EXIT

echo "Extracting pinned Termux PRoot runtime from $ARCHIVE"
tar -xJf "$ARCHIVE" -C "$TMPDIR_FETCH"

# Verify every library before replacing any existing local runtime files.
while read -r hash path; do
  [[ -z "${hash:-}" || "$hash" == \#* ]] && continue
  relative_path="${path#android/app/src/main/jniLibs/}"
  actual="$(sha256_of "$TMPDIR_FETCH/$relative_path")"
  if [[ "$actual" != "$hash" ]]; then
    echo "error: checksum mismatch for $path" >&2
    echo "  expected: $hash" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
  echo "Verifying $CHECKSUMS_FILE"
  local hash path actual
  while read -r hash path; do
    [[ -z "${hash:-}" || "$hash" == \#* ]] && continue
    if [[ "$path" =~ android/app/src/main/jniLibs/([^/]+)/ ]]; then
      if ! selected_abi "${BASH_REMATCH[1]}"; then
        continue
      fi
    fi
    if [[ ! -f "$REPO_ROOT/$path" ]]; then
      echo "error: checksum path missing: $path" >&2
      exit 1
    fi
    actual="$(sha256_of "$REPO_ROOT/$path")"
    if [[ "$actual" != "$hash" ]]; then
      echo "error: checksum mismatch for $path" >&2
      echo "  expected: $hash" >&2
      echo "  actual:   $actual" >&2
      exit 1
    fi
  done < "$CHECKSUMS_FILE"
}

# Validate native library hashes on *every* Gradle build, including cached builds.
# Never trust file-existence alone to establish that a JNI binary is safe.
if python3 "$SCRIPT_DIR/restore_pinned_proot.py" check >/dev/null 2>&1; then
  echo "Using SHA-256 verified cached PRoot binaries."
  exit 0
fi

TMPDIR_FETCH="$(mktemp -d "${TMPDIR:-/tmp}/kelivo-proot.XXXXXX")"
cleanup() { rm -rf "$TMPDIR_FETCH"; }
trap cleanup EXIT

echo "Fetching Termux proot ${PROOT_VERSION} (+ libtalloc ${TALLOC_VERSION}, libandroid-shmem ${SHMEM_VERSION})"
echo "Pool: $TERMUX_POOL"

# The historical OpenMinis pin is documented; fail clearly if someone overrides
# to a version the pool no longer serves.
if ! curl -fsI --retry 2 --retry-delay 2 --retry-all-errors \
    "${TERMUX_POOL}/p/proot/proot_${PROOT_VERSION}_aarch64.deb" >/dev/null; then
  echo "Pinned Termux pool package unavailable; checking compact immutable upstream archive."
  if python3 "$SCRIPT_DIR/restore_pinned_proot.py" restore-archive; then
    exit 0
  fi
  echo "Compact source unavailable or mismatched; falling back to checksum-verified Kelivo APKs."
  python3 "$SCRIPT_DIR/restore_pinned_proot.py" restore
  exit 0
fi

for pair in "${ABIS[@]}"; do
  termux_arch="${pair%%:*}"
  android_abi="${pair##*:}"
  dest_dir="$JNI_LIBS/$android_abi"
  mkdir -p "$dest_dir"

  work="$TMPDIR_FETCH/$termux_arch"
  mkdir -p "$work"

  echo ""
  echo "== ${termux_arch} → ${android_abi} =="

  curl -fSL --retry 5 --retry-delay 2 --retry-all-errors -o "$work/proot.deb" \
    "${TERMUX_POOL}/p/proot/proot_${PROOT_VERSION}_${termux_arch}.deb"
  curl -fSL --retry 5 --retry-delay 2 --retry-all-errors -o "$work/talloc.deb" \
    "${TERMUX_POOL}/libt/libtalloc/libtalloc_${TALLOC_VERSION}_${termux_arch}.deb"
  curl -fSL --retry 5 --retry-delay 2 --retry-all-errors -o "$work/shmem.deb" \
    "${TERMUX_POOL}/liba/libandroid-shmem/libandroid-shmem_${SHMEM_VERSION}_${termux_arch}.deb"

  extract_deb "$work/proot.deb" "$work/proot"
  extract_deb "$work/talloc.deb" "$work/talloc"
  extract_deb "$work/shmem.deb" "$work/shmem"

  proot_bin="$(find_regular_file "$work/proot" proot)" \
    || { echo "error: proot binary missing from deb" >&2; find "$work/proot" -type f; exit 1; }
  loader_bin="$(find_regular_file "$work/proot" loader)" \
    || { echo "error: proot loader missing from deb" >&2; find "$work/proot" -type f; exit 1; }
  talloc_bin="$(find_regular_file "$work/talloc" 'libtalloc.so.2.*' 'libtalloc.so.2' 'libtalloc.so')" \
    || { echo "error: libtalloc missing from deb" >&2; find "$work/talloc" -type f; exit 1; }
  shmem_bin="$(find_regular_file "$work/shmem" 'libandroid-shmem.so')" \
    || { echo "error: libandroid-shmem missing from deb" >&2; find "$work/shmem" -type f; exit 1; }

  copy_elf "$proot_bin" "$dest_dir/libproot_exec.so"
  copy_elf "$loader_bin" "$dest_dir/libproot_loader.so"
  copy_elf "$talloc_bin" "$dest_dir/libtalloc.so"
  copy_elf "$shmem_bin" "$dest_dir/libandroid-shmem.so"

  for so in libproot_exec.so libproot_loader.so libtalloc.so libandroid-shmem.so; do
    path="$dest_dir/$so"
    if [[ ! -f "$path" || ! -s "$path" ]]; then
      echo "error: missing or empty $path after extract" >&2
      exit 1
    fi
    if command -v file >/dev/null 2>&1; then
      echo "  $(file "$path")"
    fi
    echo "  sha256 $(sha256_of "$path")  ${android_abi}/${so}"
  done
done

echo ""
echo "Checking required binaries exist"
for pair in "${ABIS[@]}"; do
  android_abi="${pair##*:}"
  for so in libproot_exec.so libproot_loader.so libtalloc.so libandroid-shmem.so; do
    path="$JNI_LIBS/$android_abi/$so"
    if [[ ! -f "$path" || ! -s "$path" ]]; then
      echo "error: required binary missing: $path" >&2
      exit 1
    fi
  done
done

echo ""
verify_checksums
echo "Checksums match $CHECKSUMS_FILE"

echo ""
echo "Done. Binaries are local-only (gitignored). NOTICE lives at:"
echo "  $JNI_LIBS/NOTICE"
