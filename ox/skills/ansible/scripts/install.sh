#!/usr/bin/env bash
set -euo pipefail

mode="${1:---check}"
if [ "$#" -gt 1 ] || { [ "$mode" != --check ] && [ "$mode" != --install ]; }; then
    printf 'Usage: %s [--check|--install]\n' "$0" >&2
    exit 2
fi
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# Refuse before sudo, package managers, or any filesystem writes.
if ! python3 -B "$script_dir/container.py"; then
    printf 'ansible: refusing installation/setup outside a verified container.\n' >&2
    exit 1
fi
if [ "$mode" = --check ]; then
    printf 'ansible: container verified. Use --install only when tools are needed.\n'
    exit 0
fi
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -n -- bash "$script_dir/install.sh" --install
fi

ANSIBLE_VERSION=14.5.0
ANSIBLE_LINT_VERSION=26.10.0
ANSIBLE_LSP_VERSION=26.6.0
identity="ansible=$ANSIBLE_VERSION lint=$ANSIBLE_LINT_VERSION lsp=$ANSIBLE_LSP_VERSION"
marker=/opt/ansible-tools/installed-version
if [ -f "$marker" ] && [ "$(cat "$marker")" = "$identity" ] && \
    [ -x /usr/local/bin/ansible ] && [ -x /usr/local/bin/ansible-playbook ] && \
    [ -x /usr/local/bin/ansible-lint ] && [ -x /usr/local/bin/ansible-language-server ]; then
    printf 'ansible: requested tools are already installed.\n'
    exit 0
fi
# Do not overwrite unrelated installations or an incomplete installation.
for destination in /opt/ansible-tools /usr/local/bin/ansible /usr/local/bin/ansible-playbook \
    /usr/local/bin/ansible-community /usr/local/bin/ansible-lint \
    /usr/local/bin/ansible-language-server /usr/local/lib/node_modules/@ansible/ansible-language-server; do
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        printf 'ansible: existing %s; verify/reuse it before installing.\n' "$destination" >&2
        exit 1
    fi
done
command -v pipx >/dev/null
command -v npm >/dev/null
mkdir -p /opt/ansible-tools
work="$(mktemp -d /opt/ansible-tools/downloads.XXXXXX)"
trap 'rm -rf "$work"' EXIT
export PIPX_HOME=/opt/ansible-tools/pipx PIPX_BIN_DIR=/usr/local/bin PIPX_DEFAULT_PYTHON=/usr/bin/python3
export PIPX_LOG_DIR="$work/pipx-logs" PIPX_VENV_CACHEDIR="$work/pipx-cache"
export PIPX_STANDALONE_PYTHON_CACHEDIR="$work/pipx-python" PIP_CACHE_DIR="$work/pip-cache"
export NPM_CONFIG_PREFIX=/usr/local NPM_CONFIG_CACHE="$work/npm-cache"
pipx install --include-deps "ansible==$ANSIBLE_VERSION" < /dev/null
pipx install "ansible-lint==$ANSIBLE_LINT_VERSION" < /dev/null
npm install -g "@ansible/ansible-language-server@$ANSIBLE_LSP_VERSION" < /dev/null
ansible --version
ansible-playbook --version
ansible-lint --version
ansible-language-server --version
printf '%s\n' "$identity" > "$marker"
