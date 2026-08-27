#!/usr/bin/env bash
set -euo pipefail

# Create a real account for the host identity before dropping privileges. This
# keeps NSS, setuid programs, sanitizers, and static binaries on their normal paths.
: "${HOME:=/tmp/home}"
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"

UID_NOW="$(id -u)"
GID_NOW="$(id -g)"
TARGET_UID="${HOST_UID:-$UID_NOW}"
TARGET_GID="${HOST_GID:-$GID_NOW}"

if [[ ! "$TARGET_UID" =~ ^[0-9]+$ ]] || [ "$TARGET_UID" -gt 4294967294 ]; then
	printf 'entrypoint: invalid HOST_UID: %s\n' "$TARGET_UID" >&2
	exit 1
fi
if [[ ! "$TARGET_GID" =~ ^[0-9]+$ ]] || [ "$TARGET_GID" -gt 4294967294 ]; then
	printf 'entrypoint: invalid HOST_GID: %s\n' "$TARGET_GID" >&2
	exit 1
fi

if [ "$UID_NOW" -eq 0 ] && { [ "$TARGET_UID" -ne 0 ] || [ "$TARGET_GID" -ne 0 ]; }; then
	if group_record="$(getent group "$TARGET_GID")"; then
		runtime_group="${group_record%%:*}"
	else
		runtime_group="hostgrp-$TARGET_GID"
		if getent group "$runtime_group" >/dev/null; then
			printf 'entrypoint: group name %s already exists\n' "$runtime_group" >&2
			exit 1
		fi
		groupadd --gid "$TARGET_GID" "$runtime_group"
	fi

	if passwd_record="$(getent passwd "$TARGET_UID")"; then
		runtime_user="${passwd_record%%:*}"
		current_primary_gid="$(printf '%s' "$passwd_record" | cut -d: -f4)"
		current_home="$(printf '%s' "$passwd_record" | cut -d: -f6)"
		current_shell="$(printf '%s' "$passwd_record" | cut -d: -f7)"
		if [ "$TARGET_UID" -ne 0 ] && { [ "$current_primary_gid" != "$TARGET_GID" ] || \
			[ "$current_home" != "$HOME" ] || [ "$current_shell" != /usr/bin/fish ]; }; then
			usermod --gid "$TARGET_GID" --home "$HOME" --shell /usr/bin/fish "$runtime_user"
		fi
	else
		requested_user="${HOST_USER:-dev}"
		if [[ "$requested_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && ! getent passwd "$requested_user" >/dev/null; then
			runtime_user="$requested_user"
		else
			runtime_user="host-$TARGET_UID"
		fi
		if getent passwd "$runtime_user" >/dev/null; then
			printf 'entrypoint: user name %s already exists\n' "$runtime_user" >&2
			exit 1
		fi
		useradd --uid "$TARGET_UID" --gid "$TARGET_GID" --home-dir "$HOME" \
			--shell /usr/bin/fish --no-create-home --no-log-init "$runtime_user"
	fi

	export RUNTIME_USER="$runtime_user"
	exec setpriv --reuid="$TARGET_UID" --regid="$TARGET_GID" --clear-groups \
		--inh-caps=-all --ambient-caps=-all /usr/local/bin/entrypoint.sh "$@"
fi

if [ "$UID_NOW" -ne "$TARGET_UID" ] || [ "$GID_NOW" -ne "$TARGET_GID" ]; then
	printf 'entrypoint: expected UID:GID %s:%s, running as %s:%s\n' \
		"$TARGET_UID" "$TARGET_GID" "$UID_NOW" "$GID_NOW" >&2
	exit 1
fi

if [ -z "${RUNTIME_USER:-}" ]; then
	if passwd_record="$(getent passwd "$UID_NOW")"; then
		RUNTIME_USER="${passwd_record%%:*}"
	else
		RUNTIME_USER="${HOST_USER:-dev}"
	fi
fi
export USER="$RUNTIME_USER"
export LOGNAME="$RUNTIME_USER"

mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" >/dev/null 2>&1 || true

# ---- Git safe.directory handling ----
# If we're exactly at the root of a git repo, mark it safe (avoid "dubious ownership")
if command -v git >/dev/null 2>&1; then
	if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
		if [ -n "$repo_root" ] && [ "$repo_root" = "$(pwd -P)" ]; then
			if ! git config --global --get-all safe.directory 2>/dev/null | grep -Fxq "$repo_root"; then
				git config --global --add safe.directory "$repo_root" || true
			fi
		fi
	fi
fi

exec "$@"
