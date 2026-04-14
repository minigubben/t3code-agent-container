FROM node:24-bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    fd-find \
    git \
    openssh-client \
    python3 \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash t3

COPY docker/t3-web/entrypoint.sh /usr/local/bin/t3-entrypoint.sh
COPY docker/t3-web/bootstrap-t3-settings.sh /usr/local/bin/bootstrap-t3-settings.sh
COPY docker/t3-web/codex-remote /usr/local/bin/codex-remote
COPY docker/t3-web/opencode-remote /usr/local/bin/opencode-remote

RUN chmod 0755 \
    /usr/local/bin/t3-entrypoint.sh \
    /usr/local/bin/bootstrap-t3-settings.sh \
    /usr/local/bin/codex-remote \
    /usr/local/bin/opencode-remote

ENTRYPOINT ["/usr/local/bin/t3-entrypoint.sh"]
CMD ["--host", "0.0.0.0", "--port", "3773", "--base-dir", "/home/t3/.t3", "--no-browser"]
