"""Check publishing commands with a recording engine; never contact a registry."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
ENGINE = r'''#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps(args) + "\n")
operation = args[0]
if operation == "run":
    operation = "verify" if "--entrypoint" in args else "resolve"
if operation == os.environ.get("FAIL_OPERATION"):
    sys.exit(37)
if operation == "resolve":
    print(os.environ.get("RESOLVED_VERSION", "1.2.3"))
elif operation == "verify":
    print(os.environ.get("ACTUAL_VERSION", "1.2.3"))
'''


class BuildImageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ox build ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.engine = self.base / "engine"
        self.engine.write_text(ENGINE)
        self.engine.chmod(0o755)
        # Keep the OpenCode regression case off master regardless of checkout.
        git = self.base / "git"
        git.write_text("#!/bin/sh\nprintf 'test-branch\\n'\n")
        git.chmod(0o755)
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith(("OX_", "OCD_", "PID_", "OPENCODE_", "GIT_"))
            and key not in ("PI_CODING_AGENT_VERSION", "BASH_ENV", "NODE_IMAGE_FOR_NPM_VIEW")
        }
        self.env.update(CONTAINER_ENGINE=str(self.engine), CALLS=str(self.base / "calls.jsonl"),
                        PATH=f"{self.base}:{os.environ['PATH']}")

    def run_build(self, *args, code=0):
        result = subprocess.run(["bash", str(ROOT / "build-image.sh"), *args],
                                cwd=self.base, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def calls(self):
        return [json.loads(line) for line in Path(self.env["CALLS"]).read_text().splitlines()]

    def test_ox_verifies_version_before_publishing_both_tags(self):
        self.run_build("ox", "--push")
        resolve, build, verify, push_version, push_latest = self.calls()
        self.assertEqual(resolve[-4:], ["npm", "view", "opencode-ai@latest", "version"])
        self.assertIn("OPENCODE_VERSION=1.2.3", build)
        self.assertIn("OPENCODE_PKG=opencode-ai", build)
        self.assertIn(str(ROOT / "ox" / "Dockerfile"), build)
        self.assertEqual(build[-1], str(ROOT / "ox"))
        self.assertEqual(verify, ["run", "--rm", "--entrypoint", "opencode",
                                  "docker.io/lnksz/ox:1.2.3", "--version"])
        self.assertEqual(push_version, ["push", "docker.io/lnksz/ox:1.2.3"])
        self.assertEqual(push_latest, ["push", "docker.io/lnksz/ox:latest"])

    def test_explicit_version_and_no_cache_without_push(self):
        self.run_build("ox", "--no-cache", "beta")
        resolve, build, _ = self.calls()
        self.assertIn("opencode-ai@beta", resolve)
        self.assertIn("--no-cache", build)
        self.assertFalse(any(call[0] == "push" for call in self.calls()))

    def test_ox_overrides_are_independent(self):
        self.env.update(OX_ENGINE=str(self.engine), CONTAINER_ENGINE="not-an-engine",
                        OX_IMAGE_REPO="registry.example/team/ox", OX_PUSH="1",
                        OX_OPENCODE_VERSION="next", OX_OPENCODE_PKG="custom-opencode",
                        OCD_ENGINE="wrong", OCD_IMAGE_REPO="wrong", PID_PUSH="0")
        self.run_build("ox")
        resolve, build, _, _, latest = self.calls()
        self.assertIn("custom-opencode@next", resolve)
        self.assertIn("OPENCODE_PKG=custom-opencode", build)
        self.assertEqual(latest, ["push", "registry.example/team/ox:latest"])

    def test_failed_resolve_build_or_verification_never_pushes(self):
        for operation in ("resolve", "build", "verify"):
            with self.subTest(operation=operation):
                Path(self.env["CALLS"]).unlink(missing_ok=True)
                self.env["FAIL_OPERATION"] = operation
                self.run_build("ox", "--push", code=37)
                self.assertFalse(any(call[0] == "push" for call in self.calls()))

    def test_stale_upstream_executable_is_not_published(self):
        self.env["ACTUAL_VERSION"] = "1.0.0"
        result = self.run_build("ox", "--push", code=1)
        self.assertIn("version mismatch", result.stderr)
        self.assertFalse(any(call[0] == "push" for call in self.calls()))

    def test_existing_agent_builds_keep_their_packages_and_tags(self):
        for target, package, image in (("opencode", "opencode-ai", "ocd"),
                                       ("pi", "@earendil-works/pi-coding-agent", "pid")):
            with self.subTest(target=target):
                Path(self.env["CALLS"]).unlink(missing_ok=True)
                self.run_build(target, "--push")
                resolve, _, version, latest = self.calls()
                self.assertIn(f"{package}@latest", resolve)
                self.assertEqual(version, ["push", f"docker.io/lnksz/{image}:1.2.3"])
                self.assertEqual(latest, ["push", f"docker.io/lnksz/{image}:latest"])


if __name__ == "__main__":
    unittest.main()
