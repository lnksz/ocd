#!/usr/bin/env bash
set -euo pipefail

# Build and tag lnksz/ocd to match the resolved OpenCode version.
#
# Container engine:
# - Auto-detects `docker`, then `podman`.
# - Override with `OCD_ENGINE=docker|podman`.
#
# Image name:
# - Defaults to Docker Hub (`docker.io/lnksz/ocd`) so Podman won't rewrite to `localhost/...`.
# - Override with `OCD_IMAGE_REPO=registry.example.com/namespace/ocd`.
#
# Usage:
#   ./build-image.sh [--push] [--no-cache] [opencode_version_or_dist_tag]
#
# Examples:
#   ./build-image.sh latest
#   ./build-image.sh 0.7.3
#   ./build-image.sh --push latest
#   ./build-image.sh --no-cache latest

pkg="${OPENCODE_PKG:-opencode-ai}"

push_images=0
no_cache=0
requested_version=""

for arg in "$@"; do
	case "$arg" in
	--push)
		push_images=1
		;;
	--no-cache)
		no_cache=1
		;;
	*)
		if [[ -z "$requested_version" ]]; then
			requested_version="$arg"
		else
			printf 'Unknown argument: %s\n' "$arg" >&2
			exit 2
		fi
		;;
	esac
done

requested_version="${requested_version:-${OPENCODE_VERSION:-latest}}"

engine="${OCD_ENGINE:-${CONTAINER_ENGINE:-}}"
if [[ -z "$engine" ]]; then
	if command -v docker >/dev/null 2>&1; then
		engine="docker"
	elif command -v podman >/dev/null 2>&1; then
		engine="podman"
	else
		printf 'Neither docker nor podman found in PATH\n' >&2
		exit 127
	fi
fi

image_repo="${OCD_IMAGE_REPO:-docker.io/lnksz/ocd}"

node_image="${NODE_IMAGE_FOR_NPM_VIEW:-docker.io/library/node:20-bookworm-slim}"

resolved_version="$(
	"$engine" run --rm "$node_image" \
		npm view "${pkg}@${requested_version}" version
)"

if [[ -z "$resolved_version" ]]; then
	printf 'Failed to resolve %s@%s\n' "$pkg" "$requested_version" >&2
	exit 1
fi

tag_version="${image_repo}:${resolved_version}"
tag_latest="${image_repo}:latest"

printf 'Building %s (OpenCode %s@%s -> %s)\n' "$tag_version" "$pkg" "$requested_version" "$resolved_version" >&2

"$engine" build \
	${no_cache:+--no-cache} \
	--build-arg OPENCODE_PKG="$pkg" \
	--build-arg OPENCODE_VERSION="$resolved_version" \
	--label org.opencontainers.image.title="lnksz/ocd" \
	--label org.opencontainers.image.version="$resolved_version" \
	-t "$tag_version" \
	-t "$tag_latest" \
	.

printf 'Tagged: %s and %s\n' "$tag_version" "$tag_latest" >&2

if [[ "$push_images" == "1" || "${OCD_PUSH:-0}" == "1" ]]; then
	printf 'Pushing: %s\n' "$tag_version" >&2
	"$engine" push "$tag_version"
	printf 'Pushing: %s\n' "$tag_latest" >&2
	"$engine" push "$tag_latest"
fi

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
