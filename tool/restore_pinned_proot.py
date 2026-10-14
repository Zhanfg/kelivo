#!/usr/bin/env python3
"""Restore pinned PRoot ELF files from existing, independently hashed Kelivo APKs.

The rolling Termux pool may delete historical .deb versions. The September
2026 release APKs preserve the original binaries; every APK and every extracted
ELF is SHA-256 verified before being installed into jniLibs.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
LIBDIR = ROOT / "android/app/src/main/jniLibs"
CHECKSUMS = ROOT / "tool/proot_checksums.txt"
RELEASE = "https://github.com/Zhanfg/kelivo/releases/download/story-test-v1.3.0-7e299c9b/"
DIGESTS = {
    "armeabi-v7a": "698aa59b8590cf8f4732771fbe86f8d22a0995ae0d487bcb778903479827f9a7",
    "arm64-v8a": "30858412a7c8d9d87200248f41085986a926eb24698353925e59307f9b7e4471",
    "x86_64": "2a20caa22d2f2344bb503e77b114ee3a5a87e427e41bbd88867ef7996fac1b08",
}
LIBS = ("libproot_exec.so", "libproot_loader.so", "libtalloc.so", "libandroid-shmem.so")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def selected_abis() -> list[str]:
    requested = os.environ.get("KELIVO_ANDROID_ABIS", "").strip()
    names = [x.strip() for x in requested.split(",")] if requested else list(DIGESTS)
    if not names or any(x not in DIGESTS for x in names):
        raise ValueError("Unsupported KELIVO_ANDROID_ABIS")
    return names


def expected_hashes() -> dict[str, str]:
    result = {}
    for line in CHECKSUMS.read_text().splitlines():
        columns = line.split()
        if len(columns) == 2 and not columns[0].startswith("#"):
            result[columns[1]] = columns[0].lower()
    return result


def verify_files(abis: list[str], expected: dict[str, str]) -> None:
    for abi in abis:
        for name in LIBS:
            rel = f"android/app/src/main/jniLibs/{abi}/{name}"
            expected_hash = expected.get(rel)
            path = ROOT / rel
            if not expected_hash or not path.is_file() or digest(path.read_bytes()) != expected_hash:
                raise ValueError(f"Missing or mismatched PRoot ELF: {abi}/{name}")


def restore(abis: list[str], expected: dict[str, str]) -> None:
    with tempfile.TemporaryDirectory(prefix="kelivo-proot-verified-") as directory:
        staged: list[tuple[Path, bytes]] = []
        for abi in abis:
            filename = f"Kelivo_1.3.0%2B79_Story_TEST_7e299c9b_{abi}-debug.apk"
            apk = Path(directory) / f"{abi}.apk"
            url = RELEASE + filename
            print(f"Downloading checksum-pinned release APK for {abi}", flush=True)
            subprocess.run(
                ["curl", "-fLSs", "--retry", "3", "--retry-delay", "2", "-o", str(apk), url],
                check=True,
            )
            if digest(apk.read_bytes()) != DIGESTS[abi]:
                raise ValueError(f"Release APK checksum mismatch for {abi}")
            with zipfile.ZipFile(apk) as archive:
                for name in LIBS:
                    rel = f"android/app/src/main/jniLibs/{abi}/{name}"
                    expected_hash = expected.get(rel)
                    binary = archive.read(f"lib/{abi}/{name}")
                    if not expected_hash or not binary.startswith(b"\x7fELF"):
                        raise ValueError(f"Invalid ELF or unpinned path: {abi}/{name}")
                    if digest(binary) != expected_hash:
                        raise ValueError(f"Pinned ELF checksum mismatch: {abi}/{name}")
                    staged.append((LIBDIR / abi / name, binary))
        # No artifact is installed until all requested ELF files verify.
        for path, binary in staged:
            path.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as target:
                target.write(binary)
                target.flush()
                os.fchmod(target.fileno(), 0o755)
                temporary = Path(target.name)
            os.replace(temporary, path)
    verify_files(abis, expected)
    print("All PRoot native ELF checksums verified.", flush=True)


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"check", "restore"}:
        print("Usage: restore_pinned_proot.py check|restore", file=sys.stderr)
        return 2
    try:
        abis = selected_abis()
        expected = expected_hashes()
        if sys.argv[1] == "check":
            verify_files(abis, expected)
        else:
            restore(abis, expected)
        return 0
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        print(f"PRoot integrity: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
