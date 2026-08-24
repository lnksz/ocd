# Agent Notes

This repository provides separate Docker wrappers for coding agents:

- `opencode/`: `Dockerfile`, `entrypoint.sh`, `ocd.fish`, `build-image.sh`, and `update-tools.sh`
- `pi/`: `Dockerfile`, `entrypoint.sh`, and `pid.fish`

Build from the repository root because each Dockerfile copies files from its own agent directory:

```bash
docker build -f opencode/Dockerfile -t ocd:dev .
docker build -f pi/Dockerfile -t pid:dev .
```

## Commands

```bash
hadolint opencode/Dockerfile
hadolint pi/Dockerfile
shellcheck opencode/entrypoint.sh opencode/build-image.sh opencode/update-tools.sh pi/entrypoint.sh
fish -n opencode/ocd.fish pi/pid.fish
```

Build/version the OpenCode image:

```bash
./opencode/build-image.sh latest
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
- `entrypoint.sh` uses `nss_wrapper` to support arbitrary `--user UID:GID`; preserve the HOME/XDG and Git `safe.directory` behavior.
- Do not log secrets or broaden mounted host paths without need.
