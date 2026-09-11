# Agent containers

Run coding agents inside Docker, Podman, or Docker Sandboxes against the current working directory.

Each agent is self-contained:

- `opencode/`: OpenCode image, entrypoint, wrapper, and update script
- `pi/`: Pi image, entrypoint, and wrapper
- `ox/`: OpenCode Docker Sandbox template, session setup, and Fish wrapper
- `cod/`: Codex image, entrypoint, wrapper, and OpenCode configuration adapter
- `build-image.sh`: shared versioned image builder

Install all four Fish commands with `./install.sh`, or source a wrapper directly.

## OpenCode

```fish
source /path/to/opencode/ocd.fish
ocd
```

By default this uses `docker.io/lnksz/ocd:latest`. Override it with `OCD_IMAGE`, select an engine with `OCD_ENGINE`, or use `ocd --shell` to open `fish` instead of OpenCode.

`ocd` starts OpenCode with `--auto`, automatically approving permissions that
are not explicitly denied by the OpenCode configuration.

Build from the repository root:

```bash
docker build -f opencode/Dockerfile -t ocd:dev opencode
./build-image.sh opencode latest
```

## Pi

```fish
source /path/to/pi/pid.fish
pid
```

By default this uses `docker.io/lnksz/pid:latest`. Override it with `PID_IMAGE`, select an engine with `PID_ENGINE`, or use `pid --shell` to open `fish` instead of Pi.

Build from the repository root:

```bash
docker build -f pi/Dockerfile -t pid:dev pi
./build-image.sh pi latest
```

The publish workflow builds and pushes `docker.io/lnksz/pid:<Pi version>` and
`docker.io/lnksz/pid:latest` on pushes to `master` and on its daily schedule.

## Codex

```fish
source /path/to/cod/cod.fish
cod
```

By default this uses `docker.io/lnksz/cod:latest`. Override it with `COD_IMAGE`,
select an engine with `COD_ENGINE`, or use `cod --shell` (also `cod -s`) to open
Fish. Arguments are passed to Codex, and exiting Codex leaves a Fish shell open,
just like the other wrappers.

Codex starts with `--yolo`, disabling its approval prompts and internal sandbox.
The same default applies when running `codex` from the container's shell.

```bash
docker build -f cod/Dockerfile -t cod:dev cod
./build-image.sh cod latest
# Or pin a Codex version and optionally publish it:
./build-image.sh cod --push 0.154.0
```

The builder resolves `@openai/codex` to an exact version and tags the image with
that version and `latest`. Overrides are `CODEX_VERSION`, `COD_IMAGE_REPO`,
`COD_ENGINE`, and `COD_PUSH`. The publish workflow builds and pushes
`docker.io/lnksz/cod:<Codex version>` and `docker.io/lnksz/cod:latest` on pushes
to `master`, daily, and on manual dispatch.

### OpenCode-led configuration

`cod` persists `~/.codex` (or host `CODEX_HOME`) for Codex authentication,
`config.toml`, sessions, and history. Inside the container it is always available
at `/var/lib/codex` (Codex requires its helper binaries outside `/tmp`).
OpenCode remains the source for shared instructions:

| Host source | Codex integration |
| --- | --- |
| `$XDG_CONFIG_HOME/opencode/AGENTS.md` | Read-only global `AGENTS.override.md`, taking precedence over native Codex global instructions |
| `$XDG_CONFIG_HOME/opencode/skills/` | User skills, including their scripts and resources |
| `$XDG_CONFIG_HOME/opencode/commands/**/*.md` | Explicit skills named `opencode-commands-<name>` |
| `$XDG_CONFIG_HOME/opencode/agents/**/*.md` | Explicit skills named `opencode-agents-<name>` |
| `~/.agents/skills/` | Shared user skills; OpenCode wins for matching directory names |
| `$XDG_CONFIG_HOME/opencode/config.env` | Environment values applied after Codex's `config.env`, so OpenCode wins |

