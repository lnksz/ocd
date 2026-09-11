#!/usr/bin/env bash
set -euo pipefail

# The host checks this before supplying mount paths to a cached launcher.
if [ "${1:-}" = --runtime-version ]; then
	printf '2\n'
	exit 0
fi

# Keep the template's agent account, HOME, proxy and Docker setup. Only link
# agent-specific host directories. Existing sandbox defaults are kept once.
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"

link_directory() {
	local source="$1" target="$2"
	if [ ! -d "$source" ]; then
		printf 'ox: missing shared directory %s; recreate with ox --rm, then ox\n' "$source" >&2
		exit 1
	fi
	mkdir -p "$(dirname "$target")"
	if [ "$source" = "$target" ]; then
		return
	fi
	if [ -L "$target" ]; then
		ln -sfnT "$source" "$target"
	else
		if [ -e "$target" ]; then
			mv -T -- "$target" "$target.ox-original"
		fi
		ln -sT "$source" "$target"
	fi
}

link_directory "${OX_HOST_CONFIG:?}" "$XDG_CONFIG_HOME/opencode"
if [ ! -d "${OX_HOST_DATA_SEED:?}" ]; then
	printf 'ox: missing credential seed %s; recreate with ox --rm, then ox\n' "$OX_HOST_DATA_SEED" >&2
	exit 1
fi
for directory in "$XDG_CACHE_HOME/opencode" "$XDG_DATA_HOME/opencode"; do
	if [ -L "$directory" ]; then
		printf 'ox: refusing legacy shared OpenCode runtime %s; recreate with ox --rm, then ox\n' "$directory" >&2
		exit 1
	fi
done
mkdir -p "$XDG_CACHE_HOME/opencode" "$XDG_DATA_HOME/opencode"
for file in auth.json account.json; do
	if [ ! -e "$XDG_DATA_HOME/opencode/$file" ] && [ -r "$OX_HOST_DATA_SEED/$file" ]; then
		install -m 0600 "$OX_HOST_DATA_SEED/$file" "$XDG_DATA_HOME/opencode/$file"
	fi
done
unset OX_HOST_CACHE OX_HOST_DATA
while [ "${1:-}" != -- ]; do
	case "${1:-}" in
	config/*) root="$XDG_CONFIG_HOME" ;;
	cache/*) root="$XDG_CACHE_HOME" ;;
	data/*) root="$XDG_DATA_HOME" ;;
	*) printf 'ox: invalid shared directory argument\n' >&2; exit 2 ;;
	esac
	link_directory "$2" "$root/${1#*/}"
	shift 2
done
shift
mode="${1:?}"
shift

if [ -r /usr/local/share/rtk/opencode-rtk.ts ]; then
	install -d "$XDG_CONFIG_HOME/opencode/plugins"
	install -m 0644 /usr/local/share/rtk/opencode-rtk.ts "$XDG_CONFIG_HOME/opencode/plugins/rtk.ts"
fi

# Trust only the current workspace, even if the host UID differs from agent.
workspace="$(pwd -P)"
if ! git config --global --get-all safe.directory | grep -Fxq "$workspace"; then
	git config --global --add safe.directory "$workspace"
fi

if [ "$mode" = shell ]; then
	exec fish "$@"
fi
export OPENCODE_TUI_CONFIG=/usr/local/share/ox/tui.json
before_sessions="$(mktemp)"
if opencode session list --format json >"$before_sessions" 2>/dev/null; then
	baseline_ready=1
else
	baseline_ready=0
fi
set +e
trap : INT
opencode "$@"
opencode_status=$?
if [ "$opencode_status" -ne 0 ] && [ "$opencode_status" -ne 130 ]; then
	printf 'ox: OpenCode exited with status %s; use ox --print-logs --log-level DEBUG for startup diagnostics\n' \
		"$opencode_status" >&2
fi
after_sessions="$(mktemp)"
if [ "$baseline_ready" -eq 1 ] && opencode session list --format json >"$after_sessions" 2>/dev/null; then
	export_dir="$XDG_DATA_HOME/ox/session-exports"
	mkdir -p "$export_dir"
	while IFS= read -r session_id; do
		if [[ ! "$session_id" =~ ^ses_[A-Za-z0-9_-]+$ ]]; then
			continue
		fi
		temporary="$export_dir/.$session_id.json.$$"
		if opencode export "$session_id" >"$temporary" 2>/dev/null; then
			snapshot_hash="$(sha256sum "$temporary")"
			mv -f "$temporary" "$export_dir/$session_id.${snapshot_hash%% *}.json"
			printf 'ox: queued %s; run ox --sync-sessions on the host to import it\n' "$session_id" >&2
		else
			rm -f "$temporary"
			printf 'ox: failed to queue session snapshot %s\n' "$session_id" >&2
		fi
	done < <(node -e '
const fs = require("fs")
try {
  // OpenCode prints nothing, rather than [], when no sessions exist.
  const read = (file) => JSON.parse(fs.readFileSync(file, "utf8").trim() || "[]")
  const before = new Map(read(process.argv[1]).map((item) => [item.id, item.updated]))
  const after = read(process.argv[2])
  for (const item of after) {
    if (!before.has(item.id) || item.updated > before.get(item.id)) console.log(item.id)
  }
} catch (error) {
  console.error("ox: failed to compare session snapshots:", error.message)
}
' "$before_sessions" "$after_sessions")
fi
rm -f "$before_sessions" "$after_sessions"
exec fish
