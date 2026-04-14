#!/usr/bin/env bash
set -euo pipefail

if [[ ! -c /dev/fuse ]]; then
  printf '[rootless-docker] /dev/fuse is required for fuse-overlayfs\n' >&2
  exit 1
fi

if ! command -v dockerd-rootless.sh >/dev/null 2>&1; then
  printf '[rootless-docker] dockerd-rootless.sh not found\n' >&2
  exit 1
fi

uid="$(id -u)"
export HOME="${HOME:-/home/agent}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
export DOCKER_HOST="${DOCKER_HOST:-unix://${XDG_RUNTIME_DIR}/docker.sock}"
export DOCKERD_ROOTLESS_ROOTLESSKIT_NET="${DOCKERD_ROOTLESS_ROOTLESSKIT_NET:-slirp4netns}"
export DOCKERD_ROOTLESS_ROOTLESSKIT_PORT_DRIVER="${DOCKERD_ROOTLESS_ROOTLESSKIT_PORT_DRIVER:-slirp4netns}"
export DOCKERD_ROOTLESS_ROOTLESSKIT_MTU="${DOCKERD_ROOTLESS_ROOTLESSKIT_MTU:-1500}"

mkdir -p "${XDG_RUNTIME_DIR}" "${HOME}/.local/share/docker"

exec dockerd-rootless.sh --storage-driver=fuse-overlayfs
