# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=alibaba-cloud-linux-3-registry.cn-hangzhou.cr.aliyuncs.com/alinux3/alinux3:latest

FROM ${BASE_IMAGE}

ARG TARGETARCH=amd64
ARG NODE_MAJOR=20
ARG LAZYGIT_VERSION=0.44.1
ARG BAT_VERSION=0.25.0
ARG RG_VERSION=14.1.1
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ARG http_proxy
ARG https_proxy
ARG no_proxy

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEVTOOLS_ROOT=/opt/devtools \
    HOME=/home/admin \
    PATH=/home/admin/.local/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY os/lib/repos/epel-8-aliyun.repo /etc/yum.repos.d/devtools-epel-8-aliyun.repo

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64|x86_64) ;; \
      *) echo "alinux3-devbox currently supports linux/amd64 only, got: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    if command -v dnf >/dev/null 2>&1; then PM=dnf; else PM=yum; fi; \
    find /etc/yum.repos.d /etc/yum /etc/dnf -type f \( -name '*.repo' -o -name '*.conf' \) 2>/dev/null \
      | while IFS= read -r repo; do \
          sed -i \
            -e 's|https\?://mirrors\.cloud\.aliyuncs\.com|https://mirrors.aliyun.com|g' \
            -e 's|https\?://mirrors\.aliyuncs\.com|https://mirrors.aliyun.com|g' \
            "$repo"; \
        done; \
    if [[ -f /etc/dnf/dnf.conf ]]; then \
      grep -q '^fastestmirror=' /etc/dnf/dnf.conf \
        && sed -i 's/^fastestmirror=.*/fastestmirror=False/' /etc/dnf/dnf.conf \
        || printf '\nfastestmirror=False\n' >> /etc/dnf/dnf.conf; \
    fi; \
    "$PM" install -y \
      bash git curl wget tar gzip unzip zip xz \
      findutils gawk grep sed which less \
      procps-ng shadow-utils util-linux sudo \
      vim-enhanced \
      make gcc gcc-c++ bison autoconf automake pkgconfig \
      libevent-devel ncurses-devel \
      ca-certificates python3 \
      jq tree; \
    "$PM" install -y cloc ripgrep bat || true; \
    if ! "$PM" install -y nodejs npm; then \
      curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | bash -; \
      "$PM" install -y nodejs; \
    fi; \
    "$PM" clean all

RUN set -eux; \
    groupadd --gid 1000 admin; \
    useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash admin; \
    echo 'admin ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/admin; \
    chmod 0440 /etc/sudoers.d/admin; \
    mkdir -p /opt/devtools /workspace /etc/profile.d \
      /home/admin/.cache /home/admin/.local/bin /home/admin/.config; \
    printf '%s\n' 'export PATH="/home/admin/.local/bin:/usr/local/bin:${PATH}"' \
      > /etc/profile.d/devtools.sh; \
    chown -R admin:admin /home/admin /workspace

COPY --chown=admin:admin cache /opt/devtools/cache
COPY --chown=admin:admin shell/bash /opt/devtools/shell/bash
COPY --chown=admin:admin shell/starship /opt/devtools/shell/starship
COPY --chown=admin:admin tools/git /opt/devtools/tools/git
COPY --chown=admin:admin editors/vim /opt/devtools/editors/vim
COPY --chown=admin:admin editors/nvim /opt/devtools/editors/nvim
COPY --chown=admin:admin terminal/tmux /opt/devtools/terminal/tmux
COPY docker/alinux3/bootstrap.sh /usr/local/bin/devtools-bootstrap

RUN chmod 0755 /usr/local/bin/devtools-bootstrap \
 && sudo -u admin -H \
      env HOME=/home/admin \
          USER=admin \
          LOGNAME=admin \
          TERM=xterm-256color \
          GIT_TERMINAL_PROMPT=0 \
          NVIM_SETUP_STRICT=1 \
          DEVTOOLS_ROOT=/opt/devtools \
          DEVTOOLS_CACHE_DIR=/opt/devtools/cache \
          LAZYGIT_VERSION="${LAZYGIT_VERSION}" \
          BAT_VERSION="${BAT_VERSION}" \
          RG_VERSION="${RG_VERSION}" \
          HTTP_PROXY="${HTTP_PROXY:-}" \
          HTTPS_PROXY="${HTTPS_PROXY:-}" \
          NO_PROXY="${NO_PROXY:-}" \
          http_proxy="${http_proxy:-}" \
          https_proxy="${https_proxy:-}" \
          no_proxy="${no_proxy:-}" \
          PATH=/home/admin/.local/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      /usr/local/bin/devtools-bootstrap

RUN mkdir -p /home/admin/.cache \
 && chown -R admin:admin /home/admin

ENV USER=admin \
    LOGNAME=admin

WORKDIR /home/admin
USER admin
CMD ["bash"]
