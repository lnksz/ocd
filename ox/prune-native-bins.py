#!/usr/bin/env python3
"""Remove npm's unused platform packages after postinstall materializes the ELF bin."""
import json
from pathlib import Path
import re
import shutil
import sys


PREFIXES = {
    "@ast-grep/cli": "@ast-grep/cli-",
    "@opencode/cli": "@opencode/cli-",
    "opencode-ai": "opencode-",
}


def prune(package):
    package = Path(package).resolve(strict=True)
    metadata = json.loads((package / "package.json").read_text())
    prefix = PREFIXES.get(metadata["name"])
    if prefix is None:
        raise ValueError("unsupported package")
    bins = metadata.get("bin")
    if isinstance(bins, str):
        bins = {metadata["name"]: bins}
    if not isinstance(bins, dict) or not bins:
        raise ValueError("package has no executable entry points")

    # Validate every entry point before deleting anything. JS launchers may
    # still need platform packages; a symlink may still target one of them.
    executables = []
    for relative in bins.values():
        binary = (package / relative).resolve(strict=True)
        if not binary.is_relative_to(package):
            raise ValueError("executable escapes package directory")
        with binary.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                raise ValueError(f"entry point is not a native ELF binary: {relative}")
        executables.append(binary)

    removable = []
    for name in metadata.get("optionalDependencies", {}):
        if not name.startswith(prefix) or not re.fullmatch(r"[a-z0-9-]+", name[len(prefix):]):
            continue
        dependency = package / "node_modules" / name
        if not dependency.exists() and not dependency.is_symlink():
            continue
        if dependency.is_symlink() or not dependency.resolve().is_relative_to(package):
            raise ValueError(f"unexpected platform package path: {name}")
        if not any(binary.is_relative_to(dependency.resolve()) for binary in executables):
            removable.append(dependency)
    for dependency in removable:
        shutil.rmtree(dependency)
    print(f"{metadata['name']}: kept native entry points; removed {len(removable)} platform packages")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: prune-native-bins.py PACKAGE_DIRECTORY")
    try:
        prune(sys.argv[1])
    except (OSError, ValueError, KeyError) as error:
        sys.exit(f"native binary cleanup refused: {error}")
