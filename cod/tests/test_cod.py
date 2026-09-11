"""Regression tests for OpenCode adaptation and the host-side container contract."""

import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("integrate_config", ROOT / "cod/integrate-config.py")
CONFIG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONFIG)


class TemporaryTree(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cod test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, name, content=""):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path


class IntegrationTests(TemporaryTree):
    def integrate(self):
        target = self.root / "result"
        CONFIG.integrate(self.root / "opencode", self.root / "shared", target)
        return target

    def test_missing_optional_sources(self):
        self.assertEqual(list(self.integrate().iterdir()), [])

    def test_opencode_skill_precedence_and_resources(self):
        self.write("shared/review/SKILL.md", "shared")
        self.write("shared/other/SKILL.md", "other")
        self.write("opencode/skills/review/SKILL.md", "leading")
        self.write("opencode/skills/review/scripts/helper.py", "resource")
        target = self.integrate()
        self.assertEqual((target / "review/SKILL.md").read_text(), "leading")
        self.assertEqual((target / "review/scripts/helper.py").read_text(), "resource")
        self.assertEqual((target / "other/SKILL.md").read_text(), "other")
        self.assertEqual((self.root / "shared/review/SKILL.md").read_text(), "shared")

    def test_prompts_become_explicit_skills_with_nested_names(self):
        original = "---\ndescription: Review changes\nmodel: provider/model\nmode: subagent\n---\nReview $ARGUMENTS with $1.\n"
        source = self.write("opencode/commands/team/review.md", original)
        self.write("opencode/agents/review.md", "Act as a reviewer.\n")
        target = self.integrate()
        skill = target / "opencode-commands-team-review"
        content = (skill / "SKILL.md").read_text()
        self.assertIn("Review $ARGUMENTS with $1.", content)
        self.assertNotIn("model: provider/model", content)
        self.assertIn(str(source), content)
        self.assertIn("allow_implicit_invocation: false", (skill / "agents/openai.yaml").read_text())
        self.assertTrue((target / "opencode-agents-review/SKILL.md").is_file())
        self.assertEqual(source.read_text(), original)

    def test_colliding_and_long_names_remain_distinct(self):
        self.write("opencode/commands/team/review.md", "nested")
        self.write("opencode/commands/team-review.md", "flat")
        self.write("opencode/commands/" + "a" * 100 + ".md", "long")
        target = self.integrate()
        skills = list(target.iterdir())
        self.assertEqual(len(skills), 3)
        self.assertTrue(all(len(path.name) <= 64 for path in skills))


