function ocd --description "run OpenCode in Docker/Podman"
    # Container engine and image override:
    # - `set -x OCD_ENGINE podman|docker`
    # - `set -x OCD_IMAGE docker.io/lnksz/ocd:latest`
    set -l engine
    if set -q OCD_ENGINE
        set engine $OCD_ENGINE
    else if command -sq docker
        set engine docker
    else if command -sq podman
        set engine podman
    else
        printf 'ocd: neither docker nor podman found in PATH\n' 1>&2
        return 127
    end

    # Default includes registry so Podman won't rewrite to `localhost/...`.
    set -l image
    if set -q OCD_IMAGE; and test -n "$OCD_IMAGE"
        set image $OCD_IMAGE
    else
        set image docker.io/lnksz/ocd:latest
    end
    set -l pwd_real (pwd)

    # Linked worktrees refer to the main checkout's .git directory. Preserve
    # that reference inside the container without mounting its working tree.
    set -l external_git_dir
    if command -sq git; and git -C "$pwd_real" rev-parse --is-inside-work-tree >/dev/null 2>&1
        set external_git_dir (git -C "$pwd_real" rev-parse --git-common-dir 2>/dev/null)
        if test -n "$external_git_dir"
            set external_git_dir (readlink -f -- "$external_git_dir" 2>/dev/null)
        end
        if test "$external_git_dir" = "$pwd_real/.git"
            set external_git_dir
        end
    end

    # Host XDG paths with fallbacks
    set -l xdg_config (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo "$HOME/.config")
    set -l xdg_cache (set -q XDG_CACHE_HOME;  and echo $XDG_CACHE_HOME;  or echo "$HOME/.cache")
    set -l xdg_data (set -q XDG_DATA_HOME;   and echo $XDG_DATA_HOME;   or echo "$HOME/.local/share")

    set -l host_cfg "$xdg_config/opencode"
    mkdir -p "$host_cfg"

    set -l host_cache "$xdg_cache/opencode"
    mkdir -p "$host_cache"

    set -l host_data "$xdg_data/opencode"
    mkdir -p "$host_data"

    set -l default_cpu_percent 60
    set -l default_memory_percent 60

    set -l cpu_limit
    if set -q OCD_CPUS; and test -n "$OCD_CPUS"
        set cpu_limit $OCD_CPUS
    else
        set -l cpu_percent $default_cpu_percent
        if set -q OCD_CPU_PERCENT; and test -n "$OCD_CPU_PERCENT"
            set cpu_percent $OCD_CPU_PERCENT
        end

        if not string match -rq '^(100(\.0+)?|([1-9][0-9]?(\.[0-9]+)?)|(0\.[0-9]*[1-9][0-9]*))$' -- "$cpu_percent"
            printf 'ocd: OCD_CPU_PERCENT must be a number between 0 and 100\n' 1>&2
            return 1
        end

        set -l host_cpus (nproc)
        if not string match -rq '^[0-9]+$' -- "$host_cpus"
            printf 'ocd: failed to determine host CPU count\n' 1>&2
            return 1
        end

        set cpu_limit (math "$host_cpus * $cpu_percent / 100")
    end

    set -l memory_limit
    if set -q OCD_MEMORY; and test -n "$OCD_MEMORY"
        set memory_limit $OCD_MEMORY
    else
        set -l memory_percent $default_memory_percent
        if set -q OCD_MEMORY_PERCENT; and test -n "$OCD_MEMORY_PERCENT"
            set memory_percent $OCD_MEMORY_PERCENT
        end

        if not string match -rq '^(100(\.0+)?|([1-9][0-9]?(\.[0-9]+)?)|(0\.[0-9]*[1-9][0-9]*))$' -- "$memory_percent"
            printf 'ocd: OCD_MEMORY_PERCENT must be a number between 0 and 100\n' 1>&2
            return 1
        end

        if not read -l mem_label mem_total_kb mem_unit < /proc/meminfo
            printf 'ocd: failed to read /proc/meminfo\n' 1>&2
            return 1
        end

        if test "$mem_label" != 'MemTotal:'; or not string match -rq '^[0-9]+$' -- "$mem_total_kb"; or test "$mem_unit" != 'kB'
            printf 'ocd: failed to determine host memory size\n' 1>&2
            return 1
        end

        set memory_limit (math "floor($mem_total_kb * 1024 * $memory_percent / 100)")
    end

    set -l resource_flags \
        --cpus="$cpu_limit" \
        --memory="$memory_limit"

    set -l identity_flags --user 0:0
    if test "$engine" = podman
        set identity_flags $identity_flags --userns=keep-id
    end

    # If a previous container run created the SQLite DB as root (or otherwise non-writable),
    # OpenCode will fail with "attempt to write a readonly database".
    set -l host_db "$host_data/opencode.db"
    if test -e "$host_db"; and not test -w "$host_db"
        printf 'ocd: %s is not writable (fix ownership/permissions, e.g. sudo chown %s:%s %s*)\n' \
            "$host_db" (id -u) (id -g) "$host_db" 1>&2
        return 1
    end

    # Optional mounts for provider auth and extra OpenCode config.
    set -l extra_mounts
    if test -n "$external_git_dir"; and test -d "$external_git_dir"
        set extra_mounts $extra_mounts -v "$external_git_dir:$external_git_dir"
    end
    set -l mount_pairs \
        "$xdg_config/gh:/tmp/home/.config/gh" \
        "$xdg_cache/gh:/tmp/home/.cache/gh" \
        "$xdg_config/github-copilot:/tmp/home/.config/github-copilot" \
        "$xdg_cache/github-copilot:/tmp/home/.cache/github-copilot" \
        "$xdg_data/github-copilot:/tmp/home/.local/share/github-copilot" \
        "$xdg_config/opencode/commands:/tmp/home/.config/opencode/commands" \
        "$xdg_config/opencode/agents:/tmp/home/.config/opencode/agents" \
        "$xdg_config/opencode/skills:/tmp/home/.config/opencode/skills"

    for pair in $mount_pairs
        set -l parts (string split -m1 : -- $pair)
        set -l src $parts[1]
        if test -d "$src"
            set extra_mounts $extra_mounts -v $pair
        end
    end

    # Mount targets of symlinked config files because they may live outside
    # the host paths shared with the container.
    for cfg_file in "$host_cfg/AGENTS.md" "$host_cfg/opencode.json" "$host_cfg/opencode.jsonc"
        if test -L "$cfg_file"
            set -l cfg_target (readlink -f -- "$cfg_file" 2>/dev/null)
            if test -n "$cfg_target"
                set -l cfg_base (basename -- "$cfg_file")
                set extra_mounts $extra_mounts -v "$cfg_target:/tmp/home/.config/opencode/$cfg_base:ro"
            end
        end
    end

    # Pass environment file if present (KEY=value lines, # comments)
    set -l env_file
    if test -f "$host_cfg/config.env"
        set env_file --env-file "$host_cfg/config.env"
    end

    set -l terminal_flags
    if set -q TERM; and test -n "$TERM"
        set terminal_flags $terminal_flags -e "TERM=$TERM"
    end
    if set -q TERM_PROGRAM; and test -n "$TERM_PROGRAM"
        set terminal_flags $terminal_flags -e "TERM_PROGRAM=$TERM_PROGRAM"
    end
    if set -q COLORTERM; and test -n "$COLORTERM"
        set terminal_flags $terminal_flags -e "COLORTERM=$COLORTERM"
    end
    if set -q TERMINFO; and test -d "$TERMINFO"
        set terminal_flags $terminal_flags \
            -v "$TERMINFO:/tmp/host-terminfo:ro" \
            -e TERMINFO=/tmp/host-terminfo
    end

    set -l is_shell_mode 0
    set -l cmd
    set -l cmd_args
    if test (count $argv) -gt 0; and begin; test "$argv[1]" = "--shell"; or test "$argv[1]" = "-s"; end
        set is_shell_mode 1
        set cmd fish
        if test (count $argv) -gt 1
            set cmd_args $argv[2..-1]
        else
            set cmd_args
        end
    else
        set -l opencode_wrapper 'set -uo pipefail