`XDG_CONFIG_HOME` defaults to `~/.config`. Optional sources are used only when
present. Symlinked global instructions and native Codex configuration files are
resolved and mounted individually. Imported sources are read-only, and generated
skills live in the ephemeral container home, so each launch reflects current
OpenCode files without rewriting host configuration.

Use `/skills` or `$opencode-commands-review` to invoke an imported prompt.
Nested paths are flattened with hyphens; conflicting or long names get a stable
hash suffix. OpenCode-specific frontmatter is removed from command/agent prompts.
Their bodies are retained with guidance to interpret argument placeholders and
use equivalent Codex tools. These are reusable instructions, not native Codex
subagent definitions. Custom slash prompts are deprecated in Codex, so this
integration uses its supported skill format.

As with Pi, OpenCode's provider, plugin, MCP, and permission settings in
`opencode.json{,c}` are not translated. Set Codex-specific settings in
`~/.codex/config.toml`. Codex uses its own authentication; for a first login from
the container, run `cod --shell` then `codex login --device-auth`, or supply
environment values through `config.env`.

## Shared wrapper behavior

All wrappers default to 60% of host CPU and RAM. Their agent-specific overrides are `<AGENT>_CPU_PERCENT`, `<AGENT>_MEMORY_PERCENT`, `<AGENT>_CPUS`, and `<AGENT>_MEMORY` (`OCD_*`, `PID_*`, or `COD_*`).

`ocd` persists its XDG `opencode/` configuration, cache, and data. `pid` persists `~/.pi/agent`, mounts `~/.agents`, and reuses OpenCode skills plus its commands and agent prompts as Pi prompt templates when those directories exist. Both reuse GitHub CLI/Copilot auth when available and support linked Git worktrees.

All wrappers create an ephemeral container account matching the host UID/GID
before starting the agent. The account has passwordless `sudo` so agents can
install additional tools without changing bind-mounted file ownership. Rootless
Podman uses a `keep-id` user namespace for the same ownership behavior.
`cod` also reuses GitHub CLI configuration and supports linked Git worktrees.
The Codex launcher uses YOLO mode and does not enable the deprecated Landlock
sandbox setting.

## OpenCode in Docker Sandboxes (ox)

`ox` provides the `ocd` workflow in a persistent, per-project microVM using the
standalone Docker Sandboxes `sbx` CLI. It shares OpenCode configuration, seeds
login into private sandbox data, and can export session snapshots back to host
OpenCode without sharing SQLite files. It supports `ox -s` and opens Fish when
OpenCode exits. The custom template includes the development toolbox and a
private Docker Engine.

The publish workflow builds `docker.io/lnksz/ox:<OpenCode version>` and
`docker.io/lnksz/ox:latest` in a separate job, daily at 02:00 UTC and on pushes
to `master`. Build manually with `./build-image.sh ox --push`. Existing sandboxes
need a template refresh and recreation to adopt an update; see the ox guide.

See **[ox setup and feature comparison](ox/README.md)** for installation,
template build/import commands, `OX_*` overrides, and verification status.
Linux with KVM and `sbx` 0.42.1+ is required. Install all four Fish functions
with `bash ./install.sh`.

## Checks

```bash
hadolint opencode/Dockerfile
hadolint pi/Dockerfile
hadolint ox/Dockerfile
hadolint cod/Dockerfile
shellcheck build-image.sh install.sh opencode/entrypoint.sh opencode/update-tools.sh pi/entrypoint.sh ox/session.sh cod/entrypoint.sh cod/codex.sh
fish -n opencode/ocd.fish pi/pid.fish ox/ox.fish cod/cod.fish
python3 -B -m unittest discover -s ox/tests -v
python3 -B -m unittest discover -s cod/tests -v
docker build -f cod/Dockerfile -t cod:dev cod
python3 cod/tests/smoke.py cod:dev
```

GitHub Actions runs Dockerfile linting for all images, ShellCheck, Fish syntax
checks, Codex integration tests, and a Codex image build/smoke test. The smoke
test verifies host identity, sudo, persistent file ownership, global instructions,
Git setup, and actual skill discovery through Codex's app server without login.
