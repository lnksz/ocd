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
import shutil
import subprocess
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
elif args[0] == "exec" and "ox-sync" in args:
    exports = Path(os.environ["REMOTE_EXPORTS"])
    command = args[args.index("bash"):]
    command[-1] = str(exports)
    sys.exit(subprocess.run(command).returncode)
elif args[0] == "exec" and "TEST_LAUNCHER" in os.environ:
    command = args[args.index("bash"):]
    command[2] = command[2].replace("/usr/local/bin/ox-session", '"' + os.environ["TEST_LAUNCHER"] + '"')
    sys.exit(subprocess.run(command).returncode)
elif args[0] == "exec" and "rm" in args:
    exports = Path(os.environ["REMOTE_EXPORTS"])
    (exports / Path(args[-1]).name).unlink(missing_ok=True)
elif args[0] == "cp":
    exports = Path(os.environ["REMOTE_EXPORTS"])
    shutil.copy2(exports / Path(args[-2]).name, args[-1])
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
        host_data = self.home / "data" / "opencode"
        host_data.mkdir(parents=True)
        (host_data / "auth.json").write_text('{"provider":"test"}\n')
        terminfo = self.base / "terminfo"
        terminfo.mkdir()
        self.env.update(TERM="xterm-test", TERM_PROGRAM="test-terminal", TERMINFO=str(terminfo))
        self.run_ox()
        _, create, execute = self.calls()
        mounts = create[create.index("opencode") + 1:]
        self.assertEqual(mounts[0], str(self.workspace))
        seed = self.home / "data" / "ox" / "opencode-seed"
        for mount in (str(self.cfg), f"{seed}:ro", str(gh), str(skills),
                      f"{config_source}:ro", f"{terminfo}:ro"):
            self.assertIn(mount, mounts)
        self.assertNotIn(f"{instructions}:ro", mounts)
        self.assertEqual(mounts.count(f"{config_source}:ro"), 1)
        self.assertNotIn(f"{config_source.parent}:ro", mounts)
        self.assertNotIn(str(self.home), mounts)
        self.assertNotIn(str(self.home / "config"), mounts)
        self.assertNotIn(str(host_data), mounts)
        self.assertNotIn(str(self.home / "cache" / "opencode"), mounts)
        self.assertEqual((seed / "auth.json").read_text(), '{"provider":"test"}\n')
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
        self.assertNotIn(f"{self.workspace}:ro", mounts)
        self.assertNotIn(f"{self.cfg}:ro", mounts)

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

    def test_cached_legacy_launcher_reports_template_refresh(self):
        launcher = self.base / "old launcher"
        launcher.write_text('#!/bin/bash\n: "${OX_HOST_CONFIG:?}"\nexit 99\n')
        launcher.chmod(0o755)
        self.env.update(TEST_LAUNCHER=str(launcher), OX_HOST_CONFIG=str(self.cfg),
                        OX_IMAGE="registry.example/ox:old")
        for _ in range(2):
            result = self.run_ox(code=1)
            self.assertIn("outdated session launcher", result.stderr)
            self.assertIn("sbx template rm registry.example/ox:old", result.stderr)
            self.assertNotIn("/__ox_private_runtime", result.stderr)
            self.run_ox("--rm")

    def test_current_launcher_handshake_preserves_arguments(self):
        launcher = self.base / "current launcher"
        launcher.write_text('''#!/bin/bash
if [ "$1" = --runtime-version ]; then printf '2\\n'; exit; fi
printf '<%s>\\n' "$@"
''')
        launcher.chmod(0o755)
        self.env["TEST_LAUNCHER"] = str(launcher)
        result = self.run_ox("run", "a spaced prompt", "")
        self.assertEqual(result.stdout, "<-->\n<opencode>\n<run>\n<a spaced prompt>\n<>\n")

    def setup_sync(self):
        self.run_ox()
        exports = self.base / "sandbox exports"
        exports.mkdir()
        opencode = self.bin / "opencode"
        opencode.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with open(os.environ["IMPORT_LOG"], "a") as log:
    log.write(json.dumps({"args": sys.argv[1:], "data": Path(sys.argv[2]).read_text()}) + "\\n")
