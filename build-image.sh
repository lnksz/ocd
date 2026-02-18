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

# Check if we should create a git tag and push changes
current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"

if [[ "$current_branch" == "master" ]]; then
	tag_name="v${resolved_version}"
	if ! git rev-parse --verify --quiet "$tag_name" >/dev/null; then
		printf 'Creating git tag %s...\n' "$tag_name" >&2
		git tag "$tag_name"

		printf 'Pushing changes and tag %s to origin...\n' "$tag_name" >&2
		git push origin "$current_branch"
		git push origin "$tag_name"
	else
		printf 'Git tag %s already exists. Skipping tag creation.\n' "$tag_name" >&2
	fi
fi
