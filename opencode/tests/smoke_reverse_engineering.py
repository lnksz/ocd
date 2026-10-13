#!/usr/bin/env python3
"""Verify installed REA and GhidraMCP against a native fixture, without credentials."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

CHECK = r'''
import asyncio
import json
import os
from pathlib import Path
import subprocess
from datetime import timedelta
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

assert os.getuid() != 0
assert Path(os.environ["GHIDRA_INSTALL_DIR"], "Ghidra/Extensions/GhidraMCP/lib/GhidraMCP.jar").is_file()
for name in ("reverse-engineer-anything", "ghidra-mcp"):
    assert Path("/usr/local/share/agent-skills", name, "SKILL.md").is_file()
assert Path("/usr/local/share/agent-skills/reverse-engineer-anything/references/connection-and-recovery.md").is_file()
root = Path.cwd()
(root / "sample.c").write_text("__attribute__((noinline)) int add_numbers(int a, int b) { return a+b; }\nint main(void) { return add_numbers(2, 3); }\n")
subprocess.run(["cc", "-g", "-O0", "-no-pie", "-o", "sample", "sample.c"], check=True)
# Use REA's Ghidra provider for actual decompilation, not just readiness.
address = next(line.split()[0] for line in subprocess.check_output(["nm", "sample"], text=True).splitlines() if line.endswith(" add_numbers"))
result = subprocess.run(["rea", "decompile", str(root / "sample"), "0x" + address, "--provider", "ghidra", "--json"], text=True, capture_output=True, timeout=180)
assert result.returncode == 0, (result.stdout, result.stderr)
data = json.loads(result.stdout)
assert "add_numbers" in json.dumps(data), data
print("REA Ghidra decompilation passed.")

async def verify_mcp():
    params = StdioServerParameters(command="ghidra-mcp", args=["--headless", "--binary", str(root / "sample"), "--ready-timeout", "120"])
    async with stdio_client(params) as (reader, writer):
        async with ClientSession(reader, writer, read_timeout_seconds=timedelta(seconds=180)) as session:
            await session.initialize()
            listing = await session.list_tools()
            assert {"list_functions", "decompile_function"} <= {tool.name for tool in listing.tools}
            result = await session.call_tool("decompile_function", {"name": "add_numbers"})
            assert not result.isError, result
            text = "".join(block.text for block in result.content if hasattr(block, "text"))
            assert "add_numbers" in text and "+" in text, text
            print("GhidraMCP stdio initialization and headless decompilation passed.")

asyncio.run(verify_mcp())
'''


def main():
    image = sys.argv[1] if len(sys.argv) > 1 else "ocd:dev"
    repository = Path(__file__).resolve().parents[2]
    (repository / "tmp").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="rea-smoke-", dir=repository / "tmp") as directory:
        uid, gid = os.getuid() or 12345, os.getgid() or 12345
        root = Path(directory)
        if os.getuid() == 0:
            os.chown(root, uid, gid)
        command = ["docker", "run", "--rm", "-i", "--init", "--cpus", "2", "--memory", "2g",
                   "--user", f"{uid}:{gid}", "--entrypoint", "/opt/ghidra-mcp/.venv/bin/python",
                   "-e", "HOME=/workspace/home", "-e", "GHIDRA_HEADLESS_MAXMEM=512M",
                   "-v", f"{root}:/workspace", "-w", "/workspace", image, "-"]
        (root / "home").mkdir()
        if os.getuid() == 0:
            os.chown(root / "home", uid, gid)
        subprocess.run(command, input=CHECK, text=True, check=True, timeout=360)


if __name__ == "__main__":
    main()
