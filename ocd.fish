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

    # Host XDG paths with fallbacks
    set -l xdg_config (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo "$HOME/.config")
    set -l xdg_cache (set -q XDG_CACHE_HOME;  and echo $XDG_CACHE_HOME;  or echo "$HOME/.cache")
    set -l xdg_data (set -q XDG_DATA_HOME;   and echo $XDG_DATA_HOME;   or echo "$HOME/.local/share")

    # OpenCode host dirs (naming varies by version)
    set -l host_cfg
    for d in "$xdg_config/opencode" "$xdg_config/opencode-ai"
        if test -d "$d"
            set host_cfg "$d"
            break
        end
    end
    if test -z "$host_cfg"
        set host_cfg "$xdg_config/opencode"
        mkdir -p "$host_cfg"
    end

    set -l host_cache
    for d in "$xdg_cache/opencode" "$xdg_cache/opencode-ai"
        if test -d "$d"
            set host_cache "$d"
            break
        end
    end
    if test -z "$host_cache"
        set host_cache "$xdg_cache/opencode"
        mkdir -p "$host_cache"
    end

    set -l host_data
    for d in "$xdg_data/opencode" "$xdg_data/opencode-ai"
        if test -d "$d"
            set host_data "$d"
            break
        end
    end
    if test -z "$host_data"
        set host_data "$xdg_data/opencode"
        mkdir -p "$host_data"
    end

    # If a previous container run created the SQLite DB as root (or otherwise non-writable),
    # OpenCode will fail with "attempt to write a readonly database".
    set -l host_db "$host_data/opencode.db"
    if test -e "$host_db"; and not test -w "$host_db"
        printf 'ocd: %s is not writable (fix ownership/permissions, e.g. sudo chown %s:%s %s*)\n' \
            "$host_db" (id -u) (id -g) "$host_db" 1>&2
        return 1
    end

    # Optional auth mounts so providers (eg GitHub/Copilot) work inside the container.
    set -l extra_mounts
    set -l mount_pairs \
        "$xdg_config/gh:/tmp/home/.config/gh" \
        "$xdg_cache/gh:/tmp/home/.cache/gh" \
        "$xdg_config/github-copilot:/tmp/home/.config/github-copilot" \
        "$xdg_cache/github-copilot:/tmp/home/.cache/github-copilot" \
        "$xdg_data/github-copilot:/tmp/home/.local/share/github-copilot"

    for pair in $mount_pairs
        set -l parts (string split -m1 : -- $pair)
        set -l src $parts[1]
        if test -d "$src"
            set extra_mounts $extra_mounts -v $pair
        end
    end

    # If opencode.json/opencode.jsonc is a symlink, mount its target file over
    # the container config path (target may live outside the mounted tree).
    for cfg_file in "$host_cfg/opencode.json" "$host_cfg/opencode.jsonc"
        if test -L "$cfg_file"
            set -l cfg_target (readlink -f -- "$cfg_file" 2>/dev/null)
            if test -n "$cfg_target"
                set -l cfg_base (basename -- "$cfg_file")
                set extra_mounts $extra_mounts -v "$cfg_target:/tmp/home/.config/opencode/$cfg_base:ro"
                set extra_mounts $extra_mounts -v "$cfg_target:/tmp/home/.config/opencode-ai/$cfg_base:ro"
            end
        end
    end

    set -l stty_state (stty -g 2>/dev/null)
    set -l stty_state_status $status
    stty susp undef 2>/dev/null

    set -l cmd opencode-ai
    set -l cmd_args $argv
    if test (count $argv) -gt 0; and begin; test "$argv[1]" = "--shell"; or test "$argv[1]" = "-s"; end
        set cmd fish
        if test (count $argv) -gt 1
            set cmd_args $argv[2..-1]
        else
            set cmd_args
        end
    end

    $engine run --rm -it \
        --init \
        --user (id -u):(id -g) \
        -e HOST_USER=(whoami) \
        -e HOME=/tmp/home \
        -e XDG_CONFIG_HOME=/tmp/home/.config \
        -e XDG_CACHE_HOME=/tmp/home/.cache \
        -e XDG_DATA_HOME=/tmp/home/.local/share \
        -w "$pwd_real" \
        -v "$pwd_real:$pwd_real" \
        -v "$host_cfg:/tmp/home/.config/opencode" \
        -v "$host_cfg:/tmp/home/.config/opencode-ai" \
        -v "$host_cache:/tmp/home/.cache/opencode" \
        -v "$host_cache:/tmp/home/.cache/opencode-ai" \
        -v "$host_data:/tmp/home/.local/share/opencode" \
        -v "$host_data:/tmp/home/.local/share/opencode-ai" \
        $extra_mounts \
        $image \
        $cmd $cmd_args

    set -l exit_status $status
    if test $stty_state_status -eq 0; and test -n "$stty_state"
        stty "$stty_state" 2>/dev/null
    else
        stty sane 2>/dev/null
    end
    return $exit_status
end
