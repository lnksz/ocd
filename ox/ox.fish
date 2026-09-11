function ox --description "run OpenCode in a Docker Sandbox"
    set -l workspace (pwd -P)
    set -l digest (printf '%s' "$workspace" | sha256sum | string sub -l 16)
    set -l name "ox-$digest"

    # These wrapper options are recognized only in the first position.
    set -l mode opencode
    if set -q argv[1]
        switch "$argv[1]"
            case --sandbox-name
                printf '%s\n' "$name"
                return 0
            case --stop --rm --sync-sessions
                set mode (string sub -s 3 -- "$argv[1]")
                set -e argv[1]
            case --shell -s
                set mode shell
                set -e argv[1]
            case -c
                set argv[1] --continue
            case --
                set -e argv[1]
        end
    end

    if not command -sq sbx
        printf 'ox: install Docker Sandboxes (sbx >= 0.42.1) and run sbx login first; see ox/README.md\n' 1>&2
        return 127
    end
    if contains -- "$mode" stop rm sync-sessions
        if set -q argv[1]
            printf 'ox: --%s does not accept arguments\n' "$mode" 1>&2
            return 2
        end
        if test "$mode" != sync-sessions
            command sbx "$mode" "$name"
            return $status
        end
    end

    set -l image docker.io/lnksz/ox:latest
    if set -q OX_IMAGE; and test -n "$OX_IMAGE"
        set image "$OX_IMAGE"
    end
    set -l xdg_config "$HOME/.config"
    set -l xdg_cache "$HOME/.cache"
    set -l xdg_data "$HOME/.local/share"
    if set -q XDG_CONFIG_HOME; and test -n "$XDG_CONFIG_HOME"
        set xdg_config "$XDG_CONFIG_HOME"
    end
    if set -q XDG_CACHE_HOME; and test -n "$XDG_CACHE_HOME"
        set xdg_cache "$XDG_CACHE_HOME"
    end
    if set -q XDG_DATA_HOME; and test -n "$XDG_DATA_HOME"
        set xdg_data "$XDG_DATA_HOME"
    end
    set -l host_data "$xdg_data/opencode"
    set -l auth_seed "$xdg_data/ox/opencode-seed"
    mkdir -p "$xdg_config/opencode" "$auth_seed"; or return
    chmod 0700 "$auth_seed"; or return
    set -l host_cfg (path resolve "$xdg_config/opencode")
    set auth_seed (path resolve "$auth_seed")
    for file in auth.json account.json
        if test -f "$host_data/$file"
            set -l temporary "$auth_seed/.$file.$fish_pid"
            command install -m 0600 -- "$host_data/$file" "$temporary"; or return
            command mv -f -- "$temporary" "$auth_seed/$file"; or return
        else
            command rm -f -- "$auth_seed/$file"; or return
        end
    end

    # Keep SQLite and caches inside the VM. Cross-kernel WAL access over
    # virtiofs can expose incoherent database pages to concurrent processes.
    set -l mounts "$workspace" "$host_cfg" "$auth_seed:ro"
    set -l session_env -e "OX_HOST_CONFIG=$host_cfg" -e "OX_HOST_DATA_SEED=$auth_seed"
    set -l links
    for pair in config/gh cache/gh config/github-copilot cache/github-copilot data/github-copilot
        set -l parts (string split / -- "$pair")
        set -l root_var xdg_$parts[1]
        set -l src "$$root_var/$parts[2]"
        if test -d "$src"
            set src (path resolve "$src")
            set -a mounts "$src"
            set -a links "$pair" "$src"
        end
    end
    # Preserve external targets of the config links handled by ocd. sbx
    # workspace arguments must be directories, even for read-only shares.
    set -l config_file_targets
    for entry in AGENTS.md opencode.json opencode.jsonc commands agents skills
        set -l src "$host_cfg/$entry"
        if test -L "$src"
            set -l target (path resolve "$src")
            if test -f "$target"
                set -a config_file_targets "$target"
            else if test -d "$target"
                set -a mounts "$target"
            else
                printf 'ox: broken config symlink: %s\n' "$src" 1>&2
                return 1
            end
        end
    end
    if command -sq git; and git rev-parse --is-inside-work-tree >/dev/null 2>&1
        set -l common (git rev-parse --path-format=absolute --git-common-dir)
        set common (path resolve "$common")
        if test -d "$common"; and not string match -rq -- '^'(string escape --style=regex -- "$workspace")/ "$common"
            set -a mounts "$common"
        end
    end
    for variable in TERM TERM_PROGRAM COLORTERM
        if set -q $variable; and test -n "$$variable"
            set -a session_env -e "$variable=$$variable"
        end
    end
    if set -q TERMINFO; and test -d "$TERMINFO"
        set -l terminfo (path resolve "$TERMINFO")
        set -a mounts "$terminfo:ro"
        set -a session_env -e "TERMINFO=$terminfo"
    end
    if test -f "$host_cfg/config.env"
        set session_env --env-file "$host_cfg/config.env" $session_env
    end
    # Use the immediate containing directory for external files. Check all
    # directory shares first so a config link into the workspace or skills
    # does not accidentally turn an existing writable share read-only.
    for target in $config_file_targets
        set -l shared 0
        for mount in $mounts
            set -l root (string replace -r ':ro$' '' -- "$mount" | string trim -r -c /)
            if string match -rq -- '^'(string escape --style=regex -- "$root")/ "$target"
                set shared 1
                break
            end
        end
        if test $shared -eq 0
            set -a mounts (path dirname "$target"):ro
        end
    end
    set -l unique_mounts
    for mount in $mounts
        if not contains -- "$mount" $unique_mounts
            set -a unique_mounts "$mount"
        end
    end

    # A failed daemon/list request must not be mistaken for a missing sandbox.
    set -l sandboxes (command sbx ls -q)
    set -l list_status $status
    if test $list_status -ne 0
        return $list_status
    end
    if test "$mode" = sync-sessions
        if not contains -- "$name" $sandboxes
            printf 'ox: no sandbox exists for %s\n' "$workspace" 1>&2
            return 1
        end
        if not command -sq opencode
            printf 'ox: host opencode is required to import session snapshots\n' 1>&2
            return 127
        end
        set -l remote_dir /home/agent/.local/share/ox/session-exports
        set -l exports (command sbx exec "$name" bash -c \
            'for file in "$1"/*.json; do if test -f "$file"; then basename "$file"; fi; done' \
            ox-sync "$remote_dir")
        set -l export_status $status
        if test $export_status -ne 0
            return $export_status
        end
        if not set -q exports[1]
            printf 'ox: no completed session snapshots to sync\n'
            return 0
        end
        set -l temporary (mktemp -d); or return
        set -l sync_status 0
        for file in $exports
            if not string match -rq '^ses_[A-Za-z0-9_-]+(\.[a-f0-9]{64})?\.json$' -- "$file"
                printf 'ox: refusing unexpected snapshot name %s\n' "$file" 1>&2
                set sync_status 1
                continue
            end
            set -l local_file "$temporary/$file"
            if not command sbx cp "$name:$remote_dir/$file" "$local_file"
                set sync_status 1
                continue
            end
            if command opencode import "$local_file"
                command sbx exec "$name" rm -f -- "$remote_dir/$file"; or set sync_status 1
            else
                set sync_status 1
            end
        end
        command rm -rf -- "$temporary"
        return $sync_status
    end
    if not contains -- "$name" $sandboxes
        set -l cpus "$OX_CPUS"
        if test -z "$cpus"
            set -l percent 60
            if set -q OX_CPU_PERCENT; and test -n "$OX_CPU_PERCENT"
                set percent "$OX_CPU_PERCENT"
            end
            if not string match -rq '^(100(\.0+)?|[1-9][0-9]?(\.[0-9]+)?|0\.[0-9]*[1-9][0-9]*)$' -- "$percent"
                printf 'ox: OX_CPU_PERCENT must be a number between 0 and 100\n' 1>&2
                return 1
            end
            set cpus (math "max(1, floor("(nproc)" * $percent / 100))"); or return
        end
        if not string match -rq '^[1-9][0-9]*$' -- "$cpus"
            printf 'ox: OX_CPUS must be a positive whole number of vCPUs\n' 1>&2
            return 1
        end
        set -l memory "$OX_MEMORY"
        if test -z "$memory"
            set -l percent 60
            if set -q OX_MEMORY_PERCENT; and test -n "$OX_MEMORY_PERCENT"
                set percent "$OX_MEMORY_PERCENT"
            end
            if not string match -rq '^(100(\.0+)?|[1-9][0-9]?(\.[0-9]+)?|0\.[0-9]*[1-9][0-9]*)$' -- "$percent"
                printf 'ox: OX_MEMORY_PERCENT must be a number between 0 and 100\n' 1>&2
                return 1
            end
            read -l label total unit </proc/meminfo; or return
            if test "$label" != MemTotal:; or test "$unit" != kB; or not string match -rq '^[0-9]+$' -- "$total"
                printf 'ox: failed to determine host memory size\n' 1>&2
                return 1
            end
            set memory (math "floor($total * $percent / 100 / 1024)")m
        end
        command sbx create --name "$name" --template "$image" --cpus "$cpus" --memory "$memory" \
            opencode $unique_mounts; or return
    end

    # exec starts stopped sandboxes too. Non-interactive Bash loads the
    # template's BASH_ENV (/etc/sandbox-persistent.sh) without a login profile
    # resetting the image PATH that contains OpenCode and the development tools.
    command sbx exec -it --workdir "$workspace" $session_env "$name" \
        bash -c '
if [ "$(env -u OX_HOST_CONFIG /usr/local/bin/ox-session --runtime-version 2>/dev/null)" != 2 ]; then
    printf "ox: this sandbox has an outdated session launcher (private runtime v2 required).\n" >&2
    printf "ox: rebuild/load the template from this checkout, or refresh a published update:\n" >&2
    printf "    ox --rm\n    sbx template rm %q\n    ox\n" "$1" >&2
    printf "ox: recreating alone reuses the cached image; see ox/README.md, Apply a published update.\n" >&2
    exit 1
fi
shift
exec /usr/local/bin/ox-session "$@"
' ox-session "$image" $links -- "$mode" $argv
end
