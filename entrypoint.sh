#!/usr/bin/env bash
set -euo pipefail

# When running with --user UID:GID there may be no passwd entry.
# Provide a stable HOME and XDG dirs, then synthesize passwd/group via nss_wrapper.
: "${HOME:=/tmp/home}"
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"

mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" >/dev/null 2>&1 || true

UID_NOW="$(id -u)"
GID_NOW="$(id -g)"

# Optional cosmetic username (for prompt/tools); not required for permissions.
: "${HOST_USER:=dev}"

# nss_wrapper setup
PASSWD_FILE="$HOME/.passwd"
GROUP_FILE="$HOME/.group"
SHADOW_FILE="$HOME/.shadow"

# Use a real shell path in passwd entry; fish may not be present in minimal images, but we have it.
SHELL_PATH="${SHELL:-/usr/bin/fish}"

# Write synthetic passwd/group entries for root + current UID/GID
# Format: name:passwd:uid:gid:gecos:home:shell
{
	printf 'root:x:0:0:root:/root:/usr/sbin/nologin\n'
	printf '%s:x:%s:%s:%s:%s:%s\n' "$HOST_USER" "$UID_NOW" "$GID_NOW" "$HOST_USER" "$HOME" "$SHELL_PATH"
} >"$PASSWD_FILE"
{
	printf 'root:x:0:\n'
	printf '%s:x:%s:\n' "hostgrp" "$GID_NOW"
} >"$GROUP_FILE"
shadow_hash="!"
if command -v openssl >/dev/null 2>&1; then
	shadow_hash="$(openssl passwd -6 -salt opencode opencode)"
fi
{
	# Format: name:passwd:lastchg:min:max:warn:inactive:expire:reserved
	printf 'root:*:1:0:99999:7:::\n'
	printf '%s:%s:1:0:99999:7:::\n' "$HOST_USER" "$shadow_hash"
} >"$SHADOW_FILE"

chmod 0600 "$PASSWD_FILE" "$GROUP_FILE" "$SHADOW_FILE" 2>/dev/null || true

NSS_WRAPPER_LIB=""
for lib in /lib/*/libnss_wrapper.so /usr/lib/*/libnss_wrapper.so /lib/libnss_wrapper.so /usr/lib/libnss_wrapper.so; do
	if [ -r "$lib" ]; then
		NSS_WRAPPER_LIB="$lib"
		break
	fi
done

if [ -n "$NSS_WRAPPER_LIB" ]; then
	export NSS_WRAPPER_PASSWD="$PASSWD_FILE"
	export NSS_WRAPPER_GROUP="$GROUP_FILE"
	export NSS_WRAPPER_SHADOW="$SHADOW_FILE"
	export LD_PRELOAD="${NSS_WRAPPER_LIB}${LD_PRELOAD:+:$LD_PRELOAD}"
	if [ ! -f /etc/ld.so.preload ]; then
		printf '%s\n' "$NSS_WRAPPER_LIB" >/etc/ld.so.preload 2>/dev/null || true
	fi
fi

# Also set common identity env vars for tools that read them
export USER="$HOST_USER"
export LOGNAME="$HOST_USER"

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
