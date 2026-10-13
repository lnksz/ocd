#!/usr/bin/env bash
set -euo pipefail

# This Claude-compatible path is ephemeral and not a mounted host skill root.
# Prefer existing shared/OpenCode definitions with the same directory name.
builtin="${1:-/usr/local/share/agent-skills}"
for skill in "$builtin"/*; do
    [ -f "$skill/SKILL.md" ] || continue
    name="${skill##*/}"
    if [ -e "$HOME/.agents/skills/$name" ] || \
        [ -e "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills/$name" ]; then
        continue
    fi
    destination="$HOME/.claude/skills/$name"
    if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
        mkdir -p "${destination%/*}"
        ln -s "$skill" "$destination"
    fi
done
