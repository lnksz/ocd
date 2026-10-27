# Component update command

Use this instruction for future dependency refreshes:

> Check all externally version-pinned components in `opencode/Dockerfile` and
> `pi/Dockerfile` against their official upstream releases. Update every newer,
> compatible stable pin, including Node.js, downloaded binaries, npm packages,
> and `pipx` packages. Keep shared pins aligned, preserve agent-specific pins,
> and leave intentionally dynamic `latest` installs unchanged. Do not change
> unpinned Ubuntu apt packages or unrelated configuration.
>
> Before editing, verify each proposed version exists and is compatible. For
> downloaded tools, verify the release asset names for both supported
> architectures, checksums where available, and every companion file fetched
> from the release tag. Check the tagged repository tree for raw-file paths;
> do not assume paths used by an older version still exist. Confirm package
> names and major-version compatibility before making an upgrade.
>
> Make minimal changes. Run `hadolint opencode/Dockerfile`, `hadolint
> pi/Dockerfile`, `shellcheck build-image.sh opencode/entrypoint.sh
> opencode/update-tools.sh pi/entrypoint.sh`, `fish -n opencode/ocd.fish
> pi/pid.fish`, and `git diff --check`. Then build both images with
> `docker build -f opencode/Dockerfile -t ocd:dev opencode` and `docker build
> -f pi/Dockerfile -t pid:dev pi`, followed by the documented startup smoke
> checks. Report sources checked, versions changed or already current, and all
> validation results, including any failed upstream asset or path check.


## Refresh knowledge

- Store check scripts, verification assets, and build logs in the ignored
  repository `tmp/` directory. If host Docker configuration is read-only, set
  `BUILDX_CONFIG` to a private directory there.
- Fetch master before creating the dated branch. Previous automation branches
  can contain unmerged changes; do not assume their fixes or reports are on master.
- OpenCode V2 is published as `@opencode/cli` on npm. GitHub's latest release
  can still identify V1. Verify native optional npm packages for both architectures.
- Keep Node on its existing LTS major and package managers on their existing
  major unless a migration has been checked. Inspect the newest stable release
  within that major, rather than only the npm `latest` tag.
- Check PyPI `Requires-Python` against the image interpreter. Ubuntu 26.04 uses
  Python 3.14; cmake-language-server 0.1.6 through 0.1.11 exclude it, so
  retain 0.1.5.
- Prek has GNU Linux archives and `.sha256` companions for both `x86_64` and
  `aarch64`; select the target with `dpkg --print-architecture`.
- Install Ansible with `pipx install --include-deps` to expose `ansible` and
  `ansible-playbook` from ansible-core. Plain installation exposes only
  `ansible-community`; verify a localhost ping after building.
- YAML language server 2.0 moves its internal modules to an ESM-only `out/src`
  layout. The `yaml-language-server --stdio` CLI remains the entrypoint used
  here. Check an actual LSP initialize/document-symbol/formatting exchange.
  Upstream has no GitHub release at `2.0.0` or `v2.0.0`; use npm's `gitHead`
  to read the matching changelog instead of guessing tagged raw paths.
- RTK 1.0 changes the default binary's license and removes `--ultra-compact`.
  Retain 0.52.0 for this compatibility refresh; evaluate the 1.x migration
  separately. Since 0.51, generic runners preserve argument boundaries: use
  `rtk test --shell sh 'command && command'` for shell scripts.
- OpenCode wrappers gate persistent state mounts by major/minor version.
  OpenCode 2.2.0 therefore requires a 2.2 host or the user's explicit mismatch
  override before sharing state with an older host installation.
- When capturing noninteractive OpenCode output before running Ansible, redirect
  OpenCode stdout to a separate file and then print that file. A focused probe
  showed `opencode --version` 2.1.0 changes the shared stdout pipe from blocking
  to non-blocking; a later Ansible command rejects that file descriptor. Normal
  isolated commands and the final combined smoke pass with separate capture.
- Hunk 0.24.1 supports Node >=22, but npm installs its OpenTUI peer 0.5.17,
  which requests Node >=26.4. Verify Hunk's bundled native CLI on Node 24;
  that check does not validate the Node-based OpenTUI extension export.

## 2026-10-27 refresh

Based on freshly fetched master `22870e1`. Scope follows this file:
`opencode/Dockerfile` and `pi/Dockerfile`. The 2026-10-13 and 2026-10-20
refresh branches remain unmerged; this refresh does not merge those branches.
The architecture-aware Prek selection and Ansible `--include-deps` installation
are included because master still lacks them.

