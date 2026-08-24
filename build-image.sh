#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
	printf 'Usage: %s <agent-dir> [--push] [--no-cache] [version-or-dist-tag]\n' "${0##*/}"
}

if [[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	usage
	[[ $# -gt 0 ]] && exit 0
	exit 2
fi

target_arg="$1"
target_display="$target_arg"
shift
if [[ "$target_arg" != /* ]]; then
	target_arg="$repo_root/$target_arg"
fi
if ! target_dir="$(cd "$target_arg" 2>/dev/null && pwd)"; then
	printf 'Agent directory not found: %s\n' "$target_display" >&2
	exit 2
fi

case "$target_dir" in
"$repo_root/opencode")
	agent_name="OpenCode"
	pkg="${OPENCODE_PKG:-opencode-ai}"
	requested_version="${OPENCODE_VERSION:-latest}"
	pkg_build_arg_name="OPENCODE_PKG"
	build_arg_name="OPENCODE_VERSION"
	engine="${OCD_ENGINE:-${CONTAINER_ENGINE:-}}"
	image_repo="${OCD_IMAGE_REPO:-docker.io/lnksz/ocd}"
	push_default="${OCD_PUSH:-0}"
	image_title="lnksz/ocd"
	create_git_tag=1
	;;
"$repo_root/pi")
	agent_name="Pi"
	pkg="@earendil-works/pi-coding-agent"
	requested_version="${PI_CODING_AGENT_VERSION:-latest}"
	pkg_build_arg_name=""
	build_arg_name="PI_CODING_AGENT_VERSION"
	engine="${PID_ENGINE:-${CONTAINER_ENGINE:-}}"
	image_repo="${PID_IMAGE_REPO:-docker.io/lnksz/pid}"
	push_default="${PID_PUSH:-0}"
	image_title="lnksz/pid"
	create_git_tag=0
	;;
*)
	printf 'Unsupported agent directory: %s\n' "$target_dir" >&2
	printf 'Expected %s or %s\n' "$repo_root/opencode" "$repo_root/pi" >&2
	exit 2
	;;
esac

push_images="$push_default"
no_cache=0
version_set=0
for arg in "$@"; do
	case "$arg" in
	--push)
		push_images=1
		;;
	--no-cache)
		no_cache=1
		;;
	*)
		if [[ "$version_set" == "0" ]]; then
			requested_version="$arg"
			version_set=1
		else
			printf 'Unknown argument: %s\n' "$arg" >&2
			exit 2
		fi
		;;
	esac
done

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
build_options=()
if [[ "$no_cache" == "1" ]]; then
	build_options+=(--no-cache)
fi
build_args=(--build-arg "$build_arg_name=$resolved_version")
if [[ -n "$pkg_build_arg_name" ]]; then
	build_args+=(--build-arg "$pkg_build_arg_name=$pkg")
fi

printf 'Building %s (%s %s@%s -> %s)\n' \
	"$tag_version" "$agent_name" "$pkg" "$requested_version" "$resolved_version" >&2
"$engine" build \
	-f "$target_dir/Dockerfile" \
	"${build_options[@]}" \
	"${build_args[@]}" \
	--label "org.opencontainers.image.title=$image_title" \
	--label "org.opencontainers.image.version=$resolved_version" \
	-t "$tag_version" \
	-t "$tag_latest" \
	"$target_dir"

printf 'Tagged: %s and %s\n' "$tag_version" "$tag_latest" >&2
if [[ "$push_images" == "1" ]]; then
	printf 'Pushing: %s\n' "$tag_version" >&2
	"$engine" push "$tag_version"
	printf 'Pushing: %s\n' "$tag_latest" >&2
	"$engine" push "$tag_latest"
fi

if [[ "$create_git_tag" == "1" ]]; then
	current_branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
	if [[ "$current_branch" == "master" ]]; then
		tag_name="v${resolved_version}"
		if ! git -C "$repo_root" rev-parse --verify --quiet "$tag_name" >/dev/null; then
			printf 'Creating git tag %s...\n' "$tag_name" >&2
			git -C "$repo_root" tag "$tag_name"
			printf 'Pushing changes and tag %s to origin...\n' "$tag_name" >&2
			git -C "$repo_root" push origin "$current_branch"
			git -C "$repo_root" push origin "$tag_name"
		else
			printf 'Git tag %s already exists. Skipping tag creation.\n' "$tag_name" >&2
		fi
	fi
fi
