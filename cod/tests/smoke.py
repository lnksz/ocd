#!/usr/bin/env python3
"""Build-independent image smoke test; uses isolated fixtures and no credentials."""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

CHECK = r'''
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess

assert os.getuid() == int(os.environ["HOST_UID"])
assert os.getgid() == int(os.environ["HOST_GID"])
assert pwd.getpwuid(os.getuid()).pw_dir == os.environ["HOME"]
assert subprocess.check_output(["sudo", "-n", "id", "-u"], text=True).strip() == "0"
assert shutil.which("bwrap")
assert shutil.which("gh")
home = Path(os.environ["HOME"])
state = Path(os.environ["CODEX_HOME"])
assert (state / "AGENTS.override.md").read_text() == "OpenCode is the leading configuration.\n"
assert (state / "config.toml").read_text() == 'model_reasoning_effort = "medium"\n'
(state / "smoke-state").write_text("persistent")
assert (home / ".agents/skills/example/SKILL.md").is_file()
assert (home / ".agents/skills/opencode-commands-review/SKILL.md").is_file()
subprocess.run(["codex", "--version"], check=True)
subprocess.run(["codex", "features", "list"], check=True, stdout=subprocess.DEVNULL)
assert subprocess.check_output(["git", "config", "--global", "--get-all", "safe.directory"], text=True).strip() == "/workspace"

# Verify discovery with Codex itself, not just the generated files.
server = subprocess.Popen(["codex", "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def request(number, method, params):
    server.stdin.write(json.dumps({"id": number, "method": method, "params": params}) + "\n")
    server.stdin.flush()
    for line in server.stdout:
        message = json.loads(line)
        if message.get("id") == number:
            assert "error" not in message, message
            return message["result"]
    raise AssertionError("Codex app-server exited without responding")
try:
    request(1, "initialize", {"clientInfo": {"name": "cod-smoke", "version": "1.0"}})
    server.stdin.write('{"method":"initialized"}\n')
    server.stdin.flush()
    result = request(2, "skills/list", {"cwds": ["/workspace"], "forceReload": True})
    names = {skill["name"] for entry in result["data"] for skill in entry["skills"]}
    assert {"example", "external", "opencode-commands-review", "opencode-agents-review"} <= names, result
finally:
    server.terminate()
    server.wait(timeout=10)
print("Codex identity, sudo, persistence, config, Git, and skill discovery passed.")
'''


def main():
    image = sys.argv[1] if len(sys.argv) > 1 else "cod:dev"
    with tempfile.TemporaryDirectory(prefix="cod-smoke-") as temporary:
        root = Path(temporary)
        root.chmod(0o755)
        source = root / "opencode"
        state = root / "state"
        workspace = root / "workspace"
        state.mkdir(mode=0o777)
        workspace.mkdir(mode=0o777)
        # Also exercise an arbitrary host identity when CI itself runs as root.
        uid = os.getuid() or 12345
        gid = os.getgid() or 12345
        if os.getuid() == 0:
            os.chown(state, uid, gid)
            os.chown(workspace, uid, gid)
        for name, content in {
            "AGENTS.md": "OpenCode is the leading configuration.\n",
            "skills/example/SKILL.md": "---\nname: example\ndescription: Smoke test skill\n---\nExample.\n",
            "commands/review.md": "---\ndescription: Review code\n---\nReview $ARGUMENTS.\n",
            "agents/review.md": "Review code carefully.\n",
        }.items():
            path = source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        (state / "config.toml").write_text('model_reasoning_effort = "medium"\n')
        (state / "AGENTS.override.md").write_text("native override stays intact\n")
        external = root / "external"
        external.mkdir()
        (external / "SKILL.md").write_text("---\nname: external\ndescription: Symlinked skill\n---\nExample.\n")
        (source / "skills/external").symlink_to(external, target_is_directory=True)
        subprocess.run(["git", "init", "-q", str(workspace)], check=True)
        if os.getuid() == 0:
            for path in workspace.rglob("*"):
                os.chown(path, uid, gid)
        command = ["docker", "run", "--rm", "-i", "--init", "--user", "0:0",
                   "-e", f"HOST_UID={uid}", "-e", f"HOST_GID={gid}",
                   "-e", "HOST_USER=cod-smoke", "-e", "HOME=/tmp/home",
                   "-e", "CODEX_HOME=/var/lib/codex", "-w", "/workspace",
                   "-v", f"{workspace}:/workspace", "-v", f"{state}:/var/lib/codex",
                   "-v", f"{source}:/tmp/cod-opencode:ro",
                   "-v", f"{external}:/tmp/cod-opencode/skills/external:ro",
                   "-v", f"{source}/AGENTS.md:/var/lib/codex/AGENTS.override.md:ro",
                   image, "python3", "-"]
        subprocess.run(command, input=CHECK, text=True, check=True, timeout=120)
        assert (state / "smoke-state").stat().st_uid == uid
        assert (state / "AGENTS.override.md").read_text() == "native override stays intact\n"
        # Codex may install its own bundled system skills in persistent state.
        assert not list((state / "skills").glob("opencode-*"))


if __name__ == "__main__":
    main()
