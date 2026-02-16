# ocd

Run OpenCode inside Docker against your current working directory.

This repo contains:
- `Dockerfile`: the dev image ("everything included" tooling)
- `entrypoint.sh`: sets up HOME/XDG + `nss_wrapper` for arbitrary `--user UID:GID`
- `ocd.fish`: Fish wrapper function to run the container
- `build-image.sh`: build + tag images to match the published `opencode-ai` version

## Quick start (Fish)

1) Load the function:

```fish
source /path/to/ocd.fish
```

2) Run OpenCode in the current directory:

```fish
ocd
```

By default it uses the image `lnksz/ocd:latest`.

Override the image:

```fish
set -x OCD_IMAGE ocd:dev
ocd
```

## Build

Local build:

```bash
docker build -t ocd:dev .
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

This tags:
- `lnksz/ocd:<resolved_version>`
- `lnksz/ocd:latest`

## Auth/config persistence

`ocd.fish` mounts host config/cache into the container under `/tmp/home` so OpenCode + GitHub tooling can reuse your login state when available.

Currently it mounts (if present):
- OpenCode: `opencode/` and/or `opencode-ai/` under XDG config/cache
- GitHub CLI: `gh/` under XDG config/cache
- GitHub Copilot: `github-copilot/` under XDG config/cache/data

## Lint ("tests")

No unit tests. Treat these as checks:

```bash
hadolint Dockerfile
shellcheck entrypoint.sh
fish -n ocd.fish
```

If your host does not have these tools, run the checks inside the image:

```bash
docker run --rm -v "$PWD:/work" -w /work ocd:dev bash -lc \
  'hadolint Dockerfile && shellcheck entrypoint.sh && fish -n ocd.fish'
```
