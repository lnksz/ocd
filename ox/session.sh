#!/usr/bin/env bash
set -euo pipefail

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
link_directory "${OX_HOST_CACHE:?}" "$XDG_CACHE_HOME/opencode"
link_directory "${OX_HOST_DATA:?}" "$XDG_DATA_HOME/opencode"
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
set +e
trap : INT
opencode "$@"
opencode_status=$?
if [ "$opencode_status" -ne 0 ] && [ "$opencode_status" -ne 130 ]; then
	printf 'ox: OpenCode exited with status %s; use ox --print-logs --log-level DEBUG for startup diagnostics\n' \
		"$opencode_status" >&2
fi
exec fish
