# Agent containers

Run coding agents inside Docker, Podman, or Docker Sandboxes against the current working directory.

Each agent is self-contained:

- `opencode/`: OpenCode image, entrypoint, wrapper, and update script
- `pi/`: Pi image, entrypoint, and wrapper
- `ox/`: OpenCode Docker Sandbox template, session setup, and Fish wrapper
- `build-image.sh`: shared versioned image builder

## OpenCode

```fish
source /path/to/opencode/ocd.fish
ocd
```

By default this uses `docker.io/lnksz/ocd:latest`. Override it with `OCD_IMAGE`, select an engine with `OCD_ENGINE`, or use `ocd --shell` to open `fish` instead of OpenCode.

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

Both wrappers default to 60% of host CPU and RAM. Their agent-specific overrides are `<AGENT>_CPU_PERCENT`, `<AGENT>_MEMORY_PERCENT`, `<AGENT>_CPUS`, and `<AGENT>_MEMORY` (`OCD_*` or `PID_*`).

`ocd` persists its XDG `opencode/` configuration, cache, and data. `pid` persists `~/.pi/agent`, mounts `~/.agents`, and reuses OpenCode skills plus its commands and agent prompts as Pi prompt templates when those directories exist. Both reuse GitHub CLI/Copilot auth when available and support linked Git worktrees.

Both wrappers create an ephemeral container account matching the host UID/GID
before starting the agent. The account has passwordless `sudo` so agents can
install additional tools without changing bind-mounted file ownership. Rootless
Podman uses a `keep-id` user namespace for the same ownership behavior.

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
Linux with KVM and `sbx` 0.42.1+ is required. Install all three Fish functions
with `bash ./install.sh`.

## Checks

```bash
hadolint opencode/Dockerfile
hadolint pi/Dockerfile
hadolint ox/Dockerfile
shellcheck build-image.sh opencode/entrypoint.sh opencode/update-tools.sh pi/entrypoint.sh ox/session.sh install.sh
fish -n opencode/ocd.fish pi/pid.fish ox/ox.fish
python3 -B -m unittest discover -s ox/tests -v
```
