function ocd --description "run OpenCode in Docker"
    # Override with `set -x OCD_IMAGE yourtag`.
    set -l image (set -q OCD_IMAGE; and echo $OCD_IMAGE; or echo "lnksz/ocd:latest")
    set -l pwd_real (pwd)

    # Host XDG paths with fallbacks
    set -l xdg_config (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo "$HOME/.config")
    set -l xdg_cache  (set -q XDG_CACHE_HOME;  and echo $XDG_CACHE_HOME;  or echo "$HOME/.cache")
    set -l xdg_data   (set -q XDG_DATA_HOME;   and echo $XDG_DATA_HOME;   or echo "$HOME/.local/share")

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

    docker run --rm -it \
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
        -v "$host_cache:/tmp/home/.cache/opencode" \
        -v "$host_data:/tmp/home/.local/share/opencode" \
        $extra_mounts \
        $image \
        opencode-ai $argv
end
