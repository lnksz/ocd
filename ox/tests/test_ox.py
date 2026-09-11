"""Exercise the real Fish wrapper with a recording sbx, without KVM or login."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
FISH = shutil.which("fish")

SBX = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
with open(os.environ["CALLS"], "a") as log:
    log.write(json.dumps(args) + "\n")
if args[0] == os.environ.get("FAIL_COMMAND"):
    sys.exit(23)
state = Path(os.environ["STATE"])
if args[0] == "ls" and state.exists():
    print(state.read_text())
elif args[0] == "create":
    for mount in args[args.index("opencode") + 1:]:
        path = Path(mount.removesuffix(":ro"))
        if not path.is_dir():
            print(f"ERROR: workspace path exists but is not a directory: {path}", file=sys.stderr)
            sys.exit(1)
    state.write_text(args[args.index("--name") + 1])
elif args[0] == "rm":
    state.unlink(missing_ok=True)
'''


@unittest.skipUnless(FISH, "Fish is required")
class WrapperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ox test ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.workspace = self.base / "project [a]"
        self.workspace.mkdir()
        self.home = self.base / "host home"
        self.home.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        for name, body in {"sbx": SBX, "nproc": "#!/bin/sh\nprintf '10\\n'\n"}.items():
            path = self.bin / name
            path.write_text(body)
            path.chmod(0o755)
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith(("OX_", "XDG_", "OCD_", "PID_", "GIT_"))
            and key not in ("TERMINFO", "BASH_ENV")
        }
        self.env.update(
            HOME=str(self.home),
            PATH=f"{self.bin}:{os.environ['PATH']}",
            XDG_CONFIG_HOME=str(self.home / "config"),
            XDG_CACHE_HOME=str(self.home / "cache"),
            XDG_DATA_HOME=str(self.home / "data"),
            CALLS=str(self.base / "calls.jsonl"),
            STATE=str(self.base / "state"),
        )
        self.cfg = self.home / "config" / "opencode"
        self.cfg.mkdir(parents=True)

    def run_ox(self, *args, code=0):
        result = subprocess.run(
            [FISH, "--no-config", "-c", 'source "$argv[1]"; ox $argv[2..-1]',
             str(ROOT / "ox" / "ox.fish"), *args],
            cwd=self.workspace, env=self.env, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def calls(self):
        path = Path(self.env["CALLS"])
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_create_and_reuse_preserve_arguments(self):
        args = ("run", "text with spaces", '$(touch NEVER)', "--model", "provider/model", "")
        self.run_ox(*args)
        listing, create, execute = self.calls()
        self.assertEqual(listing, ["ls", "-q"])
        self.assertEqual(create[create.index("--cpus") + 1], "6")
        self.assertEqual(create[create.index("--template") + 1], "docker.io/lnksz/ox:latest")
        self.assertEqual(execute[-len(args):], list(args))
        self.assertEqual(execute[execute.index("bash") + 1], "-c")
        self.assertIn("opencode", execute)
        self.assertFalse((self.workspace / "NEVER").exists())
        self.run_ox("--continue")
        self.assertEqual([c[0] for c in self.calls()], ["ls", "create", "exec", "ls", "exec"])

    def test_config_auth_links_and_terminal_are_narrowly_shared(self):
        gh = self.home / "config" / "gh"
        gh.mkdir()
        skills = self.base / "shared skills"
        skills.mkdir()
        (self.cfg / "skills").symlink_to(skills)
        config_source = self.base / "dotconf" / "opencode"
        config_source.mkdir(parents=True)
        instructions = config_source / "AGENTS.md"
        instructions.write_text("Instructions\n")
        (self.cfg / "AGENTS.md").symlink_to(instructions)
        config = config_source / "opencode.json"
        config.write_text("{}\n")
        (self.cfg / "opencode.json").symlink_to(config)
        env_file = self.cfg / "config.env"
        env_file.write_text("API_KEY=test-only\n")
        terminfo = self.base / "terminfo"
        terminfo.mkdir()
        self.env.update(TERM="xterm-test", TERM_PROGRAM="test-terminal", TERMINFO=str(terminfo))
        self.run_ox()
        _, create, execute = self.calls()
        mounts = create[create.index("opencode") + 1:]
        self.assertEqual(mounts[0], str(self.workspace))
        for mount in (str(self.cfg), str(gh), str(skills), f"{config_source}:ro", f"{terminfo}:ro"):
            self.assertIn(mount, mounts)
        self.assertNotIn(f"{instructions}:ro", mounts)
        self.assertEqual(mounts.count(f"{config_source}:ro"), 1)
        self.assertNotIn(f"{config_source.parent}:ro", mounts)
        self.assertNotIn(str(self.home), mounts)
        self.assertNotIn(str(self.home / "config"), mounts)
        self.assertIn("TERM=xterm-test", execute)
        self.assertIn(str(env_file), execute)
        self.assertIn("config/gh", execute)
        self.assertNotIn("API_KEY=test-only", execute)

    def test_config_file_in_existing_share_keeps_that_share_writable(self):
        instructions = self.workspace / "AGENTS.md"
        instructions.write_text("Instructions\n")
        (self.cfg / "AGENTS.md").symlink_to(instructions)
        config = self.cfg / "shared.json"
        config.write_text("{}\n")
        (self.cfg / "opencode.json").symlink_to(config)
        self.run_ox()
        create = self.calls()[1]
        mounts = create[create.index("opencode") + 1:]
        self.assertIn(str(self.workspace), mounts)
        self.assertIn(str(self.cfg), mounts)
        self.assertFalse(any(mount.endswith(":ro") for mount in mounts))

    def test_config_file_in_symlinked_skills_reuses_directory_share(self):
        skills = self.base / "shared skills"
        skills.mkdir()
        (self.cfg / "skills").symlink_to(skills)
        instructions = skills / "instructions.md"
        instructions.write_text("Instructions\n")
        (self.cfg / "AGENTS.md").symlink_to(instructions)
        self.run_ox()
        create = self.calls()[1]
        self.assertIn(str(skills), create)
        self.assertNotIn(f"{skills}:ro", create)

    def test_worktree_shares_git_metadata_without_main_checkout(self):
        main = self.base / "main checkout"
        main.mkdir()
        for args in (["init", str(main)], ["-C", str(main), "-c", "user.name=Test",
                     "-c", "user.email=test@example.test", "commit", "--allow-empty", "-m", "Initial"],
                     ["-C", str(main), "worktree", "add", "-b", "test", str(self.workspace)]):
            subprocess.run(["git", *args], env=self.env, check=True, capture_output=True)
        self.run_ox()
        create = self.calls()[1]
        self.assertIn(str(main / ".git"), create)
        self.assertNotIn(str(main), create)

    def test_shell_and_separator(self):
        self.run_ox("-s", "-c", "printf test")
        self.assertEqual(self.calls()[-1][-4:], ["--", "shell", "-c", "printf test"])
        self.run_ox("--", "-s", "session-id")
        self.assertEqual(self.calls()[-1][-4:], ["--", "opencode", "-s", "session-id"])

    def test_resource_and_image_overrides_are_independent(self):
        self.env.update(OX_CPUS="3", OX_MEMORY="8g", OX_IMAGE="registry.example/ox:v1",
                        OCD_CPUS="99", PID_MEMORY="1m", OX_CPU_PERCENT="invalid")
        self.run_ox()
        create = self.calls()[1]
        for flag, expected in (("--cpus", "3"), ("--memory", "8g"),
                               ("--template", "registry.example/ox:v1")):
            self.assertEqual(create[create.index(flag) + 1], expected)

    def test_invalid_resources_do_not_create(self):
        for variable, value in (("OX_CPUS", "1.5"), ("OX_CPU_PERCENT", "101"),
                                ("OX_MEMORY_PERCENT", "0")):
            with self.subTest(variable=variable):
                self.env[variable] = value
                self.run_ox(code=1)
                del self.env[variable]
        self.assertTrue(all(c[0] == "ls" for c in self.calls()))

    def test_failures_propagate_without_running_later_steps(self):
        for command in ("ls", "create", "exec"):
            with self.subTest(command=command):
                Path(self.env["CALLS"]).unlink(missing_ok=True)
                self.env["FAIL_COMMAND"] = command
                self.run_ox(code=23)
                self.assertEqual(self.calls()[-1][0], command)

    def test_lifecycle_and_names(self):
        expected = "ox-" + hashlib.sha256(str(self.workspace).encode()).hexdigest()[:16]
        self.assertEqual(self.run_ox("--sandbox-name").stdout.strip(), expected)
        self.assertEqual(self.calls(), [])
        self.run_ox()
        self.run_ox("--stop")
        self.run_ox("--rm")
        self.assertEqual(self.calls()[-2:], [["stop", expected], ["rm", expected]])
        self.run_ox("--rm", "unexpected", code=2)

    def test_broken_config_symlink_fails_before_sbx(self):
        (self.cfg / "AGENTS.md").symlink_to(self.base / "missing")
        self.run_ox(code=1)
        self.assertEqual(self.calls(), [])


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ox session ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "agent"
        self.workspace = self.base / "project"
        self.bin = self.base / "bin"
        for path in (self.home, self.workspace, self.bin):
            path.mkdir()
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith(("XDG_", "OX_", "GIT_", "OPENCODE_")) and key != "BASH_ENV"
        }
        self.env.update(HOME=str(self.home), PATH=f"{self.bin}:{os.environ['PATH']}",
                        SESSION_LOG=str(self.base / "session.jsonl"))
        for kind in ("CONFIG", "CACHE", "DATA"):
            path = self.base / kind.lower()
            path.mkdir()
            self.env[f"OX_HOST_{kind}"] = str(path)
        for command in ("fish", "opencode"):
            path = self.bin / command
            path.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with open(os.environ["SESSION_LOG"], "a") as log:
    log.write(json.dumps({"command": Path(sys.argv[0]).name, "args": sys.argv[1:],
        "config": os.environ["XDG_CONFIG_HOME"],
        "tui": os.environ.get("OPENCODE_TUI_CONFIG"), "cwd": os.getcwd()}) + "\\n")
sys.exit(11 if Path(sys.argv[0]).name == "opencode" else 7)
''')
            path.chmod(0o755)

    def run_session(self, *args, code=7):
        result = subprocess.run(["bash", str(ROOT / "ox" / "session.sh"), *args],
                                env=self.env, cwd=self.workspace, capture_output=True, text=True)
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def test_shared_config_preserved_and_agent_exits_into_fish(self):
        native_config = self.home / ".config" / "opencode"
        native_config.mkdir(parents=True)
        (native_config / "original.json").write_text("{}\n")
        host_tui = Path(self.env["OX_HOST_CONFIG"]) / "tui.json"
        host_tui.write_text('{"theme":"test"}\n')
        self.run_session("--", "opencode", "run", "a spaced prompt", "")
        self.assertEqual(native_config.resolve(), Path(self.env["OX_HOST_CONFIG"]))
        self.assertTrue((native_config.with_name("opencode.ox-original") / "original.json").exists())
        self.assertEqual(host_tui.read_text(), '{"theme":"test"}\n')
        calls = [json.loads(line) for line in Path(self.env["SESSION_LOG"]).read_text().splitlines()]
        self.assertEqual([c["command"] for c in calls], ["opencode", "fish"])
        self.assertEqual(calls[0]["args"], ["run", "a spaced prompt", ""])
        self.assertEqual(calls[0]["tui"], "/usr/local/share/ox/tui.json")
        self.assertEqual(calls[1]["cwd"], str(self.workspace))
        # Re-entry must retain the original backup and avoid nested symlinks.
        self.run_session("--", "shell", "-c", "true")
        self.assertEqual(native_config.resolve(), Path(self.env["OX_HOST_CONFIG"]))

    def test_missing_mount_stops_before_agent(self):
        self.env["OX_HOST_DATA"] = str(self.base / "not mounted")
        result = self.run_session("--", "opencode", code=1)
        self.assertIn("recreate", result.stderr)
        self.assertFalse(Path(self.env["SESSION_LOG"]).exists())

    def test_shell_mode_links_optional_auth_without_tui_override(self):
        auth = self.base / "auth"
        auth.mkdir()
        self.run_session("config/gh", str(auth), "--", "shell", "-c", "a command")
        self.assertEqual((self.home / ".config" / "gh").resolve(), auth)
        calls = [json.loads(line) for line in Path(self.env["SESSION_LOG"]).read_text().splitlines()]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["command"], "fish")
        self.assertEqual(calls[0]["args"], ["-c", "a command"])
        self.assertIsNone(calls[0]["tui"])


if __name__ == "__main__":
    unittest.main()