trap : INT
opencode "$@"
exec fish'

        set cmd bash
        set cmd_args -c "$opencode_wrapper" ocd-opencode $argv
    end

    set -l override_mounts
    set -l tui_override_dir
    if test $is_shell_mode -eq 0
        set tui_override_dir (mktemp -d 2>/dev/null)
        if test -z "$tui_override_dir"
            printf 'ocd: failed to create temporary TUI config directory\n' 1>&2
            return 1
        end

        if not printf '%s\n' '{"keybinds":{"terminal_suspend":"none"}}' > "$tui_override_dir/tui.json"
            rm -rf "$tui_override_dir"
            printf 'ocd: failed to write temporary TUI config\n' 1>&2
            return 1
        end

        set override_mounts -v "$tui_override_dir/tui.json:/tmp/home/.config/opencode/tui.json:ro"
    end

    $engine run --rm -it \
        --init \
        $identity_flags \
        $resource_flags \
        $env_file \
        -e HOST_UID=(id -u) \
        -e HOST_GID=(id -g) \
        -e HOST_USER=(whoami) \
        -e HOME=/tmp/home \
        -e XDG_CONFIG_HOME=/tmp/home/.config \
        -e XDG_CACHE_HOME=/tmp/home/.cache \
        -e XDG_DATA_HOME=/tmp/home/.local/share \
        -w "$pwd_real" \
        -v "$pwd_real:$pwd_real" \
        -v "$host_cfg:/tmp/home/.config/opencode" \
        -v "$host_cache:/tmp/home/.cache/opencode" \
        -v "$host_data:/tmp/home/.local/share/opencode" \
        $extra_mounts \
        $override_mounts \
        $terminal_flags \
        $image \
        $cmd $cmd_args

    set -l exit_status $status
    if test -n "$tui_override_dir"; and test -d "$tui_override_dir"
        rm -rf "$tui_override_dir"
    end
    return $exit_status
end
