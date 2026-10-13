#!/usr/bin/env python3
"""Fail closed unless the current environment has positive container evidence."""
from pathlib import Path
import subprocess
import sys


CONTAINER_TYPES = {"docker", "podman", "lxc", "lxc-libvirt", "systemd-nspawn", "rkt"}


def is_container(root=Path("/")):
    for name in (".dockerenv", "run/.containerenv"):
        marker = root / name
        if marker.is_file() and not marker.is_symlink():
            return True
    marker = root / "run/systemd/container"
    try:
        if not marker.is_symlink() and marker.read_text().strip() in CONTAINER_TYPES:
            return True
    except OSError:
        pass
    try:
        result = subprocess.run(
            ["systemd-detect-virt", "--container"],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, timeout=5, check=False,
        )
        return result.returncode == 0 and result.stdout.strip() in CONTAINER_TYPES
    except (OSError, subprocess.TimeoutExpired):
        return False


if __name__ == "__main__":
    sys.exit(0 if is_container() else 1)