class WrapperTests(TemporaryTree):
    def setUp(self):
        super().setUp()
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(("COD_", "CODEX_", "OCD_", "PID_", "XDG_"))}
        self.env.update(HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / "config"),
                        COD_ENGINE="capture", COD_CPUS="2", COD_MEMORY="1g", MOCK_STATUS="0")

    def run_wrapper(self, *args, success=True):
        script = '''
function capture
    printf '%s\\0' $argv
    return $MOCK_STATUS
end
function podman
    capture $argv
end
source "$argv[1]"
cod $argv[2..-1]
'''
        result = subprocess.run(["fish", "--no-config", "-c", script,
                                 str(ROOT / "cod/cod.fish"), *args],
                                env=self.env, cwd=self.root, capture_output=True, check=False)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result

    def test_launch_arguments_identity_and_limits(self):
        args = self.run_wrapper("--model", "a model", "prompt with spaces").stdout.decode().split("\0")[:-1]
        self.assertIn("--cpus=2", args)
        self.assertIn("--memory=1g", args)
        self.assertIn(f"HOST_UID={os.getuid()}", args)
        self.assertIn("CODEX_HOME=/var/lib/codex", args)
        self.assertIn("docker.io/lnksz/cod:latest", args)
        self.assertEqual(args[-3:], ["--model", "a model", "prompt with spaces"])
        self.assertIn('codex "$@"', args[args.index("-c") + 1])

    def test_podman_identity_and_container_exit_status(self):
        self.env.update(COD_ENGINE="podman", MOCK_STATUS="23")
        result = self.run_wrapper("-s", success=False)
        self.assertEqual(result.returncode, 23)
        self.assertIn(b"--userns=keep-id\0", result.stdout)

    def test_opencode_instructions_symlinks_and_environment_precedence(self):
        target = self.write("external/instructions.md", "OpenCode leads")
        self.write("home/config/opencode/config.env", "EXAMPLE=leading\n")
        (self.home / "config/opencode/AGENTS.md").symlink_to(target)
        native = self.write("external/native.md", "native")
        self.write("home/.codex/config.env", "EXAMPLE=native\n")
        (self.home / ".codex/AGENTS.override.md").symlink_to(native)
        args = self.run_wrapper("--shell", "-c", "true").stdout.decode().split("\0")[:-1]
        overrides = [arg for arg in args if ":/var/lib/codex/AGENTS.override.md:" in arg]
        self.assertEqual(overrides, [f"{target}:/var/lib/codex/AGENTS.override.md:ro"])
        env_files = [args[index + 1] for index, arg in enumerate(args) if arg == "--env-file"]
        self.assertEqual(env_files, [str(self.home / ".codex/config.env"),
                                     str(self.home / "config/opencode/config.env")])
        self.assertEqual(args[-3:], ["fish", "-c", "true"])

    def test_native_home_override_and_source_mounts(self):
        native = self.root / "custom codex"
        self.env["CODEX_HOME"] = str(native)
        self.write("home/config/opencode/skills/review/SKILL.md", "review")
        self.write("home/.agents/skills/shared/SKILL.md", "shared")
        args = self.run_wrapper("-s").stdout.decode().split("\0")[:-1]
        self.assertIn(f"{native}:/var/lib/codex", args)
        self.assertIn(f"{self.home}/config/opencode/skills:/tmp/cod-opencode/skills:ro", args)
        self.assertIn(f"{self.home}/.agents/skills:/tmp/cod-shared-skills:ro", args)
        self.assertEqual(args[-1], "fish")

    def test_default_limits_ignore_other_agents(self):
        del self.env["COD_CPUS"]
        del self.env["COD_MEMORY"]
        self.env.update(OCD_CPU_PERCENT="invalid", PID_MEMORY_PERCENT="invalid")
        args = self.run_wrapper("-s").stdout.decode().split("\0")[:-1]
        cpus = float(next(arg.split("=", 1)[1] for arg in args if arg.startswith("--cpus=")))
        host_cpus = int(subprocess.check_output(["nproc"]))
        self.assertAlmostEqual(cpus, host_cpus * 0.6, places=5)
        self.assertTrue(any(arg.startswith("--memory=") for arg in args))

    def test_symlinked_skill_mount_is_narrow_and_read_only(self):
        target = self.write("external/review/SKILL.md", "review").parent
        skills = self.home / "config/opencode/skills"
        skills.mkdir(parents=True)
        (skills / "review").symlink_to(target, target_is_directory=True)
        args = self.run_wrapper("-s").stdout.decode().split("\0")[:-1]
        self.assertIn(f"{target}:/tmp/cod-opencode/skills/review:ro", args)
        self.assertNotIn(f"{target.parent}:{target.parent}", args)

    def test_symlinked_auth_remains_writable_for_token_refresh(self):
        target = self.write("external/auth.json", "{}")
        native = self.home / ".codex"
        native.mkdir()
        (native / "auth.json").symlink_to(target)
        args = self.run_wrapper("-s").stdout.decode().split("\0")[:-1]
        self.assertIn(f"{target}:/var/lib/codex/auth.json:rw", args)

    def test_invalid_percent_stops_before_engine(self):
        del self.env["COD_CPUS"]
        for value in ("0", "101", "oops", "-2"):
            with self.subTest(value=value):
                self.env["COD_CPU_PERCENT"] = value
                result = self.run_wrapper(success=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")
                self.assertIn(b"COD_CPU_PERCENT", result.stderr)

    def test_linked_worktree_mounts_only_external_metadata(self):
        main = self.root / "main"
        worktree = self.root / "linked"
        subprocess.run(["git", "init", "-q", str(main)], check=True)
        subprocess.run(["git", "-C", str(main), "-c", "user.name=Test", "-c",
                        "user.email=test@example.com", "commit", "-qm", "Initial", "--allow-empty"], check=True)
        subprocess.run(["git", "-C", str(main), "worktree", "add", "-qb", "linked", str(worktree)], check=True)
        self.root = worktree
        args = self.run_wrapper("-s").stdout.decode().split("\0")[:-1]
        self.assertIn(f"{main}/.git:{main}/.git", args)
        self.assertNotIn(f"{main}:{main}", args)


class BuildTests(TemporaryTree):
    def test_codex_version_tags_and_push_routing(self):
        log = self.root / "engine.jsonl"
        engine = self.write("engine", """#!/usr/bin/env python3
import json, os, sys
with open(os.environ['ENGINE_LOG'], 'a') as output:
    output.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1] == 'run':
    print('0.154.0')
""")
        engine.chmod(0o755)
        env = dict(os.environ, COD_ENGINE=str(engine), ENGINE_LOG=str(log),
                   COD_IMAGE_REPO="example/cod", COD_PUSH="0")
        subprocess.run(["bash", str(ROOT / "build-image.sh"), "cod", "--push", "--no-cache", "latest"],
                       env=env, check=True, capture_output=True)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        self.assertEqual(calls[0][-2:], ["@openai/codex@latest", "version"])
        self.assertIn("CODEX_VERSION=0.154.0", calls[1])
        self.assertIn("--no-cache", calls[1])
        self.assertEqual(calls[1][-1], str(ROOT / "cod"))
        self.assertEqual(calls[2:], [["push", "example/cod:0.154.0"], ["push", "example/cod:latest"]])

    def test_installer_installs_all_three_commands(self):
        env = dict(os.environ, HOME=str(self.root), XDG_CONFIG_HOME=str(self.root / "config"))
        subprocess.run(["bash", str(ROOT / "install.sh")], env=env, check=True)
        for agent, command in (("opencode", "ocd"), ("pi", "pid"), ("cod", "cod")):
            self.assertEqual((self.root / f"config/fish/functions/{command}.fish").read_bytes(),
                             (ROOT / agent / f"{command}.fish").read_bytes())


if __name__ == "__main__":
    unittest.main()
