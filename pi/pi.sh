#!/usr/bin/env bash
set -euo pipefail

# Extra skill paths avoid writing to the persistent Pi or read-only shared config.
exec /usr/local/bin/pi-native \
    --skill /usr/local/share/agent-skills/reverse-engineer-anything \
    --skill /usr/local/share/agent-skills/ghidra-mcp "$@"
