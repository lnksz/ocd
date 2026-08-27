# syntax=docker/dockerfile:1.6
FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NPM_CONFIG_PREFIX=/usr/local \
    PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/usr/local/bin \
    PIPX_DEFAULT_PYTHON=python3 \
    EDITOR=nvim

ARG NODE_VERSION=v24.16.0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---- Base + main tools + diagnostics + QoL ----
# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget openssl \
      git git-lfs openssh-client \
      bash fish sudo util-linux neovim \
      jq ripgrep fd-find fzf \
      unzip zip xz-utils \
      procps psmisc \
      build-essential pkg-config \
      python3 python3-pip python3-venv pipx \
      golang-go \
      \
      # C/C++ toolchain extras
      gdb lldb \
      cmake ninja-build ccache \
      clang clangd clang-format clang-tidy clang-tools \
      \
      # Shell/YAML/Dockerfile/Markdown helpers & linters
      shellcheck shfmt \
      yamllint \
      \
      # Bucket 4: search/indexing/introspection
      universal-ctags \
      tree \
      file \
      less \
      man-db \
      \
      # Bucket 5-ish: networking/diag
      dnsutils iproute2 netcat-openbsd lsof strace inotify-tools \
      \
      # Bucket 6: QoL
      bat git-delta eza tmux direnv \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && if command -v batcat >/dev/null 2>&1; then ln -sf "$(command -v batcat)" /usr/local/bin/bat; fi \
    && if command -v bat >/dev/null 2>&1; then ln -sf "$(command -v bat)" /usr/local/bin/bat; fi \
    && apt-get clean \
    && if ! id _apt >/dev/null 2>&1; then useradd -r -u 42 -d /nonexistent -s /usr/sbin/nologin _apt; fi \
    && printf 'ALL ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/99-nopasswd \
    && chmod 0440 /etc/sudoers.d/99-nopasswd \
    && visudo -cf /etc/sudoers

# ---- Node.js runtime ----
RUN set -euo pipefail; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) node_arch=x64 ;; \
        arm64) node_arch=arm64 ;; \
        *) echo "Unsupported arch for Node.js: $arch" >&2; exit 1 ;; \
    esac; \
    node_dist="node-${NODE_VERSION}-linux-${node_arch}"; \
    node_tarball="${node_dist}.tar.xz"; \
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${node_dist}.tar.xz" -o /tmp/node.tar.xz; \
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt" -o /tmp/SHASUMS256.txt; \
    expected_sha="$(grep " ${node_tarball}$" /tmp/SHASUMS256.txt | cut -d' ' -f1)"; \
    printf '%s  %s\n' "$expected_sha" /tmp/node.tar.xz | sha256sum -c -; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner; \
    rm -f /tmp/node.tar.xz /tmp/SHASUMS256.txt; \
    node --version; \
    npm --version

# Pre-create synthetic HOME so bind-mounts don't become root-owned.
# Docker creates missing mount targets as root:root, which breaks running with `--user`.
RUN mkdir -p /tmp/home/.config /tmp/home/.cache /tmp/home/.local/share \
    && chmod -R 0777 /tmp/home

# ---- hadolint (not always available in Ubuntu repos) ----
ARG HADOLINT_VERSION=v2.14.0
RUN set -euo pipefail; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) hadolint_arch=x86_64 ;; \
        arm64) hadolint_arch=arm64 ;; \
        *) echo "Unsupported arch for hadolint: $arch" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-${hadolint_arch}"; \
    curl -fL --retry 6 --retry-delay 2 --retry-all-errors "$url" -o /usr/local/bin/hadolint; \
    chmod +x /usr/local/bin/hadolint

