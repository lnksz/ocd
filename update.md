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

- Keep check scripts, downloaded verification assets, and build logs in the
  ignored repository `tmp/` directory. If the host Docker configuration is
  read-only in an automation sandbox, set `BUILDX_CONFIG` to a private directory
  under that `tmp/` directory; no host Docker configuration changes are needed.
- Check npm's exact package metadata and platform optional dependencies. The
  OpenCode V2 package is `@opencode/cli`; a GitHub `releases/latest` response can
  still point to the V1 maintenance series and is not the V2 version source.
- Keep Node on the existing LTS major and package managers on their existing
  major unless a migration has been checked. Check the newest release within
  that major, rather than only npm's `latest` tag.
- Check PyPI `Requires-Python` against the image's actual Python version before
  updating. Ubuntu 26.04 uses Python 3.14: `cmake-language-server` 0.1.6 through
  0.1.11 exclude that interpreter, so retain 0.1.5 until upstream supports it.
- Prek publishes GNU Linux archives and companion `.sha256` files for both
  `x86_64` and `aarch64`; select the target using `dpkg --print-architecture`.
- RTK 0.51 changes generic runners to preserve argument boundaries. For shell
  scripts use an explicit shell, e.g. `rtk test --shell sh 'cargo test && cargo
  clippy'`. This repository does not invoke those generic runners.

## 2026-10-13 refresh

Scope follows the command above: `opencode/Dockerfile` and `pi/Dockerfile`.
Official sources checked: [Node distribution index](https://nodejs.org/dist/index.json),
[npm registry](https://registry.npmjs.org/), [PyPI](https://pypi.org/),
[Hadolint releases](https://github.com/hadolint/hadolint/releases),
[Prek releases](https://github.com/j178/prek/releases), and
[RTK releases](https://github.com/rtk-ai/rtk/releases).

| Component | Previous | Selected |
| --- | --- | --- |
| pnpm | 11.25.0 | 11.28.5 |
| @yarnpkg/cli-dist | 4.18.0 | 4.18.1 |
| typescript-language-server | 6.0.0 | 6.0.2 |
| bash-language-server | 5.6.0 | 5.8.1 |
| yaml-language-server | 1.24.0 | 1.25.0 |
| hunkdiff | 0.21.0 | 0.23.0 |
| prettier | 3.9.6 | 3.9.10 |
| eslint | 10.9.1 | 10.12.0 |
| pyright | 1.1.413 | 1.1.414 |
| @ast-grep/cli | 0.45.3 | 0.50.0 |
| @opencode/cli | 2.0.22 | 2.0.28 |
| ruff | 0.16.5 | 0.17.0 |
| black | 26.5.1 | 26.10.1 |
| isort | 9.0.1 | 9.0.2 |
| mypy | 2.3.1 | 2.4.0 |
| ansible | 14.3.1 | 14.5.0 |
| ansible-lint | 26.8.0 | 26.10.0 |
| uv | 0.12.9 | 0.13.0 |
| j178/prek | v0.5.2 | v0.5.5 |
| rtk-ai/rtk | v0.47.0 | v0.51.0 |
| Node.js | v24.20.0 | v24.21.0 |

Already current: Hadolint 2.15.1, TypeScript 7.0.2,
`vscode-langservers-extracted` 4.10.0, `dockerfile-language-server-nodejs` 0.15.0,
Taplo 0.7.0, markdownlint-cli 0.49.1, Ansible language server 26.6.0, and
python-lsp-server 1.15.0. Retained cmake-language-server 0.1.5 for Python 3.14
compatibility and pnpm major 11 (npm `latest` was 12.11.2). Intentional dynamic
installs (Pi, GitLab CLI, and Go tools) remain unchanged.

Verified amd64/arm64 release asset names and availability for Node, Hadolint,
Prek, and RTK. Downloaded Hadolint, Prek, and RTK assets matched upstream SHA-256
metadata; Prek and RTK also matched their downloaded checksum companions.
Archive layouts match the extraction commands. Node's upstream checksum filename
entries and both download URLs exist; the image build verifies its native
archive against SHASUMS256. The selected OpenCode and ast-grep native npm
packages exist for both architectures. No raw tagged companion files are
fetched by these Dockerfiles. No asset or path verification failed.

Startup verification found that plain `pipx install ansible` exposes only
`ansible-community`: the actual `ansible` and `ansible-playbook` commands belong
to its ansible-core dependency. Both images now use `--include-deps` to expose
those commands. Keep this option during future refreshes.

npm emits an engine warning for Hunk's automatically installed OpenTUI peer
(`@opentui/core` 0.5.17 requires Node >=26.4). Hunk itself supports Node >=22;
its launcher selects a bundled native executable. Verify that executable's
startup, not just the npm installation, before accepting the update. The
Node-based OpenTUI extension export is outside this command-line smoke scope.

Validation on amd64 passed:

- Hadolint 2.15.1 for both Dockerfiles; ShellCheck for the documented shell
  scripts; Fish syntax checks; `git diff --check`.
- All 10 OpenCode and 3 Pi wrapper tests.
- Actual `docker build` and native image startup for `ocd:dev` (OpenCode 2.0.28)
  and `pid:dev` (Pi 1.2.0), including the normal privilege-dropping entrypoints,
  host UID/GID account creation, synthetic HOME, passwordless sudo, Fish startup,
  agent version/help, installed tool versions, ast-grep outline, and RTK's
  explicit-shell runner. All installed npm versions matched the selected pins.
- Documented `command -v` startup smokes for both images and an actual Ansible
  localhost ping (`pong`) under the host UID/GID.

Final images: OpenCode
`sha256:eb8640d1080ed814b8fea6fcce5c5918796dc7657d4ae51401cb896603eb2b53`;
Pi `sha256:3f8b9cd3a917cdaa5116c116a5c3619d2c5f5d2c153eed1ba3479b2a42caa0c0`.
ARM64 assets were checked, but no ARM64 image was built or started. Agent
startup did not make an authenticated model request. The first smoke caught
missing Ansible commands; after adding `--include-deps`, both final smokes
passed without PATH overrides. Logs and upstream metadata are retained locally
under `tmp/update-2026-10-13/`.
