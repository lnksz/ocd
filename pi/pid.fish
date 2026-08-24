function pid --description "run Pi coding agent in Docker/Podman"
    # Container engine and image override:
    # - `set -x PID_ENGINE podman|docker`
    # - `set -x PID_IMAGE docker.io/lnksz/pid:latest`
    set -l engine
    if set -q PID_ENGINE
        set engine $PID_ENGINE
    else if command -sq docker
        set engine docker
    else if command -sq podman
        set engine podman
    else
        printf 'pid: neither docker nor podman found in PATH\n' 1>&2
        return 127
    end

    # Default includes registry so Podman won't rewrite to `localhost/...`.
    set -l image
    if set -q PID_IMAGE; and test -n "$PID_IMAGE"
        set image $PID_IMAGE
    else
        set image docker.io/lnksz/pid:latest
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

    set -l host_cfg "$HOME/.pi/agent"
    mkdir -p "$host_cfg"

    set -l default_cpu_percent 60
    set -l default_memory_percent 60

    set -l cpu_limit
    if set -q PID_CPUS; and test -n "$PID_CPUS"
        set cpu_limit $PID_CPUS
    else
        set -l cpu_percent $default_cpu_percent
        if set -q PID_CPU_PERCENT; and test -n "$PID_CPU_PERCENT"
            set cpu_percent $PID_CPU_PERCENT
        end

        if not string match -rq '^(100(\.0+)?|([1-9][0-9]?(\.[0-9]+)?)|(0\.[0-9]*[1-9][0-9]*))$' -- "$cpu_percent"
            printf 'pid: PID_CPU_PERCENT must be a number between 0 and 100\n' 1>&2
            return 1
        end

        set -l host_cpus (nproc)
        if not string match -rq '^[0-9]+$' -- "$host_cpus"
            printf 'pid: failed to determine host CPU count\n' 1>&2
            return 1
        end

        set cpu_limit (math "$host_cpus * $cpu_percent / 100")
    end

    set -l memory_limit
    if set -q PID_MEMORY; and test -n "$PID_MEMORY"
        set memory_limit $PID_MEMORY
    else
        set -l memory_percent $default_memory_percent
        if set -q PID_MEMORY_PERCENT; and test -n "$PID_MEMORY_PERCENT"
            set memory_percent $PID_MEMORY_PERCENT
        end

        if not string match -rq '^(100(\.0+)?|([1-9][0-9]?(\.[0-9]+)?)|(0\.[0-9]*[1-9][0-9]*))$' -- "$memory_percent"
            printf 'pid: PID_MEMORY_PERCENT must be a number between 0 and 100\n' 1>&2
            return 1
        end

        if not read -l mem_label mem_total_kb mem_unit < /proc/meminfo
            printf 'pid: failed to read /proc/meminfo\n' 1>&2
            return 1
        end

        if test "$mem_label" != 'MemTotal:'; or not string match -rq '^[0-9]+$' -- "$mem_total_kb"; or test "$mem_unit" != 'kB'
            printf 'pid: failed to determine host memory size\n' 1>&2
            return 1
        end

        set memory_limit (math "floor($mem_total_kb * 1024 * $memory_percent / 100)")
    end

    set -l resource_flags \
        --cpus="$cpu_limit" \
        --memory="$memory_limit"

    # Optional mounts for provider auth and extra Pi config.
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
        "$HOME/.agents:/tmp/home/.agents" \
        "$xdg_config/opencode/skills:/tmp/home/.pi/agent/skills/opencode" \
        "$xdg_config/opencode/commands:/tmp/home/.pi/agent/prompts/opencode-commands" \
        "$xdg_config/opencode/agents:/tmp/home/.pi/agent/prompts/opencode-agents"

    for pair in $mount_pairs
        set -l parts (string split -m1 : -- $pair)
        set -l src $parts[1]
        if test -d "$src"
            set extra_mounts $extra_mounts -v $pair
        end
    end

    # Mount targets of symlinked config files because they may live outside
    # the host paths shared with the container.
    for cfg_file in "$host_cfg/AGENTS.md" "$host_cfg/settings.json" "$host_cfg/keybindings.json" "$host_cfg/models.json"
        if test -L "$cfg_file"
            set -l cfg_target (readlink -f -- "$cfg_file" 2>/dev/null)
            if test -n "$cfg_target"
                set -l cfg_base (basename -- "$cfg_file")
                set extra_mounts $extra_mounts -v "$cfg_target:/tmp/home/.pi/agent/$cfg_base:ro"
            end
        end
    end

    # Pass environment file if present (KEY=value lines, # comments)
    set -l env_file
    if test -f "$host_cfg/config.env"
        set env_file --env-file "$host_cfg/config.env"
    end

    set -l cmd
    set -l cmd_args
    if test (count $argv) -gt 0; and begin; test "$argv[1]" = "--shell"; or test "$argv[1]" = "-s"; end
        set cmd fish
        if test (count $argv) -gt 1
            set cmd_args $argv[2..-1]
        else
            set cmd_args
        end
    else
        set -l pi_wrapper 'set -uo pipefail
trap : INT
pi "$@"
exec fish'

        set cmd bash
        set cmd_args -c "$pi_wrapper" pid-pi $argv
    end

    $engine run --rm -it \
        --init \
        --user (id -u):(id -g) \
        $resource_flags \
        -e HOST_USER=(whoami) \
        -e HOME=/tmp/home \
        -e XDG_CONFIG_HOME=/tmp/home/.config \
        -e XDG_CACHE_HOME=/tmp/home/.cache \
        -e XDG_DATA_HOME=/tmp/home/.local/share \
        -e PI_CODING_AGENT_DIR=/tmp/home/.pi/agent \
        -w "$pwd_real" \
        -v "$pwd_real:$pwd_real" \
        -v "$host_cfg:/tmp/home/.pi/agent" \
        $extra_mounts \
        $env_file \
        $image \
        $cmd $cmd_args

end
