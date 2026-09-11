# Agent Notes

This repository provides separate Docker wrappers for coding agents:

- `opencode/`: `Dockerfile`, `entrypoint.sh`, `ocd.fish`, and `update-tools.sh`
- `pi/`: `Dockerfile`, `entrypoint.sh`, and `pid.fish`
- `ox/`: Docker Sandbox `Dockerfile`, `session.sh`, and `ox.fish` (standalone sbx)
- `cod/`: `Dockerfile`, `entrypoint.sh`, `cod.fish`, `codex.sh`, and `integrate-config.py`
- Root: shared `build-image.sh`

Build from the repository root with each agent directory as its build context:

```bash
docker build -f opencode/Dockerfile -t ocd:dev opencode
docker build -f pi/Dockerfile -t pid:dev pi
docker build -f ox/Dockerfile -t ox:dev ox
docker build -f cod/Dockerfile -t cod:dev cod
```

## Commands

```bash
hadolint opencode/Dockerfile
hadolint pi/Dockerfile
hadolint ox/Dockerfile
hadolint cod/Dockerfile
shellcheck build-image.sh install.sh opencode/entrypoint.sh opencode/update-tools.sh pi/entrypoint.sh ox/session.sh cod/entrypoint.sh cod/codex.sh
fish -n opencode/ocd.fish pi/pid.fish ox/ox.fish cod/cod.fish
python3 -B -m unittest discover -s ox/tests -v
python3 -B -m unittest discover -s cod/tests -v
```

Build/version the agent images:

```bash
./build-image.sh opencode latest
./build-image.sh pi latest
./build-image.sh ox latest
./build-image.sh cod latest
./opencode/update-tools.sh
```

Smoke-check the images:

```bash
docker run --rm ocd:dev bash -lc 'command -v opencode >/dev/null'
docker run --rm pid:dev bash -lc 'command -v pi >/dev/null'
python3 -B -m unittest discover -s ox/tests -v
python3 cod/tests/smoke.py cod:dev
```

## Rules

- `ox` extends Docker's OpenCode sandbox template and preserves its runtime
  entrypoint, labels and `agent` account. Its image must be imported with
  `sbx template load` or published before use; see `ox/README.md`.

- Keep agent-specific files inside that agent's directory. Do not add root compatibility loaders or shared agent Dockerfiles.
- Keep images independent: OpenCode-only dependencies/config belong in `opencode/`; Pi-only dependencies/config belong in `pi/`; sandbox-only dependencies/config belong in `ox/`; Codex-only dependencies/config belong in `cod/`.
- Keep Docker builds deterministic: pin tools where practical, clean package caches, and use `apt-get install -y --no-install-recommends`.
- Keep Fish wrappers small, quote paths, use `set -l` locals, and keep mounts narrowly scoped.
- `ocd`, `pid`, and `cod` each default resource limits to 60% of host CPU/RAM. Do not make one agent consume the other agent's resource environment variables.
- OpenCode leads shared instructions for `cod`: import its AGENTS.md, skills,
  commands, agent prompts, and config.env read-only. Keep Codex auth/native TOML
  in CODEX_HOME and generated skills in the ephemeral home.
- `entrypoint.sh` creates an ephemeral account for the host UID/GID and drops
  privileges before agent setup; preserve the HOME/XDG and Git
  `safe.directory` behavior.
- Do not log secrets or broaden mounted host paths without need.