# ---- GitLab CLI (latest release) ----
# Remote ADD makes the release metadata part of the cache key, so a new release
# invalidates this installation layer without pinning a version.
# hadolint ignore=DL3020
ADD https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/permalink/latest /tmp/glab-release.json
RUN set -euo pipefail; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64 | arm64) glab_arch="$arch" ;; \
        *) echo "Unsupported arch for GitLab CLI: $arch" >&2; exit 1 ;; \
    esac; \
    tag_name="$(jq -er '.tag_name | select(startswith("v"))' /tmp/glab-release.json)"; \
    version="${tag_name#v}"; \
    asset_name="glab_${version}_linux_${glab_arch}.tar.gz"; \
    asset_url="$(jq -er --arg name "$asset_name" '.assets.links[] | select(.name == $name) | .direct_asset_url' /tmp/glab-release.json)"; \
    checksums_url="$(jq -er '.assets.links[] | select(.name == "checksums.txt") | .direct_asset_url' /tmp/glab-release.json)"; \
    curl -fL --retry 6 --retry-delay 2 --retry-all-errors "$asset_url" -o "/tmp/${asset_name}"; \
    curl -fL --retry 6 --retry-delay 2 --retry-all-errors "$checksums_url" -o /tmp/checksums.txt; \
    expected_sha="$(grep "  ${asset_name}$" /tmp/checksums.txt | cut -d' ' -f1)"; \
    printf '%s  %s\n' "$expected_sha" "/tmp/${asset_name}" | sha256sum -c -; \
    tar -xzf "/tmp/${asset_name}" -C /usr/local/bin --strip-components=1 bin/glab; \
    chmod +x /usr/local/bin/glab; \
    glab version; \
    rm -f /tmp/glab-release.json "/tmp/${asset_name}" /tmp/checksums.txt

# ---- RTK (token-saving shell proxy for OpenCode) ----
ARG RTK_VERSION=v0.33.1
RUN set -euo pipefail; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) rtk_target=x86_64-unknown-linux-musl ;; \
        arm64) rtk_target=aarch64-unknown-linux-gnu ;; \
        *) echo "Unsupported arch for rtk: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fL --retry 6 --retry-delay 2 --retry-all-errors \
        "https://github.com/rtk-ai/rtk/releases/download/${RTK_VERSION}/rtk-${rtk_target}.tar.gz" \
        -o /tmp/rtk.tar.gz; \
    tar -xzf /tmp/rtk.tar.gz -C /usr/local/bin rtk; \
    chmod +x /usr/local/bin/rtk; \
    install -d /usr/local/share/rtk; \
    curl -fL --retry 6 --retry-delay 2 --retry-all-errors \
        "https://raw.githubusercontent.com/rtk-ai/rtk/${RTK_VERSION}/hooks/opencode-rtk.ts" \
        -o /usr/local/share/rtk/opencode-rtk.ts; \
    rm -f /tmp/rtk.tar.gz

# ---- opencode (adjust package name/version if needed) ----
ARG OPENCODE_PKG=opencode-ai
ARG OPENCODE_VERSION=latest
# hadolint ignore=DL3059
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g "${OPENCODE_PKG}@${OPENCODE_VERSION}" \
    && \
    # Install pnpm/yarn directly from npm to avoid corepack's extra Yarn registry lookup.
    npm install -g \
      pnpm@11.9.0 \
      @yarnpkg/cli-dist@4.17.0 \
      typescript@6.0.3 typescript-language-server@5.3.0 \
      vscode-langservers-extracted@4.10.0 \
      bash-language-server@5.6.0 \
      yaml-language-server@1.23.0 \
      dockerfile-language-server-nodejs@0.15.0 \
      @taplo/cli@0.7.0 \
      prettier@3.8.4 \
      eslint@10.5.0 \
      markdownlint-cli@0.49.0 \
      pyright@1.1.411 \
      \
      # Ansible LSP (see note below)
      @ansible/ansible-language-server@26.6.0

# NOTE: If @ansible/ansible-language-server ever fails to resolve on your system,
# replace it with a known working package name used in your environment.

# ---- Python toolchain + LSP + linters/formatters + Ansible ----
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    pipx install "python-lsp-server[all]==1.14.0" \
    && pipx install "ruff==0.15.20" \
    && pipx install "black==26.5.1" \
    && pipx install "isort==8.0.1" \
    && pipx install "mypy==2.1.0" \
    && pipx install "cmake-language-server==0.1.5" \
    && pipx install "ansible==14.1.0" \
    && pipx install "ansible-lint==26.4.0" \
    && pipx install "uv==0.11.24"

# ---- Go LSP + linters/formatters ----
ENV GOPATH=/opt/go
RUN --mount=type=cache,target=/root/.cache/go-build,sharing=locked \
    --mount=type=cache,target=/opt/go/pkg/mod,sharing=locked \
    mkdir -p "$GOPATH" \
    && /usr/bin/go install golang.org/x/tools/gopls@latest \
    && /usr/bin/go install golang.org/x/tools/cmd/goimports@latest \
    && /usr/bin/go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

ENV PATH="/opt/go/bin:${PATH}"

# ---- Entrypoint ----
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["fish"]
