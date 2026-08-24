# Agent containers

Run coding agents inside Docker or Podman against the current working directory.

Each agent is self-contained:

- `opencode/`: OpenCode image, entrypoint, wrapper, and build/update scripts
- `pi/`: Pi image, entrypoint, and wrapper

## OpenCode

```fish
source /path/to/opencode/ocd.fish
ocd
```

By default this uses `docker.io/lnksz/ocd:latest`. Override it with `OCD_IMAGE`, select an engine with `OCD_ENGINE`, or use `ocd --shell` to open `fish` instead of OpenCode.

Build from the repository root (the root is the Docker build context):

```bash
docker build -f opencode/Dockerfile -t ocd:dev .
./opencode/build-image.sh latest
```

## Pi

```fish
source /path/to/pi/pid.fish
pid
```

By default this uses `docker.io/lnksz/pid:latest`. Override it with `PID_IMAGE`, select an engine with `PID_ENGINE`, or use `pid --shell` to open `fish` instead of Pi.

Build from the repository root:

```bash
docker build -f pi/Dockerfile -t pid:dev .
```

The publish workflow builds and pushes `docker.io/lnksz/pid:<Pi version>` and
`docker.io/lnksz/pid:latest` on pushes to `master` and on its daily schedule.

Both wrappers default to 60% of host CPU and RAM. Their agent-specific overrides are `<AGENT>_CPU_PERCENT`, `<AGENT>_MEMORY_PERCENT`, `<AGENT>_CPUS`, and `<AGENT>_MEMORY` (`OCD_*` or `PID_*`).

`ocd` persists its XDG `opencode/` configuration, cache, and data. `pid` persists `~/.pi/agent`, mounts `~/.agents`, and reuses OpenCode skills plus its commands and agent prompts as Pi prompt templates when those directories exist. Both reuse GitHub CLI/Copilot auth when available and support linked Git worktrees.

## Checks

```bash
hadolint opencode/Dockerfile
hadolint pi/Dockerfile
shellcheck opencode/entrypoint.sh opencode/build-image.sh opencode/update-tools.sh pi/entrypoint.sh
fish -n opencode/ocd.fish pi/pid.fish
```
