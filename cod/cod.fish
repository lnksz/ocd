function cod --description "run Codex in Docker/Podman"
    set -l engine
    if set -q COD_ENGINE
        set engine $COD_ENGINE
    else if command -sq docker
        set engine docker
    else if command -sq podman
        set engine podman
    else
        printf 'cod: neither docker nor podman found in PATH\n' 1>&2
        return 127
    end

    set -l image docker.io/lnksz/cod:latest
    if set -q COD_IMAGE; and test -n "$COD_IMAGE"
        set image $COD_IMAGE
    end
    set -l pwd_real (pwd)

    # Linked worktrees need the main checkout's Git metadata, not its files.
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

    set -l xdg_config (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo "$HOME/.config")
    set -l xdg_cache (set -q XDG_CACHE_HOME; and echo $XDG_CACHE_HOME; or echo "$HOME/.cache")
    set -l host_cfg "$HOME/.codex"
    if set -q CODEX_HOME; and test -n "$CODEX_HOME"
        set host_cfg $CODEX_HOME
    end
    mkdir -p "$host_cfg"; or return 1
    set host_cfg (realpath -- "$host_cfg")

    set -l cpu_limit
    if set -q COD_CPUS; and test -n "$COD_CPUS"
        set cpu_limit $COD_CPUS
    else
        set -l cpu_percent 60
        if set -q COD_CPU_PERCENT; and test -n "$COD_CPU_PERCENT"
            set cpu_percent $COD_CPU_PERCENT
        end
        if not string match -rq '^(100(\.0+)?|([1-9][0-9]?(\.[0-9]+)?)|(0\.[0-9]*[1-9][0-9]*))$' -- "$cpu_percent"
            printf 'cod: COD_CPU_PERCENT must be a number between 0 and 100\n' 1>&2
            return 1
        end
        set -l host_cpus (nproc)
        if not string match -rq '^[0-9]+$' -- "$host_cpus"
            printf 'cod: failed to determine host CPU count\n' 1>&2
            return 1
        end
        set cpu_limit (math "$host_cpus * $cpu_percent / 100")
    end

    set -l memory_limit
    if set -q COD_MEMORY; and test -n "$COD_MEMORY"
        set memory_limit $COD_MEMORY
    else
        set -l memory_percent 60
        if set -q COD_MEMORY_PERCENT; and test -n "$COD_MEMORY_PERCENT"
            set memory_percent $COD_MEMORY_PERCENT
        end
        if not string match -rq '^(100(\.0+)?|([1-9][0-9]?(\.[0-9]+)?)|(0\.[0-9]*[1-9][0-9]*))$' -- "$memory_percent"
            printf 'cod: COD_MEMORY_PERCENT must be a number between 0 and 100\n' 1>&2
            return 1
        end
        if not read -l mem_label mem_total_kb mem_unit < /proc/meminfo
            printf 'cod: failed to read /proc/meminfo\n' 1>&2
            return 1
        end
        if test "$mem_label" != 'MemTotal:'; or not string match -rq '^[0-9]+$' -- "$mem_total_kb"; or test "$mem_unit" != 'kB'
            printf 'cod: failed to determine host memory size\n' 1>&2
            return 1
        end
        set memory_limit (math "floor($mem_total_kb * 1024 * $memory_percent / 100)")
    end

    set -l identity_flags --user 0:0
    if test "$engine" = podman
        set identity_flags $identity_flags --userns=keep-id
    end

    set -l extra_mounts
    if test -n "$external_git_dir"; and test -d "$external_git_dir"
        set extra_mounts $extra_mounts -v "$external_git_dir:$external_git_dir"
    end
    # Source mounts stay read-only; the entrypoint assembles ephemeral skills.
    set -l mount_pairs \
        "$xdg_config/gh:/tmp/home/.config/gh" \
        "$xdg_cache/gh:/tmp/home/.cache/gh" \
        "$HOME/.agents/skills:/tmp/cod-shared-skills:ro" \
        "$xdg_config/opencode/skills:/tmp/cod-opencode/skills:ro" \
        "$xdg_config/opencode/commands:/tmp/cod-opencode/commands:ro" \
        "$xdg_config/opencode/agents:/tmp/cod-opencode/agents:ro"
    for pair in $mount_pairs
        set -l parts (string split -m1 : -- "$pair")
        if test -d "$parts[1]"
            set extra_mounts $extra_mounts -v "$pair"
            # Skill folders are often symlinks into a separate dotfiles checkout.
            if contains -- "$parts[2]" /tmp/cod-shared-skills:ro /tmp/cod-opencode/skills:ro
                set -l destination (string replace -r ':ro$' '' -- "$parts[2]")
                for skill in "$parts[1]"/*
                    if test -L "$skill"; and test -d "$skill"
                        set -l target (readlink -f -- "$skill")
                        set -l name (basename -- "$skill")
                        set extra_mounts $extra_mounts -v "$target:$destination/$name:ro"
                    end
                end
            end
        end
    end

    # Resolve symlinked native config/auth without mounting their parent folders.
    for name in config.toml auth.json AGENTS.md AGENTS.override.md
        if test "$name" = AGENTS.override.md; and test -f "$xdg_config/opencode/AGENTS.md"
            continue
        end
        if test -L "$host_cfg/$name"; and test -f "$host_cfg/$name"
            set -l target (readlink -f -- "$host_cfg/$name")
            set -l mode ro
            if test "$name" = auth.json
                set mode rw
            end
            set extra_mounts $extra_mounts -v "$target:/var/lib/codex/$name:$mode"
        end
    end
    # Codex gives AGENTS.override.md precedence over its own global AGENTS.md.
    if test -f "$xdg_config/opencode/AGENTS.md"
        set -l target (readlink -f -- "$xdg_config/opencode/AGENTS.md")
        set extra_mounts $extra_mounts -v "$target:/var/lib/codex/AGENTS.override.md:ro"
    end

    # Docker applies later env files last: OpenCode is the leading source.
    set -l env_flags
    for env_path in "$host_cfg/config.env" "$xdg_config/opencode/config.env"
        if test -f "$env_path"
            set env_flags $env_flags --env-file "$env_path"
        end
    end
    for name in TERM TERM_PROGRAM COLORTERM
        if set -q $name; and test -n "$$name"
            set env_flags $env_flags -e "$name=$$name"
        end
    end

    set -l cmd
    set -l cmd_args
    if test (count $argv) -gt 0; and contains -- "$argv[1]" --shell -s
        set cmd fish
        set cmd_args $argv[2..-1]
    else
        set -l codex_wrapper 'set -uo pipefail
trap : INT
codex "$@"
exec fish'
        set cmd bash
        set cmd_args -c "$codex_wrapper" cod-codex $argv
    end

    $engine run --rm -it --init \
        $identity_flags \
        --cpus="$cpu_limit" --memory="$memory_limit" \
        $env_flags \
        -e HOST_UID=(id -u) -e HOST_GID=(id -g) -e HOST_USER=(whoami) \
        -e HOME=/tmp/home \
        -e XDG_CONFIG_HOME=/tmp/home/.config \
        -e XDG_CACHE_HOME=/tmp/home/.cache \
        -e XDG_DATA_HOME=/tmp/home/.local/share \
        -e CODEX_HOME=/var/lib/codex \
        -w "$pwd_real" \
        -v "$pwd_real:$pwd_real" \
        -v "$host_cfg:/var/lib/codex" \
        $extra_mounts \
        $image $cmd $cmd_args
end
