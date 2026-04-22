FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list \
    && curl -fsSL https://deb.nodesource.com/setup_24.x | bash -

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    cmake \
    containerd.io \
    dbus-user-session \
    docker-buildx-plugin \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin \
    docker-ce-rootless-extras \
    fd-find \
    file \
    fuse-overlayfs \
    g++ \
    gcc \
    gdb \
    git \
    iptables \
    iproute2 \
    jq \
    less \
    libudev-dev \
    libusb-1.0-0-dev \
    lldb \
    make \
    man-db \
    ninja-build \
    nodejs \
    openssh-client \
    pipx \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    rsync \
    sqlite3 \
    strace \
    sudo \
    udev \
    uidmap \
    unzip \
    usbutils \
    xz-utils \
    zip \
    zsh \
    slirp4netns \
    && npm install -g @openai/codex@latest opencode-ai@latest t3@latest \
    && ln -sf /usr/bin/codex /usr/local/bin/codex \
    && ln -sf /usr/bin/opencode /usr/local/bin/opencode \
    && ln -sf /usr/bin/t3 /usr/local/bin/t3 \
    && corepack enable \
    && rm -rf /var/lib/apt/lists/*

RUN userdel -r ubuntu >/dev/null 2>&1 || true \
    && groupdel ubuntu >/dev/null 2>&1 || true \
    && groupadd --gid 1000 agent \
    && useradd --uid 1000 --gid agent --shell /bin/bash --create-home agent \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent \
    && echo "agent:100000:65536" >> /etc/subuid \
    && echo "agent:100000:65536" >> /etc/subgid \
    && mkdir -p /home/agent/.ssh \
    && chown -R agent:agent /home/agent

COPY docker/agent/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/agent/start-rootless-docker.sh /usr/local/bin/start-rootless-docker.sh
COPY docker/agent/start-t3-server.sh /usr/local/bin/start-t3-server.sh
COPY docker/agent/bootstrap-t3-settings.sh /usr/local/bin/bootstrap-t3-settings.sh

RUN chmod 0755 \
    /usr/local/bin/entrypoint.sh \
    /usr/local/bin/start-rootless-docker.sh \
    /usr/local/bin/start-t3-server.sh \
    /usr/local/bin/bootstrap-t3-settings.sh

ENV HOME=/home/agent
ENV PATH=/home/agent/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV DOCKER_HOST=unix:///run/user/1000/docker.sock

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