Official sources checked: [Node distribution index](https://nodejs.org/dist/index.json),
[npm registry](https://registry.npmjs.org/), [PyPI](https://pypi.org/),
[Hadolint releases](https://github.com/hadolint/hadolint/releases),
[Prek releases](https://github.com/j178/prek/releases), and
[RTK releases](https://github.com/rtk-ai/rtk/releases).
Compatibility checks included the [OpenCode 2.2.0 changelog](https://github.com/anomalyco/opencode/blob/v2.2.0/CHANGELOG.md),
[YAML 2.0 changelog](https://github.com/redhat-developer/yaml-language-server/blob/6301340c3dd5386a801605bde244486cc24581e0/CHANGELOG.md),
[markdownlint-cli 0.50.0 release notes](https://github.com/igorshubovych/markdownlint-cli/releases/tag/v0.50.0),
and [RTK 1.0 breaking changes](https://github.com/rtk-ai/rtk/releases/tag/v1.0.0).

| Component | Master | Selected |
| --- | --- | --- |
| pnpm | 11.25.0 | 11.28.9 |
| @yarnpkg/cli-dist | 4.18.0 | 4.18.1 |
| typescript-language-server | 6.0.0 | 6.0.2 |
| bash-language-server | 5.6.0 | 5.8.1 |
| yaml-language-server | 1.24.0 | 2.0.0 |
| hunkdiff | 0.21.0 | 0.24.1 |
| prettier | 3.9.6 | 3.9.10 |
| eslint | 10.9.1 | 10.13.0 |
| markdownlint-cli | 0.49.1 | 0.50.0 |
| pyright | 1.1.413 | 1.1.414 |
| @ast-grep/cli | 0.45.3 | 0.51.0 |
| @opencode/cli | 2.0.22 | 2.2.0 |
| ruff | 0.16.5 | 0.17.3 |
| black | 26.5.1 | 26.10.1 |
| isort | 9.0.1 | 9.0.2 |
| mypy | 2.3.1 | 2.4.0 |
| ansible | 14.3.1 | 14.5.0 |
| ansible-lint | 26.8.0 | 26.10.1 |
| uv | 0.12.9 | 0.13.6 |
| j178/prek | v0.5.2 | v0.5.7 |
| rtk-ai/rtk | v0.47.0 | v0.52.0 |
| Node.js | v24.20.0 | v24.22.1 |

Already current: Hadolint 2.15.1, TypeScript 7.0.2,
`vscode-langservers-extracted` 4.10.0, `dockerfile-language-server-nodejs` 0.15.0,
Taplo 0.7.0, Ansible language server 26.6.0, and python-lsp-server 1.15.0.
Retained cmake-language-server 0.1.5: all newer releases through 0.1.11 exclude
Python 3.14. Kept Node on LTS major 24 and package managers on their existing
majors. RTK 0.52.0 is the newest pre-1.0 release; latest 1.1.0 requires a
separate license/CLI migration. Intentional dynamic Pi, GitLab CLI, and Go
installs remain unchanged.

OpenCode 2.1 changes SDK/event contracts while retaining compatibility with
stored sessions and imports. Version 2.2 changes AI SDK exports, removes the
GitHub Action, and requires OpenTUI 0.7 for TUI plugins. These images install
the CLI and do not bundle those integrations; external plugins require their
own compatibility check. State-sharing wrappers require host major/minor 2.2.
Markdownlint-cli 0.50.0 updates its lint engine and rules; it supports Node 24.
The guessed markdownlint root `CHANGELOG.md` URL returned 404. Inspection of
the matching repository tree confirmed no such file; official release notes
provided the compatibility evidence instead. No Dockerfile fetches raw tagged
companion files.

Node archive URLs and checksum filename entries were verified for x64 and
arm64. Hadolint, Prek, and RTK assets were downloaded for both architectures
and checked against available release SHA-256 metadata and checksum companions;
archive layouts match the Dockerfile extraction commands. OpenCode, ast-grep,
and Hunk native npm packages exist for both architectures. No selected binary
asset or required companion check failed. Validation assets and logs are in
ignored `tmp/update-2026-10-27/`.

Validation passed on amd64:

- Hadolint 2.15.1 for both Dockerfiles, prescribed ShellCheck and Fish syntax
  checks, all 10 OpenCode and 3 Pi wrapper tests, and `git diff --check`.
- Actual `docker build` for `ocd:dev` and `pid:dev`, then documented
  `command -v` startup checks for each agent.
- Startup through normal privilege-dropping entrypoints with host UID/GID,
  synthetic HOME, account lookup, passwordless sudo, and Fish. OpenCode's
  matching-host 2.2 version gate also passed. Agent version/help checks reported
  OpenCode 2.2.0 and dynamic Pi 1.4.0.
- Every installed npm and pipx package matched the selected version; image
  Python is 3.14.4. Hunk 0.24.1 native CLI, ast-grep outline, and RTK's
  explicit-shell runner passed.
- Both images completed YAML LSP initialize, document symbols, formatting and
  shutdown, plus an actual Ansible localhost ping (`pong`).
- Both images linted a Markdown fixture, compiled and formatted TypeScript,
  formatted/linted/type-checked Python with Ruff, Black and mypy, and outlined
  JavaScript with ast-grep.

Hunk's OpenTUI 0.5.17 peer still warns that it needs Node >=26.4; the native
CLI passed on Node 24.22.1, but the Node extension export was not tested.
OpenCode stdout was captured separately as described above; no image or PATH
workaround was needed. ARM64 assets were checked, but no ARM64 image was built
or started. No authenticated model requests or external plugin tests were run.

Final image IDs:

- `ocd:dev`: `sha256:f97f9bb8e021eaf534d10c1911c22628c45ace4d5fe7c7ac61169218c4dacbd2`
- `pid:dev`: `sha256:c8880be6018fe912c00c138c7118a45d7a54b0857985a5ed8489169b29654c9b`
