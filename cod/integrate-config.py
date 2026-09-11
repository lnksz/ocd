#!/usr/bin/env python3
"""Expose OpenCode-led reusable instructions as ephemeral Codex user skills."""

import argparse
import hashlib
import json
import re
from pathlib import Path


def integrate(source: Path, shared: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    # OpenCode wins for the same directory name. Do not modify mounted sources.
    skills = {}
    for root in (shared, source / "skills"):
        if root.is_dir():
            skills.update((path.name, path) for path in sorted(root.iterdir()) if path.is_dir())
    for name, path in skills.items():
        target = destination / name
        if target.is_symlink():
            target.unlink()
        target.symlink_to(path.resolve(), target_is_directory=True)

    for category in ("commands", "agents"):
        root = source / category
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.md")):
            relative = path.relative_to(root).with_suffix("").as_posix()
            slug = re.sub(r"[^a-z0-9]+", "-", relative.lower()).strip("-") or "prompt"
            name = f"opencode-{category}-{slug}"
            # Keep names within the skill spec, and disambiguate flattened paths.
            if len(name) > 64 or (destination / name).exists():
                digest = hashlib.sha256(relative.encode()).hexdigest()[:10]
                name = f"{name[:53]}-{digest}"
            target = destination / name
            if target.exists():
                raise ValueError(f"Conflicting generated skill: {name}")
            target.mkdir()
            text = path.read_text(encoding="utf-8")
            # OpenCode's model/tool/mode frontmatter is not Codex skill metadata.
            text = re.sub(r"\A---\r?\n.*?\r?\n---(?:\r?\n|\Z)", "", text, count=1, flags=re.DOTALL)
            description = f"Use the OpenCode {category[:-1]} prompt {relative}. Invoke explicitly."
            (target / "SKILL.md").write_text(
                f"---\nname: {name}\ndescription: {json.dumps(description)}\n---\n\n"
                f"Source: {path}\n\n"
                "Apply the instructions below to the user's skill invocation. "
                "Interpret $ARGUMENTS and positional placeholders as the supplied "
                "arguments. OpenCode tool references describe intent; use equivalent "
                "Codex tools. Relative file references resolve from the source directory.\n\n"
                + text.lstrip(),
                encoding="utf-8",
            )
            (target / "agents").mkdir()
            (target / "agents/openai.yaml").write_text(
                "policy:\n  allow_implicit_invocation: false\n", encoding="utf-8"
            )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("/tmp/cod-opencode"))
    parser.add_argument("--shared", type=Path, default=Path("/tmp/cod-shared-skills"))
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()
    integrate(args.source, args.shared, args.destination)
