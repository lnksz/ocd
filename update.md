# Component update command

Use this instruction for future dependency refreshes:

> Check all externally version-pinned components in `opencode/Dockerfile` and
> `pi/Dockerfile` against their official upstream releases. Update every newer,
> compatible stable pin, including Node.js, downloaded binaries, npm packages,
> and `pipx` packages. Keep shared pins aligned, preserve agent-specific pins,
> and leave intentionally dynamic `latest` installs unchanged. Do not change
> unpinned Ubuntu apt packages or unrelated configuration.
>
> Before editing, verify each proposed version exists and is compatible. For
> downloaded tools, verify the release asset names for both supported
> architectures, checksums where available, and every companion file fetched
> from the release tag. Check the tagged repository tree for raw-file paths;
> do not assume paths used by an older version still exist. Confirm package
> names and major-version compatibility before making an upgrade.
>
> Make minimal changes. Run `hadolint opencode/Dockerfile`, `hadolint
> pi/Dockerfile`, `shellcheck build-image.sh opencode/entrypoint.sh
> opencode/update-tools.sh pi/entrypoint.sh`, `fish -n opencode/ocd.fish
> pi/pid.fish`, and `git diff --check`. Then build both images with
> `docker build -f opencode/Dockerfile -t ocd:dev opencode` and `docker build
> -f pi/Dockerfile -t pid:dev pi`, followed by the documented startup smoke
> checks. Report sources checked, versions changed or already current, and all
> validation results, including any failed upstream asset or path check.
