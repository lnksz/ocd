#!/usr/bin/env bash
set -euo pipefail

# The container is the execution boundary: disable Codex approvals and sandboxing.
exec /usr/local/bin/codex-native --yolo "$@"
