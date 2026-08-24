#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    printf 'Usage: %s\n' "./opencode/update-tools.sh"
    printf '\n'
    printf '%s\n' 'Run OpenCode with a prompt that updates pinned opencode/Dockerfile components to their latest versions.'
    exit 0
fi

prompt=$'Update all versioned components pinned in Dockerfile to their latest compatible upstream versions. Work only in this repository. Keep changes minimal and focused on version updates in opencode/Dockerfile unless another repo file must change to keep the build or checks correct. After updating, run hadolint opencode/Dockerfile and report what changed.'

exec opencode run "$prompt" "$script_dir"
