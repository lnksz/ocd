# syntax=docker/dockerfile:1.6
FROM ubuntu:25.10

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    NPM_CONFIG_PREFIX=/usr/local \
    PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/usr/local/bin \
    PIPX_DEFAULT_PYTHON=python3

# ---- Base + main tools + diagnostics + QoL ----
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget openssl \
      git git-lfs openssh-client \
      bash fish sudo \
      jq ripgrep fd-find fzf \
      unzip zip xz-utils \
      procps psmisc \
      build-essential pkg-config \
      python3 python3-pip python3-venv pipx \
      golang-go \
      nodejs npm \
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
      \
      # Bucket 7B: nss-wrapper for synthetic passwd/group
      libnss-wrapper \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && if command -v batcat >/dev/null 2>&1; then ln -sf "$(command -v batcat)" /usr/local/bin/bat; fi \
    && if command -v bat >/dev/null 2>&1; then ln -sf "$(command -v bat)" /usr/local/bin/bat; fi \
    && apt-get clean \
    && if ! id _apt >/dev/null 2>&1; then useradd -r -u 42 -d /nonexistent -s /usr/sbin/nologin _apt; fi \
    && printf 'Defaults env_keep += "NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP NSS_WRAPPER_SHADOW"\n' > /etc/sudoers.d/00-nss-wrapper \
    && printf 'Defaults pam_service=ocd-sudo\n' >> /etc/sudoers.d/00-nss-wrapper \
    && printf 'ALL ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/99-nopasswd \
    && chmod 0440 /etc/sudoers.d/00-nss-wrapper /etc/sudoers.d/99-nopasswd \
    && printf '%s\n' \
      '#%PAM-1.0' \
      '' \
      'auth    sufficient  pam_permit.so' \
      'account sufficient  pam_permit.so' \
      '' \
      'session required    pam_limits.so' \
      'session required    pam_env.so readenv=1 user_readenv=0' \
      'session required    pam_env.so readenv=1 envfile=/etc/default/locale user_readenv=0' \
      > /etc/pam.d/ocd-sudo \
    && multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH)" \
    && nss_lib="/lib/${multiarch}/libnss_wrapper.so" \
    && if [ -r "$nss_lib" ]; then printf '%s\n' "$nss_lib" > /etc/ld.so.preload; fi

# Pre-create synthetic HOME so bind-mounts don't become root-owned.
# Docker creates missing mount targets as root:root, which breaks running with `--user`.
RUN mkdir -p /tmp/home/.config /tmp/home/.cache /tmp/home/.local/share \
    && chmod -R 0777 /tmp/home

# ---- hadolint (not always available in Ubuntu repos) ----
ARG HADOLINT_VERSION=v2.12.0
RUN set -euo pipefail; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) hadolint_arch=x86_64 ;; \
        arm64) hadolint_arch=arm64 ;; \
        *) echo "Unsupported arch for hadolint: $arch" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-${hadolint_arch}"; \
    curl -fsSL "$url" -o /usr/local/bin/hadolint; \
    chmod +x /usr/local/bin/hadolint

# ---- opencode-ai (adjust package name/version if needed) ----
ARG OPENCODE_PKG=opencode-ai
ARG OPENCODE_VERSION=latest
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g "${OPENCODE_PKG}@${OPENCODE_VERSION}" \
    && if [ -x /usr/local/bin/opencode ] && [ ! -e /usr/local/bin/opencode-ai ]; then ln -s /usr/local/bin/opencode /usr/local/bin/opencode-ai; fi

# ---- Node toolchain + LSPs + linters ----
# corepack gives you pnpm/yarn in a versioned, reproducible way
RUN corepack enable \
    && corepack prepare pnpm@latest --activate \
    && corepack prepare yarn@stable --activate

RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g \
      typescript typescript-language-server \
      vscode-langservers-extracted \
      bash-language-server \
      yaml-language-server \
      dockerfile-language-server-nodejs \
      @taplo/cli \
      prettier \
      eslint \
      markdownlint-cli \
      pyright \
      \
      # Ansible LSP (see note below)
      @ansible/ansible-language-server

# NOTE: If @ansible/ansible-language-server ever fails to resolve on your system,
# replace it with a known working package name used in your environment.

# ---- Python toolchain + LSP + linters/formatters + Ansible ----
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    pipx install "python-lsp-server[all]" \
    && pipx install ruff \
    && pipx install black \
    && pipx install isort \
    && pipx install mypy \
    && pipx install cmake-language-server \
    && pipx install ansible \
    && pipx install ansible-lint \
    && pipx install uv

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
