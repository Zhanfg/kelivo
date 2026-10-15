import hashlib
import io
import tarfile
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

SCRIPT = Path(__file__).resolve().parents[1] / "restore_pinned_proot.py"
spec = importlib.util.spec_from_file_location("restore_pinned_proot", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RestorePinnedProotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.abi = "arm64-v8a"
        self.source = self.root / "release.apk"
        self.payloads = {name: b"\x7fELF" + name.encode() for name in module.LIBS}
        with ZipFile(self.source, "w") as archive:
            for name, data in self.payloads.items():
                archive.writestr(f"lib/{self.abi}/{name}", data)
        self.expected = {
            f"android/app/src/main/jniLibs/{self.abi}/{name}": hashlib.sha256(data).hexdigest()
            for name, data in self.payloads.items()
        }
        for obj, name, val in [
            (module, "ROOT", self.root),
            (module, "LIBDIR", self.root / "android/app/src/main/jniLibs"),
            (module, "DIGESTS", {self.abi: hashlib.sha256(self.source.read_bytes()).hexdigest()}),
        ]:
            p = patch.object(obj, name, val)
            p.start()
            self.addCleanup(p.stop)

    def fake_download(self, cmd, *, check):
        self.assertTrue(check)
        shutil.copyfile(self.source, cmd[cmd.index("-o") + 1])

    def make_compact_archive(self):
        source = self.root / "compact.tar.xz"
        with tarfile.open(source, "w:xz") as archive:
            for name, data in self.payloads.items():
                info = tarfile.TarInfo(f"{self.abi}/{name}")
                info.size = len(data)
                archive.addfile(info, io.BytesIO(data))
        return source

    def test_compact_archive_validates_and_restores_elf(self):
        source = self.make_compact_archive()
        def fake(cmd, *, check):
            self.assertTrue(check)
            shutil.copyfile(source, cmd[cmd.index("-o") + 1])
        with patch.object(module.subprocess, "run", side_effect=fake):
            module.restore_compact_archive([self.abi], self.expected)
        module.verify_files([self.abi], self.expected)

    def test_compact_archive_rejects_corrupt_elf_atomically(self):
        source = self.make_compact_archive()
        bad = dict(self.expected)
        bad[f"android/app/src/main/jniLibs/{self.abi}/libtalloc.so"] = "f" * 64
        def fake(cmd, *, check):
            shutil.copyfile(source, cmd[cmd.index("-o") + 1])
        with patch.object(module.subprocess, "run", side_effect=fake):
            with self.assertRaisesRegex(ValueError, "Compact ELF checksum mismatch"):
                module.restore_compact_archive([self.abi], bad)
        for name in module.LIBS:
            self.assertFalse((module.LIBDIR / self.abi / name).exists())

    def test_restore_checks_both_apk_and_elf_hashes(self):
        with patch.object(module.subprocess, "run", side_effect=self.fake_download):
            module.restore([self.abi], self.expected)
        module.verify_files([self.abi], self.expected)

    def test_rejects_bad_source_without_writing(self):
        with patch.object(module, "DIGESTS", {self.abi: "0" * 64}):
            with patch.object(module.subprocess, "run", side_effect=self.fake_download):
                with self.assertRaisesRegex(ValueError, "APK checksum mismatch"):
                    module.restore([self.abi], self.expected)
        self.assertFalse((module.LIBDIR / self.abi / module.LIBS[0]).exists())

    def test_rejects_bad_elf_without_writing(self):
        bad = dict(self.expected)
        bad[f"android/app/src/main/jniLibs/{self.abi}/libproot_loader.so"] = "f" * 64
        with patch.object(module.subprocess, "run", side_effect=self.fake_download):
            with self.assertRaisesRegex(ValueError, "ELF checksum mismatch"):
                module.restore([self.abi], bad)
        self.assertFalse((module.LIBDIR / self.abi / module.LIBS[0]).exists())


if __name__ == "__main__":
    unittest.main()
