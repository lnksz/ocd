#!/usr/bin/env bash
set -euo pipefail

# Build and tag lnksz/ocd to match the resolved OpenCode version.
#
# Usage:
#   ./build-image.sh [opencode_version_or_dist_tag]
#
# Examples:
#   ./build-image.sh latest
#   ./build-image.sh 0.7.3

pkg="${OPENCODE_PKG:-opencode-ai}"
requested_version="${1:-${OPENCODE_VERSION:-latest}}"

node_image="${NODE_IMAGE_FOR_NPM_VIEW:-node:20-bookworm-slim}"

resolved_version="$(
    docker run --rm "$node_image" \
        npm view "${pkg}@${requested_version}" version
)"

if [[ -z "$resolved_version" ]]; then
    printf 'Failed to resolve %s@%s\n' "$pkg" "$requested_version" >&2
    exit 1
fi

tag_version="lnksz/ocd:${resolved_version}"
tag_latest="lnksz/ocd:latest"

printf 'Building %s (OpenCode %s@%s -> %s)\n' "$tag_version" "$pkg" "$requested_version" "$resolved_version" >&2

docker build \
    --build-arg OPENCODE_PKG="$pkg" \
    --build-arg OPENCODE_VERSION="$resolved_version" \
    --label org.opencontainers.image.title="lnksz/ocd" \
    --label org.opencontainers.image.version="$resolved_version" \
    -t "$tag_version" \
    -t "$tag_latest" \
    .

printf 'Tagged: %s and %s\n' "$tag_version" "$tag_latest" >&2
