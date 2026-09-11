# syntax=docker/dockerfile:1.6
# Multi-platform upstream runtime, inspected with sbx 0.42.1.
ARG SANDBOX_TEMPLATE=docker.io/docker/sandbox-templates:opencode-docker@sha256:d23d51e1eaa7c23db723b3cd547fc998829b5c147579c512c7222efd30761fdd
FROM ${SANDBOX_TEMPLATE}

# The upstream runtime requires its named accounts.
# hadolint ignore=DL3066
USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    EDITOR=nvim \
    NPM_CONFIG_PREFIX=/usr/local \
    PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/usr/local/bin \
    PIPX_DEFAULT_PYTHON=python3

# The sandbox supplies Python, Go and its private Docker Engine.
# Add the ocd development toolbox without replacing sandbox runtime plumbing.
# hadolint ignore=DL3008
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl wget openssl git git-lfs openssh-client gh glab \
      bash fish sudo util-linux neovim jq ripgrep fd-find fzf \
      unzip zip xz-utils procps psmisc parallel build-essential pkg-config \
      python3 python3-pip python3-venv pipx golang-go \
      gdb lldb cmake ninja-build ccache clang clangd clang-format clang-tidy clang-tools \
      shellcheck shfmt yamllint universal-ctags tree file less man-db \
      dnsutils iproute2 netcat-openbsd lsof strace inotify-tools \
      bat git-delta eza tmux direnv \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG NODE_VERSION=v24.20.0
RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
      amd64) node_arch=x64 ;; \
      arm64) node_arch=arm64 ;; \
      *) exit 1 ;; \
    esac; \
    archive="node-${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${archive}" -o /tmp/node.tar.xz; \
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt" -o /tmp/SHASUMS256.txt; \
    expected_sha="$(grep " ${archive}$" /tmp/SHASUMS256.txt | cut -d' ' -f1)"; \
    printf '%s  %s\n' "$expected_sha" /tmp/node.tar.xz | sha256sum -c -; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner; \
    rm -f /tmp/node.tar.xz /tmp/SHASUMS256.txt

ARG HADOLINT_VERSION=v2.15.1
ARG PREK_VERSION=v0.5.2
ARG RTK_VERSION=v0.47.0
RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
      amd64) hadolint_arch=x86_64; target=x86_64-unknown-linux-gnu; rtk_target=x86_64-unknown-linux-musl ;; \
      arm64) hadolint_arch=arm64; target=aarch64-unknown-linux-gnu; rtk_target=aarch64-unknown-linux-gnu ;; \
      *) exit 1 ;; \
    esac; \
    curl -fL --retry 6 --retry-delay 2 --retry-all-errors \
      "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-linux-${hadolint_arch}" \
      -o /usr/local/bin/hadolint; \
    chmod +x /usr/local/bin/hadolint; \
    archive="prek-${target}.tar.gz"; \
    url="https://github.com/j178/prek/releases/download/${PREK_VERSION}/${archive}"; \
    curl -fL --retry 6 --retry-delay 2 --retry-all-errors "$url" -o "/tmp/${archive}"; \
    curl -fL --retry 6 --retry-delay 2 --retry-all-errors "${url}.sha256" -o /tmp/prek.sha256; \
    expected_sha="$(cut -d' ' -f1 /tmp/prek.sha256)"; \
    printf '%s  %s\n' "$expected_sha" "/tmp/${archive}" | sha256sum -c -; \
    tar -xzf "/tmp/${archive}" -C /usr/local/bin --strip-components=1 --no-same-owner; \
    curl -fL --retry 6 --retry-delay 2 --retry-all-errors \
      "https://github.com/rtk-ai/rtk/releases/download/${RTK_VERSION}/rtk-${rtk_target}.tar.gz" -o /tmp/rtk.tar.gz; \
    tar -xzf /tmp/rtk.tar.gz -C /usr/local/bin rtk; \
    chmod +x /usr/local/bin/rtk; \
    install -d /usr/local/share/rtk; \
    curl -fL --retry 6 --retry-delay 2 --retry-all-errors \
      "https://raw.githubusercontent.com/rtk-ai/rtk/${RTK_VERSION}/hooks/opencode/rtk.ts" \
      -o /usr/local/share/rtk/opencode-rtk.ts; \
    rm -f "/tmp/${archive}" /tmp/prek.sha256 /tmp/rtk.tar.gz

RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g \
      pnpm@11.25.0 @yarnpkg/cli-dist@4.18.0 \
      typescript@7.0.2 typescript-language-server@6.0.0 \
      vscode-langservers-extracted@4.10.0 bash-language-server@5.6.0 \
      yaml-language-server@1.24.0 dockerfile-language-server-nodejs@0.15.0 \
      @taplo/cli@0.7.0 hunkdiff@0.21.0 prettier@3.9.6 eslint@10.9.1 \
      markdownlint-cli@0.49.1 pyright@1.1.413 @ansible/ansible-language-server@26.6.0

RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    pipx install "python-lsp-server[all]==1.15.0" \
    && pipx install "ruff==0.16.5" \
    && pipx install "black==26.5.1" \
    && pipx install "isort==9.0.1" \
    && pipx install "mypy==2.3.1" \
    && pipx install "cmake-language-server==0.1.5" \
    && pipx install "ansible==14.3.1" \
    && pipx install "ansible-lint==26.8.0" \
    && pipx install --force "uv==0.12.9"

ENV GOPATH=/opt/go
RUN --mount=type=cache,target=/root/.cache/go-build,sharing=locked \
    --mount=type=cache,target=/opt/go/pkg/mod,sharing=locked \
    go install golang.org/x/tools/gopls@v0.23.0 \
    && go install golang.org/x/tools/cmd/goimports@v0.50.0 \
    && go install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.64.8
ENV PATH="/opt/go/bin:${PATH}"

# Replace the upstream npm installation in its existing prefix so the image
# PATH cannot select an older OpenCode. CI resolves latest to an exact version.
ARG OPENCODE_PKG=opencode-ai
ARG OPENCODE_VERSION=latest
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install -g --prefix /usr/local/share/npm-global \
      "${OPENCODE_PKG}@${OPENCODE_VERSION}" --include=optional

COPY --chmod=0755 session.sh /usr/local/bin/ox-session
COPY tui.json /usr/local/share/ox/tui.json

# Preserve the inherited entrypoint, command, labels and agent identity.
# hadolint ignore=DL3066
USER agent
