# ocd

Run OpenCode inside Docker against your current working directory.

This repo contains:
- `Dockerfile`: the dev image ("everything included" tooling)
- `entrypoint.sh`: sets up HOME/XDG + `nss_wrapper` for arbitrary `--user UID:GID`
- `ocd.fish`: Fish wrapper function to run the container
- `build-image.sh`: build + tag images to match the published `opencode` version

The image also bundles [`rtk`](https://github.com/rtk-ai/rtk) and seeds the OpenCode plugin at container startup, so shell tool calls can be transparently rewritten through RTK.

## Quick start (Fish)

1) Load the function:

```fish
source /path/to/ocd.fish
```

2) Run OpenCode in the current directory:

```fish
ocd
```

By default it uses the image `docker.io/lnksz/ocd:latest`.

By default the wrapper also limits the container to `60%` of host CPU capacity and `60%` of host RAM.

Override the image:

```fish
set -x OCD_IMAGE ocd:dev
ocd
```

Use Podman instead of Docker:

```fish
set -x OCD_ENGINE podman
ocd
```

## Resource limits

`ocd.fish` computes container limits from the host by default:

- CPU: `60%` of host CPU capacity via `--cpus`
- RAM: `60%` of host memory via `--memory`

Override the percentages:

```fish
set -x OCD_CPU_PERCENT 50
set -x OCD_MEMORY_PERCENT 80
ocd
```

Override with absolute engine values instead:

```fish
set -x OCD_CPUS 2.5
set -x OCD_MEMORY 8g
ocd
```

Precedence is:

- `OCD_CPUS` over `OCD_CPU_PERCENT`
- `OCD_MEMORY` over `OCD_MEMORY_PERCENT`
- otherwise the built-in `60%` defaults

For plain `ocd`, the wrapper injects a temporary TUI override that disables OpenCode's built-in `Ctrl+Z` suspend binding to avoid wedging the host tty. `ocd --shell` is left unchanged.

## Build

Local build:

```bash
docker build -t ocd:dev .
```

Podman build:

```bash
podman build -t ocd:dev .
```

Smoke-run:

```bash
docker run --rm -it ocd:dev fish
```

## Versioned tags (Docker Hub)

Build and tag to match the resolved OpenCode version:

```bash
./build-image.sh latest
./build-image.sh 0.7.3
```

With Podman (or explicit engine selection):

```bash
OCD_ENGINE=podman ./build-image.sh latest
```

This tags:
- `docker.io/lnksz/ocd:<resolved_version>`
- `docker.io/lnksz/ocd:latest`

If you want to push to a registry:

```bash
./build-image.sh --push latest
```

## Auth/config persistence

`ocd.fish` mounts host config/cache into the container under `/tmp/home` so OpenCode + GitHub tooling can reuse your login state when available.

Currently it mounts (if present):
- OpenCode: `opencode/` under XDG config/cache/data
- GitHub CLI: `gh/` under XDG config/cache
- GitHub Copilot: `github-copilot/` under XDG config/cache/data

On startup, `entrypoint.sh` also installs the RTK OpenCode plugin to `opencode/plugins/rtk.ts` inside the mounted config dir so OpenCode can use `rtk rewrite` automatically.

## Lint ("tests")

No unit tests. Treat these as checks:

```bash
hadolint Dockerfile
shellcheck entrypoint.sh
fish -n ocd.fish
```

Quick RTK smoke check:

```bash
docker run --rm -v "$PWD:/work" -w /work ocd:dev bash -lc \
  'command -v rtk >/dev/null && test -f /usr/local/share/rtk/opencode-rtk.ts'
```

If your host does not have these tools, run the checks inside the image:

```bash
docker run --rm -v "$PWD:/work" -w /work ocd:dev bash -lc \
  'hadolint Dockerfile && shellcheck entrypoint.sh && fish -n ocd.fish'
```
