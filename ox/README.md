# ox: OpenCode in Docker Sandboxes

`ox` is the Docker Sandboxes counterpart to `ocd`, for a Linux host running
Fish. It uses the **standalone `sbx` CLI**, with its API checked against
**0.42.1**. Older `docker sandbox` plugin tutorials describe a different CLI.

## Set up

1. [Install Docker Sandboxes](https://docs.docker.com/ai/sandboxes/install/).
   On supported Ubuntu 24.04+ hosts, enable KVM, add your account to the `kvm`
   group, and sign in with `sbx login`. Docker Desktop is not required.
   Run this on the host, rather than inside `ocd` or `pid`.

2. The default template is `docker.io/lnksz/ox:latest`. Once the publishing
   workflow has run successfully on `master`, `sbx` can pull it directly and
   you do not need Docker on the host.

   Before the first publication, or for local development, build and import
   the template from the repository root using Docker with BuildKit:

   ```bash
   docker build -f ox/Dockerfile -t docker.io/local/ox:dev ox
   docker image save docker.io/local/ox:dev -o /tmp/ox-template.tar
   sbx template load /tmp/ox-template.tar
    rm /tmp/ox-template.tar
    ```

   Select that local template in Fish:

   ```fish
   set -gx OX_IMAGE docker.io/local/ox:dev
   ```

   Sandboxes has a separate image store: building the image in the host Docker
   daemon alone does not make it available to `sbx`. Alternatively, push your
   template to a registry and set `OX_IMAGE` to its fully qualified reference.
   The workflow added on this branch takes effect after merging to `master`;
   adding the workflow does not itself publish an image.

3. Install the Fish functions with `bash ./install.sh`, or source this one:

   ```fish
   source /path/to/ocd/ox/ox.fish
   cd /path/to/project
   ox
   ```

Your existing OpenCode login (`auth.json` and `account.json`) is copied into a
new sandbox on first launch. Config, plugins, agents, commands, and skills are
shared automatically, just as with `ocd`. Existing `config.env` is passed using
`sbx exec --env-file`; it is not sourced as shell code. Host config changes take
effect when you quit and restart OpenCode with `ox`.

OpenCode cache, history, logs, and SQLite data stay inside each sandbox. Do not
mount the host OpenCode data directory into the microVM: SQLite WAL access from
host and sandbox processes crosses kernel and virtiofs coherence boundaries.
After upgrading from an earlier `ox` checkout that shared this directory, exit
the session, refresh or rebuild/load the template, and recreate the sandbox
before continuing. See [apply an update](#apply-a-published-update-on-your-host):
`ox --rm` alone can reuse an incompatible cached image.

## Everyday use

```fish
ox                             # OpenCode in the current directory
ox -c                          # continue the last OpenCode session
ox --continue                  # forward arguments to OpenCode
ox run 'Explain this project'   # OpenCode CLI, then Fish, like ocd
ox -s                          # Fish directly (--shell also works)
ox -s -c 'node --version'       # execute a Fish command
ox -- -s session-id            # escape ox's -s shorthand for OpenCode
ox --sandbox-name              # print this directory's stable sandbox name
ox --sync-sessions             # import queued snapshots into host OpenCode
ox --stop                      # stop the VM, keeping installed tools/state
ox --rm                        # remove the sandbox; the next ox recreates it
```

OpenCode exits into Fish in the same sandbox. Exiting Fish returns to the
host. The sandbox stays available until stopped or removed. `ox` restarts a
stopped sandbox automatically. Names are `ox-<hash of absolute working path>`
so unrelated projects with the same basename do not collide. Moving a project
changes its sandbox name; remove the old sandbox explicitly with `sbx rm`.

When OpenCode exits, `ox` queues JSON exports of the root sessions created or
updated during that invocation. From the same project directory on the host, run
`ox --sync-sessions` to copy queued exports through `sbx cp` and import them
with the host `opencode` command. Successfully imported queue entries are
removed; failed copies/imports stay queued for retry. Each exported revision
has a content-addressed filename, so importing it cannot remove a newer revision
of the same session. An empty queue is a successful no-op. Sync before `ox --rm`
if you want to retain those snapshots.

Snapshots are one-way archives, not live synchronization. The sandbox remains
authoritative; do not continue the same imported session independently in both
environments. Use OpenCode's `serve`/`attach` mode instead when both terminals
must operate on one live session. OpenCode's importer inserts missing messages
and parts but does not replace existing ones or refresh existing session
metadata; later imports are not an exact mirror of edited or compacted history.

Use `sbx ls` for all sandboxes. For development servers, publish ports with:

```fish
sbx ports (ox --sandbox-name) --publish 8080:3000
```

`ox --rm` uses the normal `sbx rm` confirmation and active-session checks.
Exit the session first and confirm removal. Files in shared host directories
survive removal; OpenCode history and logs, packages, Docker images, and other
sandbox-local files do not.

## Features compared with ocd

| Feature | ox behavior |
| --- | --- |
| Current directory | Direct, read/write mount at the same absolute path; changes appear on the host immediately |
| OpenCode arguments, `-s` / `--shell`, post-agent Fish | Preserved |
| OpenCode config and login | Config is shared; host login files seed private sandbox data on first launch |
| OpenCode cache, data, logs and history | Private to each persistent sandbox to keep SQLite WAL access within one kernel |
| Host session visibility | `ox --sync-sessions` imports queued, completed JSON snapshots into host OpenCode |
| GitHub CLI/Copilot auth | Same existing `gh/` and `github-copilot/` directories as `ocd` |
| Linked worktrees | Mount the external Git common directory as well, without mounting the main working tree |
| Symlinked config | Share commands/agents/skills directory targets; share the immediate parent of external `AGENTS.md` and `opencode.json[c]` file targets read-only |
| Terminal | Forward `TERM`, `TERM_PROGRAM`, `COLORTERM`, and optional terminfo; disable OpenCode's terminal-suspend key through a sandbox-only TUI override |
| Development toolbox | Fish, Node, C/C++, Python, Go, Ansible, LSPs, linters, Hunk, RTK and its plugin, Prek, GitHub/GitLab CLIs |
| Default resources | 60% RAM; 60% CPUs rounded down to whole vCPUs, minimum one |
| Isolation | Dedicated microVM kernel and sandbox network controls |
| Docker inside the agent | Private Docker Engine in the sandbox, without a host Docker socket mount |
| Lifetime | Persistent per working directory, including OpenCode history, installed tools and shell history |

The template extends Docker's **OpenCode Docker-enabled template**, preserving
its entrypoint, labels, proxy environment, non-root `agent` account and sudo
access. It pins the upstream multi-platform image digest, Node, and additional
downloaded tools where practical. The build replaces the upstream OpenCode
installation with the requested npm version. OS packages (including `gh`/`glab`)
come from its Ubuntu repositories, so those versions need not match `ocd` exactly.

## Updates and automated publishing

The existing `.github/workflows/build-and-push.yml` has a separate `ox` job.
It runs on pushes to `master`, daily at **02:00 UTC**, and on manual workflow
dispatch (which also builds `master`). It uses the existing
`DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets, with push access to `lnksz/ox`.
The GitHub-hosted runner builds a **linux/amd64** image, matching the existing
agent publishing jobs. ARM64 hosts can build/import the template locally.

The job executes:

```bash
./build-image.sh ox --push
```

The builder resolves `opencode-ai@latest` to an exact version, passes it to the
Dockerfile, checks the built image's `opencode --version`, and publishes:

- `docker.io/lnksz/ox:<OpenCode version>`
- `docker.io/lnksz/ox:latest`

Version tags, like those for `ocd` and `pid`, can be rebuilt as tooling changes;
use an image digest with `OX_IMAGE` when you need an immutable reference.
Local builds support the same flags:

```bash
./build-image.sh ox latest
./build-image.sh ox --no-cache --push
```

Build-time overrides are `OX_ENGINE`, `OX_IMAGE_REPO`, `OX_PUSH`,
`OX_OPENCODE_VERSION`, and `OX_OPENCODE_PKG`. `OX_IMAGE` selects the runtime
template, while `OX_IMAGE_REPO` selects where the builder tags/publishes it.

### Apply a published update on your host

Existing sandboxes keep their original filesystem and installed binaries.
`sbx` also caches templates, so merely restarting or recreating a sandbox does
not guarantee the required launcher is available. Some sbx versions also resolve
registry tags again during creation, replacing a locally loaded build with the
published image. The wrapper checks the launcher's runtime version before setup
and rejects images that predate private OpenCode data.

For a host without Docker, exit the current session, select the published
template, remove the sandbox and its cached template tag, then recreate:

```fish
set -gx OX_IMAGE docker.io/lnksz/ox:latest
ox --rm
sbx template rm "$OX_IMAGE"
ox -c
```

If that template is not cached, skip the `sbx template rm` step. If removal is
blocked by another sandbox using the image, you can import a fresh copy using
Docker instead:

```fish
docker pull "$OX_IMAGE"
docker image save "$OX_IMAGE" -o /tmp/ox-template.tar
sbx template load /tmp/ox-template.tar
rm /tmp/ox-template.tar
ox -c
```

Recreate each project sandbox when ready to adopt the new image. Shared project
files and configuration survive. Host login files seed the replacement sandbox;
OpenCode history, packages, Docker images, and other sandbox-local files are
removed with the old sandbox.

### Apply changes from an unpublished checkout

When the wrapper and `ox/session.sh` have changed locally, refreshing a published
tag cannot supply those changes. Build and load the current checkout under a
separate local tag so registry resolution cannot replace it with the old image:

```fish
docker build -f ox/Dockerfile -t docker.io/local/ox:dev ox
docker image save docker.io/local/ox:dev -o /tmp/ox-template.tar
sbx template load /tmp/ox-template.tar
rm /tmp/ox-template.tar
source ox/ox.fish
set -gx OX_IMAGE docker.io/local/ox:dev
# From the project directory, sync any snapshots you need, then recreate:
ox --rm
ox
```

Skip removal if the project has no sandbox yet. Loading the new image replaces
the cached template tag; existing sandboxes still need to be recreated.

### What updates separately

- **OpenCode:** resolved and installed afresh by the daily build.
- **Sandbox base and development tools:** pinned in `ox/Dockerfile`; update the
  digest/version pins in Git, then rebuild. The daily job does not rewrite pins.
- **Fish wrapper:** update the checkout and rerun `bash ./install.sh`; re-source
  `ox/ox.fish` in an already-open shell.
- **Host `sbx`:** update through your host package manager, e.g.
  `sudo apt-get update && sudo apt-get install --only-upgrade docker-sbx`.

## Overrides

```fish
set -gx OX_IMAGE registry.example.com/team/ox:v1
set -gx OX_CPUS 6
set -gx OX_MEMORY 12g
# Or percentage-based defaults:
set -gx OX_CPU_PERCENT 50
set -gx OX_MEMORY_PERCENT 50
```

Only `OX_*` resource/image variables are read; `OCD_*` and `PID_*` are
independent. Absolute resource overrides take precedence over percentages.
`OX_CPUS` must be a positive integer. `OX_MEMORY` uses sbx's binary units, such
as `512m` or `8g`.

**Image, resources, and mounts are fixed when the sandbox is created.** After
changing those settings, XDG roots, external symlink targets, or adding an
optional auth directory, run `ox --rm` followed by `ox`. Editing files within
an existing mount needs only a fresh OpenCode session. `config.env` and terminal
variables are passed anew on every invocation. Changes to host OpenCode login
files do not overwrite an existing sandbox's private login; recreate the
sandbox to seed them again.

## Differences to account for

- `ox` initially targets Linux, matching `ocd`'s use of `nproc` and
  `/proc/meminfo`. Docker Sandboxes itself also supports macOS and Windows.
- HOME is the template's `/home/agent`, rather than `/tmp/home`. Configs with
  hard-coded `/tmp/home` paths need to use the corresponding sandbox paths.
  Arbitrary absolute references and symlinks outside the documented shares
  are not discovered automatically.
- `sbx` workspace arguments must be directories. For a config file linked to
  `/path/to/dotconf/opencode/AGENTS.md`, `ox` shares `/path/to/dotconf/opencode`
  read-only, including its other files. Targets already inside a shared
  directory use that existing mount without changing its access mode.
- UID/GID translation belongs to the sandbox filesystem layer. `ox` keeps
  Docker's `agent` account instead of running `ocd`'s host-account entrypoint.
- Copying host `auth.json`/`account.json`, sharing auth directories, and passing
  `config.env` gives the agent access to those credentials, as `ocd` does. The
  wrapper's protected seed directory is `$XDG_DATA_HOME/ox/opencode-seed`; it
  does **not** convert credentials into proxy-protected secrets. Docker also
  supports `sbx secret set` for supported providers; see its
  [credential guide](https://docs.docker.com/ai/sandboxes/configuration/credentials/).
- Sandboxes applies its own network policy. Custom providers, MCP endpoints
  and private services must be reachable under that policy. Configure this
  with `sbx policy` according to Docker's documentation. The wrapper does not
  change your global policy.

## Troubleshoot OpenCode startup

`missing shared directory /__ox_private_runtime_requires_recreate` means an older
wrapper detected an incompatible image through a placeholder mount path. The
current wrapper reports `outdated session launcher` instead. Both require an
updated **template and sandbox**, not a directory with that name. Use the
[published update](#apply-a-published-update-on-your-host) steps or
[build/load this checkout](#apply-changes-from-an-unpublished-checkout).

`Failed to read KV state` with `ENOENT` for
`/home/agent/.local/state/opencode/kv.json` can appear on first launch. This file
stores TUI preferences in the sandbox, separately from its private OpenCode data
directory. OpenCode catches that read error and continues initialization, so
the message alone does not identify why the process exited or the TUI stalled.

The session launcher reports nonzero OpenCode exits before opening Fish (except
normal Ctrl-C termination). For more detail, use:

```fish
ox --print-logs --log-level DEBUG
```

To capture the version and exit status even in an existing sandbox with an older
session launcher, enter its Fish shell and run OpenCode directly:

```fish
ox -s
opencode --version
env OPENCODE_TUI_CONFIG=/usr/local/share/ox/tui.json opencode --print-logs --log-level DEBUG
printf 'OpenCode exit status: %s\n' $status
```

Include the version, debug output surrounding the failure, exit status, and
whether the TUI closes or hangs when reporting a startup problem. The final
`printf` runs after OpenCode returns to Fish.

## Verification

```bash
hadolint ox/Dockerfile
shellcheck ox/session.sh install.sh
fish -n ox/ox.fish
python3 -B -m unittest discover -s ox/tests -v
```

The automated tests exercise argument boundaries, creation/reuse, lifecycle,
mount selection, worktrees, overrides and error propagation with a recording
`sbx` executable. Image-builder tests check version resolution, tags, overrides,
existing agent behavior and failure-before-publish handling with a recording
container engine. The base image manifest and sbx 0.42.1 CLI help were also
inspected. A local image build with OpenCode 1.18.30 and live sbx 0.38.0 checks
verified creation, private SQLite/cache directories, empty-queue sync, real
OpenCode session export/import, and stop/restart persistence with isolated host
XDG directories. Interactive TUI/provider behavior still needs a manual check.

On a supported host, after building/importing, smoke-check with:

```fish
ox -s -c 'id; pwd; command -v opencode fish node rtk hunk glab; sudo -n true; docker info'
ox -s -c 'git status; test -w $XDG_DATA_HOME/opencode; and echo "OpenCode data writable"'
ox
ox --stop
ox -s -c 'echo "Sandbox restarted"'
```

Reference: [usage](https://docs.docker.com/ai/sandboxes/usage/),
[OpenCode](https://docs.docker.com/ai/sandboxes/agents/opencode/),
[custom templates](https://docs.docker.com/ai/sandboxes/customize/templates/).