sys.exit(int(os.environ.get("IMPORT_STATUS", "0")))
''')
        opencode.chmod(0o755)
        self.env.update(REMOTE_EXPORTS=str(exports), IMPORT_LOG=str(self.base / "imports.jsonl"))
        return exports

    def test_sync_imports_and_removes_queued_snapshots(self):
        exports = self.setup_sync()
        session_id = "ses_test123"
        snapshot = exports / f"{session_id}.{'a' * 64}.json"
        snapshot.write_text(json.dumps({"info": {"id": session_id}, "messages": []}))
        self.run_ox("--sync-sessions")
        imported = json.loads(Path(self.env["IMPORT_LOG"]).read_text())
        self.assertEqual(imported["args"][0], "import")
        self.assertEqual(json.loads(imported["data"])["info"]["id"], session_id)
        self.assertFalse(snapshot.exists())
        self.assertEqual([call[0] for call in self.calls()][-4:],
                         ["ls", "exec", "cp", "exec"])

    def test_sync_empty_or_absent_queue_succeeds(self):
        exports = self.setup_sync()
        for _ in range(2):
            result = self.run_ox("--sync-sessions")
            self.assertIn("no completed session snapshots", result.stdout)
            self.assertFalse(Path(self.env["IMPORT_LOG"]).exists())
            if exports.exists():
                exports.rmdir()

    def test_sync_preserves_queue_on_copy_or_import_failure(self):
        exports = self.setup_sync()
        snapshot = exports / "ses_retry.json"
        snapshot.write_text('{}\n')
        for variable, value in (("FAIL_COMMAND", "cp"), ("IMPORT_STATUS", "1")):
            with self.subTest(variable=variable):
                self.env[variable] = value
                self.run_ox("--sync-sessions", code=1)
                self.assertTrue(snapshot.exists())
                del self.env[variable]

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
                        SESSION_LOG=str(self.base / "session.jsonl"),
                        SESSION_LIST_COUNT=str(self.base / "session-list-count"))
        config = self.base / "config"
        config.mkdir()
        seed = self.base / "seed"
        seed.mkdir()
        self.env["OX_HOST_CONFIG"] = str(config)
        self.env["OX_HOST_DATA_SEED"] = str(seed)
        for command in ("fish", "opencode"):
            path = self.bin / command
            path.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
if name == "opencode" and sys.argv[1:3] == ["session", "list"]:
    counter = Path(os.environ["SESSION_LIST_COUNT"])
    count = int(counter.read_text()) if counter.exists() else 0
    counter.write_text(str(count + 1))
    if count == 0 and os.environ.get("EMPTY_BASELINE"):
        sys.exit(0)
    before = [{"id": "ses_changed", "updated": 1}, {"id": "ses_unchanged", "updated": 1}]
    after = [{"id": "ses_test123", "updated": 2}, {"id": "ses_changed", "updated": 3},
             {"id": "ses_unchanged", "updated": 1}]
    print(json.dumps(before if count == 0 else after))
    sys.exit(0)
if name == "opencode" and sys.argv[1:2] == ["export"]:
    print(json.dumps({"info": {"id": sys.argv[2]}, "messages": []}))
    sys.exit(0)
with open(os.environ["SESSION_LOG"], "a") as log:
    log.write(json.dumps({"command": name, "args": sys.argv[1:],
        "config": os.environ["XDG_CONFIG_HOME"],
        "tui": os.environ.get("OPENCODE_TUI_CONFIG"), "cwd": os.getcwd()}) + "\\n")
sys.exit(11 if name == "opencode" else 7)
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
        seed_auth = Path(self.env["OX_HOST_DATA_SEED"]) / "auth.json"
        seed_auth.write_text('{"provider":"test"}\n')
        self.run_session("--", "opencode", "run", "a spaced prompt", "")
        self.assertEqual(native_config.resolve(), Path(self.env["OX_HOST_CONFIG"]))
        self.assertTrue((native_config.with_name("opencode.ox-original") / "original.json").exists())
        self.assertEqual(host_tui.read_text(), '{"theme":"test"}\n')
        private_cache = self.home / ".cache" / "opencode"
        private_data = self.home / ".local" / "share" / "opencode"
        self.assertTrue(private_cache.is_dir())
        self.assertFalse(private_cache.is_symlink())
        self.assertTrue(private_data.is_dir())
        self.assertFalse(private_data.is_symlink())
        self.assertEqual((private_data / "auth.json").read_text(), '{"provider":"test"}\n')
        self.assertNotEqual(private_data.resolve(), seed_auth.parent)
        queued = private_data.parent / "ox" / "session-exports"
        self.assertEqual({path.name.split(".")[0] for path in queued.glob("*.json")},
                          {"ses_test123", "ses_changed"})
        snapshot = next(queued.glob("ses_test123.*.json"))
        self.assertEqual(snapshot.name, f"ses_test123.{hashlib.sha256(snapshot.read_bytes()).hexdigest()}.json")
        self.assertEqual(json.loads(snapshot.read_text())["info"]["id"],
                          "ses_test123")
        calls = [json.loads(line) for line in Path(self.env["SESSION_LOG"]).read_text().splitlines()]
        self.assertEqual([c["command"] for c in calls], ["opencode", "fish"])
        self.assertEqual(calls[0]["args"], ["run", "a spaced prompt", ""])
        self.assertEqual(calls[0]["tui"], "/usr/local/share/ox/tui.json")
        self.assertEqual(calls[1]["cwd"], str(self.workspace))
        # Re-entry must retain the original backup and avoid nested symlinks.
        self.run_session("--", "shell", "-c", "true")
        self.assertEqual(native_config.resolve(), Path(self.env["OX_HOST_CONFIG"]))

    def test_runtime_version_requires_no_mounts_or_setup(self):
        del self.env["OX_HOST_CONFIG"]
        del self.env["OX_HOST_DATA_SEED"]
        self.assertEqual(self.run_session("--runtime-version", code=0).stdout, "2\n")
        self.assertEqual(list(self.home.iterdir()), [])

    def test_first_session_is_exported_from_empty_baseline(self):
        self.env["EMPTY_BASELINE"] = "1"
        self.run_session("--", "opencode")
        exports = self.home / ".local/share/ox/session-exports"
        self.assertEqual({path.name.split(".")[0] for path in exports.glob("*.json")},
                         {"ses_test123", "ses_changed", "ses_unchanged"})

    def test_missing_mount_stops_before_agent(self):
        self.env["OX_HOST_DATA_SEED"] = str(self.base / "not mounted")
        result = self.run_session("--", "opencode", code=1)
        self.assertIn("recreate", result.stderr)
        self.assertFalse(Path(self.env["SESSION_LOG"]).exists())

    def test_legacy_shared_data_stops_before_agent(self):
        shared_data = self.base / "shared data"
        shared_data.mkdir()
        data_home = self.home / ".local" / "share"
        data_home.mkdir(parents=True)
        (data_home / "opencode").symlink_to(shared_data)
        result = self.run_session("--", "opencode", code=1)
        self.assertIn("refusing legacy shared OpenCode runtime", result.stderr)
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
