# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/alinux3:latest

FROM ${BASE_IMAGE} AS minimal

ARG TARGETARCH
ARG NODE_MAJOR=20
ARG NVIM_VERSION=0.11.3
ARG STARSHIP_VERSION=1.25.1
ARG ZOXIDE_VERSION=0.9.9
ARG FZF_VERSION=0.72.0

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEV_HOME=/home/admin \
    PATH=/usr/local/bin:/home/admin/.local/bin:$PATH

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eux; \
    if command -v dnf >/dev/null 2>&1; then PM=dnf; else PM=yum; fi; \
    "$PM" install -y \
      bash zsh sudo git curl wget jq ca-certificates \
      tar gzip unzip zip xz findutils gawk grep sed which less \
      procps-ng shadow-utils util-linux openssh-clients \
      vim-enhanced tmux make gcc gcc-c++; \
    "$PM" clean all

RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
      amd64) NVIM_ARCH=x86_64; STARSHIP_ARCH=x86_64; ZOXIDE_ARCH=x86_64-unknown-linux-musl; FZF_ARCH=linux_amd64 ;; \
      arm64) NVIM_ARCH=arm64; STARSHIP_ARCH=aarch64; ZOXIDE_ARCH=aarch64-unknown-linux-musl; FZF_ARCH=linux_arm64 ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-${NVIM_ARCH}.tar.gz" -o /tmp/nvim.tar.gz; \
    tar -xzf /tmp/nvim.tar.gz -C /opt; \
    ln -sf "/opt/nvim-linux-${NVIM_ARCH}/bin/nvim" /usr/local/bin/nvim; \
    curl -fsSL "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${STARSHIP_VERSION}-${STARSHIP_ARCH}-unknown-linux-gnu.tar.gz" -o /tmp/starship.tar.gz; \
    tar -xzf /tmp/starship.tar.gz -C /usr/local/bin starship; \
    curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-${ZOXIDE_ARCH}.tar.gz" -o /tmp/zoxide.tar.gz; \
    tar -xzf /tmp/zoxide.tar.gz -C /usr/local/bin zoxide; \
    curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-${FZF_ARCH}.tar.gz" -o /tmp/fzf.tar.gz; \
    tar -xzf /tmp/fzf.tar.gz -C /usr/local/bin fzf; \
    rm -rf /tmp/*.tar.gz /opt/nvim-linux-*/share/man

RUN git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git /usr/local/share/zsh/plugins/zsh-autosuggestions \
 && git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git /usr/local/share/zsh/plugins/zsh-syntax-highlighting

RUN set -eux; \
    groupadd --gid 1000 admin; \
    useradd --uid 1000 --gid 1000 --create-home --shell /bin/zsh admin; \
    echo 'admin ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/admin; \
    chmod 0440 /etc/sudoers.d/admin; \
    mkdir -p /etc/devtools/templates /etc/profile.d /workspace; \
    chown admin:admin /home/admin /workspace

COPY containers/alinux3/skel/profile.sh /etc/profile.d/devtools.sh
COPY containers/alinux3/skel/bashrc /etc/skel/.bashrc
COPY containers/alinux3/skel/zshrc /etc/skel/.zshrc
COPY containers/alinux3/skel/gitconfig /etc/skel/.gitconfig
COPY terminal/vim/vimrc /etc/skel/.vimrc
COPY terminal/nvim /etc/skel/.config/nvim
COPY terminal/starship/starship-tokyo-linux.toml /etc/skel/.config/starship.toml
COPY terminal/tmux/tmux.conf /etc/skel/.tmux.conf
COPY vcs/git/bin/ /usr/local/bin/
COPY agent/claude/config/ /etc/devtools/templates/claude/
COPY agent/codex/config/ /etc/devtools/templates/codex/
COPY agent/cursor-agent/config/ /etc/devtools/templates/cursor-agent/
COPY containers/alinux3/user-sync.sh /usr/local/bin/devtools-user-sync
COPY containers/alinux3/config-sync.sh /usr/local/bin/devtools-config-sync
COPY containers/alinux3/entrypoint.sh /usr/local/bin/devtools-entrypoint

RUN chmod +x /usr/local/bin/devtools-user-sync /usr/local/bin/devtools-config-sync /usr/local/bin/devtools-entrypoint /usr/local/bin/git-* \
 && cp -a /etc/skel/. /home/admin/ \
 && chown -R admin:admin /home/admin

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/devtools-entrypoint"]
CMD ["zsh", "-l"]

FROM minimal AS full

ARG NODE_MAJOR=20

RUN set -eux; \
    if command -v dnf >/dev/null 2>&1; then PM=dnf; else PM=yum; fi; \
    "$PM" install -y nodejs npm || { \
      curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | bash -; \
      "$PM" install -y nodejs; \
    }; \
    "$PM" clean all; \
    npm install --global @anthropic-ai/claude-code @openai/codex; \
    npm cache clean --force

RUN set -eux; \
    install -d -m 0755 /opt/cursor-agent-home/.local/bin /usr/local/bin; \
    HOME=/opt/cursor-agent-home bash -c 'curl -fsS https://cursor.com/install | bash'; \
    test -x /opt/cursor-agent-home/.local/bin/agent; \
    ln -sf /opt/cursor-agent-home/.local/bin/agent /usr/local/bin/agent; \
    ln -sf /usr/local/bin/agent /usr/local/bin/cursor-agent

FROM full AS ssh

RUN set -eux; \
    if command -v dnf >/dev/null 2>&1; then PM=dnf; else PM=yum; fi; \
    "$PM" install -y openssh-server; \
    "$PM" clean all; \
    mkdir -p /run/sshd

COPY containers/alinux3/sshd_config /etc/ssh/sshd_config
