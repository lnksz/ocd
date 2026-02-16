# Agent Notes (Repo Guide)

This repo is a small “OpenCode in Docker” wrapper:
- `Dockerfile` builds the dev container image.
- `entrypoint.sh` sets up a synthetic user HOME/XDG + `nss_wrapper`, then execs the command.
- `ocd.fish` provides a Fish function to run the container against the current working directory.

There is no application code or conventional unit test suite here. Quality checks are primarily linters.

## Commands

### Build (Docker image)

Build locally:
```bash
docker build -t ocd:dev .
```

Build and tag to match the resolved OpenCode version:
```bash
./build-image.sh latest
./build-image.sh 0.7.3
```

Build with an explicit OpenCode package/version (if you publish variants):
```bash
docker build \
  --build-arg OPENCODE_PKG=opencode-ai \
  --build-arg OPENCODE_VERSION=latest \
  -t ocd:dev \
  .
```

Smoke-run the image:
```bash
docker run --rm -it ocd:dev fish
```

### Lint / Format

This repo does not include a task runner; run tools directly.

Dockerfile:
```bash
hadolint Dockerfile
```

Bash (`entrypoint.sh`):
```bash
shellcheck entrypoint.sh
shfmt -w -i 4 -ci entrypoint.sh
```

Fish (`ocd.fish`):
```bash
fish -n ocd.fish
```

### “Tests”

No unit tests are present. Treat these as the test suite:
```bash
hadolint Dockerfile && shellcheck entrypoint.sh && fish -n ocd.fish
```

### Running a single check (single “test”)

Prefer running the narrowest check first:
- Single Dockerfile lint: `hadolint Dockerfile`
- Single bash lint: `shellcheck entrypoint.sh`
- Single fish parse check: `fish -n ocd.fish`

If you add a test suite later, update this file with the exact single-test invocation.

## Repo-Specific Rules

Cursor rules: none found in `.cursor/rules/` or `.cursorrules`.

Copilot rules: none found in `.github/copilot-instructions.md`.

If you add either later, mirror the important constraints here.

## Code Style Guidelines

### General

- Keep changes minimal and purpose-driven; this repo is infrastructure glue.
- Prefer boring, portable solutions (Debian + POSIX-ish shell). Avoid cleverness.
- Don’t introduce heavy dependencies or new languages unless they materially simplify the workflow.
- Maintain deterministic container builds: pin where practical, keep layers stable, clean caches.

### Bash (`entrypoint.sh`)

- Start scripts with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Quote variables unless you explicitly want word splitting/globbing.
- Use `: "${VAR:=default}"` for defaults when appropriate.
- Prefer `printf` over `echo` (already used) for predictable output.
- Error handling:
  - Use `|| true` only when failure is expected and safe.
  - Avoid hiding errors by redirecting output unless necessary.
- Keep environment variables documented near where they are set/used:
  - `HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`
  - `HOST_USER`, `LD_PRELOAD`, `NSS_WRAPPER_PASSWD`, `NSS_WRAPPER_GROUP`
- Git safety:
  - `entrypoint.sh` currently adds `safe.directory` globally when running at repo root.
  - Be cautious editing this logic; it affects user global git config inside the container.

Formatting:
- Use `shfmt` with 4-space indentation (consistent with current style).

### Fish (`ocd.fish`)

- Use `function name --description ...` and keep it single-purpose.
- Prefer `set -l` for locals; avoid leaking vars.
- Quote paths; assume spaces in working directories.
- Keep Docker args readable (one flag per line is preferred for long runs).
- The function should remain a thin wrapper; complex logic belongs in scripts.

### Dockerfile

- Keep Debian base (`debian:bookworm-slim`) unless there’s a strong reason to change.
- Use `apt-get install -y --no-install-recommends` and clean `apt` lists in the same layer.
- Avoid leaving caches:
  - `apt-get clean && rm -rf /var/lib/apt/lists/*`
  - `npm cache clean --force`
  - use `pip --no-cache-dir`
- Prefer `ARG` for build-time configuration and `ENV` for runtime defaults.
- Group installs into logical layers (already done). Avoid churn that invalidates cache unnecessarily.

### Imports / Modules

Not applicable (no Python/TS/Go module structure in this repo). If you add source code:
- Establish a formatter + linter and add exact commands to “Commands” above.
- Add a single-test recipe (e.g., `pytest path::test_name`, `go test -run`, `bun test -t`).

### Naming Conventions

- Files: keep conventional names (`Dockerfile`, `entrypoint.sh`, `*.fish`).
- Env vars: `UPPER_SNAKE_CASE`.
- Fish locals: `snake_case`.
- Bash locals: `lower_snake_case` where possible.

### Security / Safety

- Don’t log secrets; avoid printing env vars by default.
- Be careful with `LD_PRELOAD` and `nss_wrapper` behavior; keep it scoped to the container.
- Avoid broadening mounted volumes in `ocd.fish` beyond what’s required.

### Compatibility

- Assume Linux host + Docker.
- Avoid interactive/TTY-dependent behavior in scripts beyond what Docker run already needs.

## When You Change Behavior

- Update this file with new commands (build/lint/test) and any new agent rules.
- Add a quick smoke check command that validates the new behavior.
