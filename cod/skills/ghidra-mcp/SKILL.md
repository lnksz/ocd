---
name: ghidra-mcp
description: Analyze, decompile, rename, and annotate native binaries using the installed Ghidra 12.1.4 and LaurieWired GhidraMCP 2.0, including headless analysis and persistent Ghidra projects.
---

# Ghidra MCP in these containers

`ghidra-mcp` runs in its own Python 3.13 environment. `GHIDRA_INSTALL_DIR`
points to `/opt/ghidra`; Java 21 and the matching GhidraMCP extension are installed.
Use the installed command directly; no uvx downloads or plugin builds are needed.

For native investigation through the REA CLI, use `rea --help` and select the
Ghidra provider (`--provider ghidra`). REA owns a separate temporary, read-only
analysis project. It does not use the GhidraMCP server or an existing Ghidra project.

For Ghidra MCP tools without a GUI, launch a stdio server for the chosen binary:

```bash
ghidra-mcp --headless --binary /absolute/path/to/target
```

Temporary projects discard modifications on exit. To retain renames, types,
comments, or patches, add `--project /workspace/ghidra-projects`; changes save
on exit unless `--discard` is supplied. Bind the server to the actual requested
binary and use its advertised tools and schemas. Loading a large binary can
need `--ready-timeout 300` or longer.

The GUI launcher is `ghidra`; it needs an available graphical display. To attach
to a GUI with the plugin enabled, use `ghidra-mcp --ghidra-server URL`.
Use `ghidra-mcp --help` for transport and project options. HTTP transports bind
loopback by default; stdio needs no published container ports.

The CLI installation and skill do not register MCP in a running agent. Register
`rea mcp` or the chosen `ghidra-mcp` command in the agent's MCP configuration
when MCP tools are requested. Some configuration directories are host mounts;
inspect the destination before applying a registration. Shell use needs no registration.
