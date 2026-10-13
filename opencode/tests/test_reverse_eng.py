"""Container-only setup must fail closed before any installation side effects."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "opencode/skills/reverse-eng/scripts"
SPEC = importlib.util.spec_from_file_location("container_check", SCRIPTS / "container.py")
CONTAINER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTAINER)


class ContainerDetectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_unverified_host_and_vm_are_rejected(self):
        with mock.patch.object(CONTAINER.subprocess, "run", return_value=mock.Mock(returncode=1)):
            self.assertFalse(CONTAINER.is_container(self.root))
            (self.root / "run/systemd").mkdir(parents=True)
            (self.root / "run/systemd/container").write_text("qemu\n")
            self.assertFalse(CONTAINER.is_container(self.root))

    def test_missing_detection_command_is_rejected(self):
        with mock.patch.object(CONTAINER.subprocess, "run", side_effect=FileNotFoundError):
            self.assertFalse(CONTAINER.is_container(self.root))

    def test_container_markers_are_accepted_without_external_probe(self):
        for name in (".dockerenv", "run/.containerenv", "run/systemd/container"):
            with self.subTest(name=name):
                marker = self.root / name
                marker.parent.mkdir(parents=True, exist_ok=True)
                marker.write_text("docker\n")
                with mock.patch.object(CONTAINER.subprocess, "run") as probe:
                    self.assertTrue(CONTAINER.is_container(self.root))
                    probe.assert_not_called()
                marker.unlink()

    def test_symlinked_marker_does_not_prove_container(self):
        target = self.root / "unrelated"
        target.write_text("")
        (self.root / ".dockerenv").symlink_to(target)
        with mock.patch.object(CONTAINER.subprocess, "run", return_value=mock.Mock(returncode=1)):
            self.assertFalse(CONTAINER.is_container(self.root))

    def test_generic_namespace_sandbox_and_wsl_are_rejected(self):
        for name in ("container-other", "bwrap", "wsl", "none"):
            with self.subTest(name=name), mock.patch.object(
                CONTAINER.subprocess, "run", return_value=mock.Mock(returncode=0, stdout=name)
            ):
                self.assertFalse(CONTAINER.is_container(self.root))

    def test_positive_systemd_container_probe_is_accepted(self):
        with mock.patch.object(CONTAINER.subprocess, "run", return_value=mock.Mock(returncode=0, stdout="docker\n")) as probe:
            self.assertTrue(CONTAINER.is_container(self.root))
            self.assertEqual(probe.call_args.args[0], ["systemd-detect-virt", "--container"])


class InstallationBoundaryTests(unittest.TestCase):
    def test_host_refusal_precedes_all_installation_side_effects(self):
        self.exercise(verified=False, mode="--install", status=1)

    def test_read_only_check_does_not_install_even_inside_container(self):
        self.exercise(verified=True, mode="--check", status=0)

    def exercise(self, verified, mode, status):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "bin"
            binary.mkdir()
            python = binary / "python3"
            python.write_text(f"#!/bin/sh\nexit {0 if verified else 1}\n")
            python.chmod(0o755)
            effects = root / "effects"
            for name in ("sudo", "apt-get", "curl", "npm", "pipx", "uv", "mkdir", "rm", "id"):
                path = binary / name
                path.write_text('#!/bin/sh\nprintf "%s\\n" "$0" >> "$SIDE_EFFECTS"\nexit 99\n')
                path.chmod(0o755)
            environment = dict(os.environ, PATH=f"{binary}:{os.environ['PATH']}", SIDE_EFFECTS=str(effects))
            for agent in ("opencode", "pi", "ox", "cod"):
                for skill in ("reverse-eng", "ansible"):
                    with self.subTest(agent=agent, skill=skill):
                        script = ROOT / agent / "skills" / skill / "scripts/install.sh"
                        result = subprocess.run(["bash", str(script), mode], env=environment,
                                                capture_output=True, text=True, check=False)
                        self.assertEqual(result.returncode, status, result.stderr)
                        self.assertFalse(effects.exists(), "installer ran a side-effecting command")
                        if not verified:
                            self.assertIn("refusing installation/setup", result.stderr)
