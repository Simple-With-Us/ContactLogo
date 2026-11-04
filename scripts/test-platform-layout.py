#!/usr/bin/env python3
"""Exercise the canonical-layout gate and its temporary web bridge."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


GATE = Path(__file__).with_name("check-platform-layout.py")
CANONICAL = (
    "apps/android",
    "apps/ios",
    "apps/macos",
    "apps/macos-app-store",
    "apps/web",
)


class PlatformLayoutFixtures(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="contactlogo-layout-")
        self.root = Path(self.temp.name)
        for directory in CANONICAL:
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        (self.root / "apps/web/index.bin").write_bytes(b"web fixture\x00\xff\n")
        executable = self.root / "apps/web/run-fixture.sh"
        executable.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        executable.chmod(0o755)
        self._mirror()
        (self.root / "scripts").mkdir()
        shutil.copyfile(GATE, self.root / "scripts/check-platform-layout.py")
        (self.root / ".gitignore").write_text(
            "apps/web/dist/\nweb/dist/\n", encoding="utf-8"
        )
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(
            ["git", "-C", str(self.root), "-c", "user.name=Fixture", "-c",
             "user.email=fixture@example.invalid", "add", "-A"],
            check=True,
        )

    def tearDown(self):
        self.temp.cleanup()

    def _mirror(self):
        shutil.copytree(self.root / "apps/web", self.root / "web", dirs_exist_ok=True)

    def _stage(self):
        subprocess.run(["git", "-C", str(self.root), "add", "-A"], check=True)

    def _run_gate(self):
        return subprocess.run(
            [sys.executable, str(self.root / "scripts/check-platform-layout.py")],
            cwd=self.root,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_valid_bridge_matches_bytes_and_executable_mode(self):
        result = self._run_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("web bridge matches apps/web", result.stdout)

    def test_changed_mirror_bytes_fail(self):
        (self.root / "web/index.bin").write_bytes(b"different\x00\xff\n")
        result = self._run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("tracked worktree file differs from index: web/index.bin", result.stdout)

    def test_missing_mirror_file_fails(self):
        (self.root / "web/index.bin").unlink()
        result = self._run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing tracked worktree file: web/index.bin", result.stdout)

    def test_absent_bridge_directory_fails(self):
        shutil.rmtree(self.root / "web")
        result = self._run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing required legacy web deployment bridge: web", result.stdout)

    def test_extra_tracked_mirror_file_fails(self):
        (self.root / "web/extra.txt").write_text("extra\n", encoding="utf-8")
        self._stage()
        result = self._run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("extra tracked web bridge file: web/extra.txt", result.stdout)

    def test_mirror_executable_mode_must_match(self):
        (self.root / "web/run-fixture.sh").chmod(0o644)
        self._stage()
        result = self._run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("mode 100644 != 100755", result.stdout)

    def test_missing_canonical_directory_fails(self):
        (self.root / "apps/macos-app-store").rmdir()
        result = self._run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing canonical directory: apps/macos-app-store", result.stdout)

    def test_bridge_directory_symlink_fails(self):
        shutil.rmtree(self.root / "web")
        (self.root / "web").symlink_to("apps/web", target_is_directory=True)
        result = self._run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("directories cannot be symlinks: web", result.stdout)

    def test_unignored_web_build_output_fails(self):
        (self.root / ".gitignore").write_text(
            "apps/web/dist/\n", encoding="utf-8"
        )
        self._stage()
        result = self._run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("web build output is not gitignored: web/dist", result.stdout)

    def test_nested_unignored_build_output_fails(self):
        (self.root / ".gitignore").write_text(
            "apps/web/dist/\nweb/dist/\n!web/dist/keep.txt\n", encoding="utf-8"
        )
        self._stage()
        result = self._run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("web build output is un-ignored by a negation rule: web/dist", result.stdout)

    def test_tracked_build_output_fails(self):
        (self.root / "web/dist").mkdir(parents=True)
        (self.root / "web/dist/tracked.html").write_text("tracked\n", encoding="utf-8")
        subprocess.run(
            ["git", "-C", str(self.root), "add", "-f", "web/dist/tracked.html"],
            check=True,
        )
        result = self._run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("web build output is tracked: web/dist", result.stdout)

    def test_casefold_path_collision_fails(self):
        lower_directory = self.root / "apps/ios"
        upper_directory = self.root / "apps/IOS"
        if upper_directory.exists() and upper_directory.samefile(lower_directory):
            self.skipTest("filesystem aliases apps/IOS to apps/ios")
        upper = self.root / "apps/ios/README.txt"
        lower = self.root / "apps/IOS/readme.txt"
        upper.parent.mkdir(parents=True, exist_ok=True)
        lower.parent.mkdir(parents=True, exist_ok=True)
        upper.write_text("one\n", encoding="utf-8")
        lower.write_text("two\n", encoding="utf-8")
        self._stage()
        result = self._run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("case-fold path collision:", result.stdout)

    def test_top_level_apps_case_variant_fails(self):
        canonical = self.root / "apps"
        variant = self.root / "Apps"
        if variant.exists() and variant.samefile(canonical):
            self.skipTest("filesystem aliases Apps to apps")
        variant.mkdir()
        (variant / "marker.txt").write_text("legacy\n", encoding="utf-8")
        self._stage()
        result = self._run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected case variant for required root directory: Apps", result.stdout)
        self.assertIn("case-fold root-name collision: Apps <> apps", result.stdout)


if __name__ == "__main__":
    unittest.main()
