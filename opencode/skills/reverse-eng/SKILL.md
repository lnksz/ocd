---
name: reverse-eng
description: Investigate native binaries and shipped applications with REA, Ghidra, and LaurieWired GhidraMCP v2. Install and configure missing tools on demand only inside a verified container; never install or run setup on the host.
---

# Reverse engineering in a container

The default images carry these instructions and the installer, without the
reverse-engineering tools. Install only when the requested investigation needs
them. Reuse existing working tools before acquiring anything.

## Container boundary

Before any installation or setup, run the bundled read-only check using this
skill's actual directory (resolve symlinks if necessary):

```bash
bash /usr/local/share/agent-skills/reverse-eng/scripts/install.sh --check
```

If the check fails, do not run installers, sudo, package managers, `npx`,
`uvx`, `rea setup`, or edit MCP configuration. Do not bypass the check or invent
container evidence. Existing tools may still be used for the requested analysis.
If tools are missing, explain that installation requires a container and use the
project's existing container workflow before repeating the check inside it.
This restriction also applies to installation advice in upstream REA skills.

The check accepts Docker/Podman marker files or positive systemd container
detection identifying Docker, Podman, LXC, nspawn, or rkt. Generic
`container-other`, tool sandboxes, WSL, a VM, hostname, UID, environment variable,
or access to a Docker
socket alone is insufficient. Uncertain environments must refuse installation.

## Install on demand

After confirming a container, check `command -v rea ghidra-mcp` and any existing
Ghidra installation. If usable, run `rea doctor --provider ghidra --json` and reuse
it. Otherwise run the bundled installer inside this container:

```bash
bash /usr/local/share/agent-skills/reverse-eng/scripts/install.sh --install
```

When this skill lives elsewhere, use its actual `scripts/install.sh` path. The
script repeats the container check before invoking passwordless sudo, downloads
pinned releases with SHA-256 checks, installs Java 21, Ghidra 12.1.4, REA 6.4.0,
and LaurieWired/GhidraMCP 2.0, and creates an isolated Python 3.13.15 environment
using the upstream frozen dependency lockfile. It supports these Ubuntu/Debian
images on amd64/arm64; npm, uv, Python, and the C/C++ toolchain are already supplied.
Do not install or upgrade unrelated tools to work around an unsupported image.

Installed tools live under `/opt` and `/usr/local`, with JDK packages in system
paths. Verify that these are container-local before installing; do not target
host bind mounts, the workspace, user home, or persistent client configuration.
The installer refuses conflicting existing paths rather than overwriting them;
inspect and reuse an existing installation or use a fresh container. Re-running
it after a successful installation reuses that installation. Downloads are
removed. Tools disappear when a disposable container is removed; do not commit
or publish its tool-filled filesystem unless requested.

## Verify and investigate

```bash
rea --version
rea doctor --provider ghidra --json
ghidra-mcp --help
```

Read the installed, version-matched REA workflow at
`/usr/local/share/agent-skills/reverse-engineer-anything/SKILL.md`, then only its
references relevant to the target. Installation supplies CLI/MCP executables;
it does not register servers in the current agent session.

For native CLI analysis, select Ghidra explicitly. The launch wrappers supply
the bundled Ghidra and Java paths even if a client filters environment variables:

```bash
rea analyze /absolute/path/to/target --provider ghidra --json
rea function /absolute/path/to/target main --provider ghidra --json
```

REA manages its own temporary, read-only analysis projects. Use binary addresses
from the analysis results when decompiling; PIE symbol offsets may differ from
Ghidra's relocated addresses. Keep evidence and limitations with conclusions.

## MCP setup inside the container

Use `rea mcp` as a local stdio server. For direct headless GhidraMCP, select the
actual binary and start:

```bash
ghidra-mcp --headless --binary /absolute/path/to/target --ready-timeout 300
```

Temporary GhidraMCP projects discard changes on exit. Add
`--project /workspace/ghidra-projects` to retain annotations and edits, or
`--discard` to avoid saving. Project files may intentionally live in the mounted
workspace; tool installation and agent configuration must stay container-local.
The GUI command `ghidra` requires a graphical display; headless mode needs none.
Stdio needs no exposed network ports.

If MCP integration is needed, use the client's per-session overrides or an
ephemeral configuration file outside mounted host configuration. Register the
installed commands directly instead of downloading them through npx/uvx:

```json
{
  "mcpServers": {
    "rea": {"command": "/usr/local/bin/rea", "args": ["mcp"]},
    "ghidra": {
      "command": "/usr/local/bin/ghidra-mcp",
      "args": ["--headless", "--binary", "/absolute/path/to/target", "--ready-timeout", "300"]
    }
  }
}
```

Adapt the schema to the current agent; OpenCode uses its `mcp` schema and Codex
uses `mcp_servers`. Restart/reload the client if required, then verify its actual
tool list and a query against the chosen target. Do not run `rea setup` against
host-mounted XDG configuration, `.pi`, `.agents`, or `CODEX_HOME`; inspect its
proposed destinations before any container-local setup. When an ephemeral MCP
override is unavailable, use the CLI instead of modifying host configuration.
