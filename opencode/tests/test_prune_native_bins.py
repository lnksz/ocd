"""Pruning must preserve runnable entry points and reject unsafe layouts."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("prune_native", ROOT / "opencode/prune-native-bins.py")
PRUNE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRUNE)


class NativePackageTests(unittest.TestCase):
    def setUp(self):
        (ROOT / "tmp").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=ROOT / "tmp")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / "package"
        self.package.mkdir()

    def binary(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"\x7fELFtest fixture")
        return path

    def metadata(self, name="@opencode/cli", bins=None, optional=None):
        (self.package / "package.json").write_text(json.dumps({
            "name": name,
            "bin": bins or {"opencode": "bin/opencode.exe"},
            "optionalDependencies": optional or {"@opencode/cli-linux-x64": "1.0.0"},
        }))

    def test_native_entry_point_survives_platform_package_removal(self):
        for name, dependency in (("@opencode/cli", "@opencode/cli-linux-x64"),
                                 ("opencode-ai", "opencode-linux-x64"),
                                 ("@ast-grep/cli", "@ast-grep/cli-linux-x64-gnu")):
            with self.subTest(name=name):
                self.metadata(name=name, optional={dependency: "1"})
                native = self.binary(self.package / "bin/opencode.exe")
                redundant = self.binary(self.package / "node_modules" / dependency / "bin/native")
                unrelated = self.binary(self.package / "node_modules/unrelated/bin/native")
                PRUNE.prune(self.package)
                self.assertTrue(native.exists())
                self.assertFalse(redundant.exists())
                self.assertTrue(unrelated.exists())

    def test_symlink_entry_point_keeps_its_selected_platform_package(self):
        selected = "@opencode/cli-linux-x64"
        unused = "@opencode/cli-linux-x64-musl"
        self.metadata(optional={selected: "1", unused: "1"})
        native = self.binary(self.package / "node_modules" / selected / "bin/native")
        redundant = self.binary(self.package / "node_modules" / unused / "bin/native")
        launcher = self.package / "bin/opencode.exe"
        launcher.parent.mkdir()
        launcher.symlink_to(native)
        PRUNE.prune(self.package)
        self.assertEqual(launcher.read_bytes(), native.read_bytes())
        self.assertFalse(redundant.exists())

    def test_javascript_launcher_refuses_cleanup_before_deleting_anything(self):
        self.metadata()
        self.binary(self.package / "bin/opencode.exe").write_text("#!/usr/bin/env node\n")
        native = self.binary(self.package / "node_modules/@opencode/cli-linux-x64/bin/native")
        with self.assertRaisesRegex(ValueError, "not a native ELF"):
            PRUNE.prune(self.package)
        self.assertTrue(native.exists())

    def test_entry_point_outside_package_is_rejected(self):
        self.metadata(bins={"opencode": "../outside"})
        self.binary(self.root / "outside")
        with self.assertRaisesRegex(ValueError, "executable escapes"):
            PRUNE.prune(self.package)

    def test_symlinked_dependency_does_not_allow_external_deletion(self):
        self.metadata()
        self.binary(self.package / "bin/opencode.exe")
        external = self.binary(self.root / "external/bin/native")
        dependency = self.package / "node_modules/@opencode/cli-linux-x64"
        dependency.parent.mkdir(parents=True)
        dependency.symlink_to(external.parent.parent, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "unexpected platform package path"):
            PRUNE.prune(self.package)
        self.assertTrue(external.exists())

    def test_other_optional_dependencies_and_undeclared_variants_are_retained(self):
        self.metadata(optional={"unrelated": "1", "@opencode/cli-../../escape": "1"})
        self.binary(self.package / "bin/opencode.exe")
        native = self.binary(self.package / "node_modules/@opencode/cli-linux-x64/bin/native")
        unrelated = self.binary(self.package / "node_modules/unrelated/bin/native")
        PRUNE.prune(self.package)
        self.assertTrue(native.exists())
        self.assertTrue(unrelated.exists())


if __name__ == "__main__":
    unittest.main()
