#!/usr/bin/env bash

set -eu

: "${HOME:?HOME must be set}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fish_functions_dir="${XDG_CONFIG_HOME:-"$HOME/.config"}/fish/functions"

install -Dm644 "$script_dir/opencode/ocd.fish" "$fish_functions_dir/ocd.fish"
install -Dm644 "$script_dir/pi/pid.fish" "$fish_functions_dir/pid.fish"
