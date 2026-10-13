#!/usr/bin/env bash
set -euo pipefail

mode="${1:---check}"
if [ "$#" -gt 1 ] || { [ "$mode" != --check ] && [ "$mode" != --install ]; }; then
    printf 'Usage: %s [--check|--install]\n' "$0" >&2
    exit 2
fi
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# This check runs before sudo, package managers, downloads, or any file writes.
if ! python3 -B "$script_dir/container.py"; then
    printf 'reverse-eng: refusing installation/setup outside a verified container.\n' >&2
    exit 1
fi
if [ "$mode" = --check ]; then
    printf 'reverse-eng: container verified. Use --install only when tools are needed.\n'
    exit 0
fi
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -n -- bash "$script_dir/install.sh" --install
fi

REA_VERSION=6.4.0
GHIDRA_VERSION=12.1.4
GHIDRA_BUILD_DATE=20260921
GHIDRA_SHA256=ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db
GHIDRA_MCP_VERSION=2.0
GHIDRA_MCP_SHA256=ebf904fd6782e429e95a60a24fe0724b20c0acb2dedb304135a5281f6b5f2e72
GHIDRA_MCP_REVISION=1e980252087b2479a21b9ca6d82d5829538651a7
GHIDRA_MCP_SOURCE_SHA256=bcea63344b900fc27db5347d8f34079cf2903b2f5a67582319b6eb5ff2f737e9
GHIDRA_MCP_PYTHON_VERSION=3.13.15

identity="rea=$REA_VERSION ghidra=$GHIDRA_VERSION ghidra-mcp=$GHIDRA_MCP_VERSION python=$GHIDRA_MCP_PYTHON_VERSION"
marker=/opt/reverse-eng/installed-version
if [ -f "$marker" ] && [ "$(cat "$marker")" = "$identity" ] && \
    [ -x /usr/local/bin/rea ] && [ -x /usr/local/bin/ghidra-mcp ] && \
    [ -x /opt/ghidra/support/analyzeHeadless ] && \
    [ -f /opt/ghidra/Ghidra/Extensions/GhidraMCP/lib/GhidraMCP.jar ]; then
    printf 'reverse-eng: requested tools are already installed.\n'
    exit 0
fi
# Never replace an existing unmanaged or partially installed toolchain.
for destination in /opt/ghidra /opt/ghidra-mcp /opt/ghidra-python /opt/ghidra-java \
    /usr/local/bin/rea /usr/local/bin/rea-native /usr/local/bin/ghidra-mcp \
    /usr/local/bin/ghidra /usr/local/bin/ghidra-headless \
    /usr/local/lib/node_modules/rea-agents; do
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        printf 'reverse-eng: existing %s; verify/reuse it before installing.\n' "$destination" >&2
        exit 1
    fi
done
command -v apt-get >/dev/null
command -v npm >/dev/null
command -v uv >/dev/null
# Keep installation and downloads in the container filesystem, outside the workspace.
mkdir -p /opt/reverse-eng
work="$(mktemp -d /opt/reverse-eng/downloads.XXXXXX)"
trap 'rm -rf "$work"' EXIT
export NPM_CONFIG_CACHE="$work/npm-cache"
apt-get update < /dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openjdk-21-jdk libfreetype6 fontconfig < /dev/null
apt-get clean
rm -rf /var/lib/apt/lists/*
export GHIDRA_INSTALL_DIR=/opt/ghidra JAVA_HOME=/opt/ghidra-java REA_ANALYSIS_PROVIDER=ghidra

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

npm install -g --ignore-scripts --cache "$work/npm-cache" "rea-agents@${REA_VERSION}"
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

printf "%s\n" "$identity" > "$marker"
printf "reverse-eng: installed and verified tools inside this container.\n"
