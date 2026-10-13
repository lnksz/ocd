#!/usr/bin/env bash
set -euo pipefail

# Each image owns this installer because Docker build contexts are independent.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fetch() {
    curl -fL --retry 6 --retry-delay 2 --retry-all-errors "$1" -o "$2"
    printf '%s  %s\n' "$3" "$2" | sha256sum -c -
}

fetch "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_BUILD_DATE}.zip" \
    "$work/ghidra.zip" "$GHIDRA_SHA256"
unzip -q "$work/ghidra.zip" -d "$work"
mv "$work/ghidra_${GHIDRA_VERSION}_PUBLIC" /opt/ghidra
# The upstream ZIP ships Linux x86_64 natives only. Preserve arm64 images by
# building the native decompiler from the same pinned release sources.
case "$(dpkg --print-architecture)" in
    amd64) native_platform=linux_x86_64 ;;
    arm64)
        native_platform=linux_arm_64
        make -C /opt/ghidra/Ghidra/Features/Decompiler/src/decompile/cpp -j2 \
            ghidra_opt ARCH_TYPE= OSDIR="$native_platform"
        install -D -m 0755 /opt/ghidra/Ghidra/Features/Decompiler/src/decompile/cpp/ghidra_opt \
            "/opt/ghidra/Ghidra/Features/Decompiler/os/$native_platform/decompile"
        make -C /opt/ghidra/Ghidra/Features/Decompiler/src/decompile/cpp clean
        ;;
    *) printf 'Unsupported Ghidra architecture\n' >&2; exit 1 ;;
esac
test -x "/opt/ghidra/Ghidra/Features/Decompiler/os/$native_platform/decompile"

fetch "https://github.com/LaurieWired/GhidraMCP/releases/download/${GHIDRA_MCP_VERSION}/GhidraMCP-release-${GHIDRA_MCP_VERSION//./-}.zip" \
    "$work/mcp.zip" "$GHIDRA_MCP_SHA256"
unzip -q "$work/mcp.zip" -d "$work/release"
# The release archive wraps the actual Ghidra extension ZIP.
unzip -q "$work"/release/*/ghidra_*_GhidraMCP.zip -d /opt/ghidra/Ghidra/Extensions

fetch "https://codeload.github.com/LaurieWired/GhidraMCP/tar.gz/${GHIDRA_MCP_REVISION}" \
    "$work/mcp-source.tar.gz" "$GHIDRA_MCP_SOURCE_SHA256"
mkdir -p /opt/ghidra-mcp
tar -xzf "$work/mcp-source.tar.gz" -C /opt/ghidra-mcp --strip-components=1 --no-same-owner
# JPype/PyGhidra headless support needs Python <=3.13, independently of system Python.
UV_PYTHON_INSTALL_DIR=/opt/ghidra-python uv sync --directory /opt/ghidra-mcp \
    --frozen --no-dev --extra headless --python "$GHIDRA_MCP_PYTHON_VERSION" --no-cache
chmod -R a+rX /opt/ghidra-python /opt/ghidra-mcp
# Some stdio MCP clients pass only HOME/PATH. Keep provider defaults at the
# executable boundary too, while honoring explicit environment overrides.
cat > /usr/local/bin/ghidra-mcp <<'SH'
#!/usr/bin/env bash
set -euo pipefail
export GHIDRA_INSTALL_DIR="${GHIDRA_INSTALL_DIR:-/opt/ghidra}"
export JAVA_HOME="${JAVA_HOME:-/opt/ghidra-java}"
exec /opt/ghidra-mcp/.venv/bin/ghidra-mcp "$@"
SH
chmod 0755 /usr/local/bin/ghidra-mcp
ln -s "/usr/lib/jvm/java-21-openjdk-$(dpkg --print-architecture)" /opt/ghidra-java
ln -s /opt/ghidra/ghidraRun /usr/local/bin/ghidra
ln -s /opt/ghidra/support/analyzeHeadless /usr/local/bin/ghidra-headless

npm install -g --ignore-scripts "rea-agents@${REA_VERSION}"
mv /usr/local/bin/rea /usr/local/bin/rea-native
cat > /usr/local/bin/rea <<'SH'
#!/usr/bin/env bash
set -euo pipefail
export GHIDRA_INSTALL_DIR="${GHIDRA_INSTALL_DIR:-/opt/ghidra}"
export JAVA_HOME="${JAVA_HOME:-/opt/ghidra-java}"
export REA_ANALYSIS_PROVIDER="${REA_ANALYSIS_PROVIDER:-ghidra}"
exec /usr/local/bin/rea-native "$@"
SH
chmod 0755 /usr/local/bin/rea
install -d /usr/local/share/agent-skills
cp -a "$(npm root -g)/rea-agents/skills/reverse-engineer-anything" /usr/local/share/agent-skills/
rea --version
ghidra-mcp --help >/dev/null
/opt/ghidra-mcp/.venv/bin/python -c 'import ghidra_mcp, pyghidra, mcp'
