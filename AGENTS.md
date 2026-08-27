# Agent Notes

This repository provides separate Docker wrappers for coding agents:

- `opencode/`: `Dockerfile`, `entrypoint.sh`, `ocd.fish`, and `update-tools.sh`
- `pi/`: `Dockerfile`, `entrypoint.sh`, and `pid.fish`
- Root: shared `build-image.sh`

Build from the repository root with each agent directory as its build context:

```bash
docker build -f opencode/Dockerfile -t ocd:dev opencode
docker build -f pi/Dockerfile -t pid:dev pi
```

## Commands

```bash
hadolint opencode/Dockerfile
hadolint pi/Dockerfile
shellcheck build-image.sh opencode/entrypoint.sh opencode/update-tools.sh pi/entrypoint.sh
fish -n opencode/ocd.fish pi/pid.fish
```

Build/version the agent images:

```bash
./build-image.sh opencode latest
./build-image.sh pi latest
./opencode/update-tools.sh
```

Smoke-check the images:

```bash
docker run --rm ocd:dev bash -lc 'command -v opencode >/dev/null'
docker run --rm pid:dev bash -lc 'command -v pi >/dev/null'
```

## Rules

- Keep agent-specific files inside that agent's directory. Do not add root compatibility loaders or shared agent Dockerfiles.
- Keep images independent: OpenCode-only dependencies/config belong in `opencode/`; Pi-only dependencies/config belong in `pi/`.
- Keep Docker builds deterministic: pin tools where practical, clean package caches, and use `apt-get install -y --no-install-recommends`.
- Keep Fish wrappers small, quote paths, use `set -l` locals, and keep mounts narrowly scoped.
- `ocd` and `pid` each default resource limits to 60% of host CPU/RAM. Do not make one agent consume the other agent's environment variables.
- `entrypoint.sh` creates an ephemeral account for the host UID/GID and drops
  privileges before agent setup; preserve the HOME/XDG and Git
  `safe.directory` behavior.
- Do not log secrets or broaden mounted host paths without need.
