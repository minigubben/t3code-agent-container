#!/usr/bin/env bash
set -euo pipefail

AGENT_USER="agent"
AGENT_GROUP="agent"
AGENT_HOME="/home/${AGENT_USER}"
AGENT_UID="${AGENT_UID:-1000}"
AGENT_GID="${AGENT_GID:-1000}"
PUBKEY_SOURCE="${T3_AGENT_PUBLIC_KEY_PATH:-/run/config/t3_agent_key.pub}"
DISABLED_PASSWORD_HASH="${DISABLED_PASSWORD_HASH:-\$6\$agent-harness\$xCBbYfQHAtzmgAE4B4Uzx5ElLFw2dzF/8JXJmZ27KIpG6NbejprAjHKl3bPCH6P51BapHdJvOaFSyRtl3/fKp1}"

log() {
  printf '[agent-entrypoint] %s\n' "$*"
}

ensure_identity() {
  local current_uid current_gid target_user target_group
  current_uid="$(id -u "${AGENT_USER}")"
  current_gid="$(id -g "${AGENT_USER}")"

  if [[ "${current_gid}" != "${AGENT_GID}" ]]; then
    target_group="$(getent group "${AGENT_GID}" | cut -d: -f1 || true)"
    if [[ -n "${target_group}" && "${target_group}" != "${AGENT_GROUP}" ]]; then
      log "requested AGENT_GID ${AGENT_GID} is already used by group ${target_group}"
      exit 1
    fi
    groupmod -o -g "${AGENT_GID}" "${AGENT_GROUP}"
  fi

  if [[ "${current_uid}" != "${AGENT_UID}" ]]; then
    target_user="$(getent passwd "${AGENT_UID}" | cut -d: -f1 || true)"
    if [[ -n "${target_user}" && "${target_user}" != "${AGENT_USER}" ]]; then
      log "requested AGENT_UID ${AGENT_UID} is already used by user ${target_user}"
      exit 1
    fi
    usermod -o -u "${AGENT_UID}" "${AGENT_USER}"
  fi
}

ensure_runtime_paths() {
  mkdir -p \
    "${AGENT_HOME}/.ssh" \
    "${AGENT_HOME}/.codex" \
    "${AGENT_HOME}/.opencode" \
    "${AGENT_HOME}/.local/share/docker" \
    "/run/user/${AGENT_UID}" \
    /var/run/sshd

  chown -R "${AGENT_USER}:${AGENT_GROUP}" \
    "${AGENT_HOME}" \
    "/run/user/${AGENT_UID}"
  chmod 0700 "${AGENT_HOME}/.ssh"
  chmod 0700 "${AGENT_HOME}" "${AGENT_HOME}/.codex" "${AGENT_HOME}/.opencode"
}

repair_runtime_ownership() {
  chown -R "${AGENT_USER}:${AGENT_GROUP}" \
    "${AGENT_HOME}/.codex" \
    "${AGENT_HOME}/.opencode" \
    "${AGENT_HOME}/.local"
}

ensure_ssh_account_is_unlocked() {
  local shadow_hash
  shadow_hash="$(getent shadow "${AGENT_USER}" | cut -d: -f2 || true)"
  if [[ -z "${shadow_hash}" || "${shadow_hash}" == "!" || "${shadow_hash}" == "*" || "${shadow_hash}" == '!'* || "${shadow_hash}" == '*'* ]]; then
    usermod -p "${DISABLED_PASSWORD_HASH}" "${AGENT_USER}"
  fi
}

install_authorized_key() {
  if [[ ! -f "${PUBKEY_SOURCE}" ]]; then
    log "missing public key at ${PUBKEY_SOURCE}"
    exit 1
  fi

  install -m 0600 -o "${AGENT_USER}" -g "${AGENT_GROUP}" /dev/null "${AGENT_HOME}/.ssh/authorized_keys"
  cat "${PUBKEY_SOURCE}" > "${AGENT_HOME}/.ssh/authorized_keys"
  chown "${AGENT_USER}:${AGENT_GROUP}" "${AGENT_HOME}/.ssh/authorized_keys"
}

configure_subids() {
  sed -i '/^agent:/d' /etc/subuid /etc/subgid
  echo "agent:100000:65536" >> /etc/subuid
  echo "agent:100000:65536" >> /etc/subgid
}

start_rootless_docker() {
  log "starting rootless Docker for ${AGENT_USER}"
  sudo -u "${AGENT_USER}" -H env \
    XDG_RUNTIME_DIR="/run/user/${AGENT_UID}" \
    HOME="${AGENT_HOME}" \
    DOCKER_HOST="unix:///run/user/${AGENT_UID}/docker.sock" \
    DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS="${DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS:---propagation=private}" \
    /usr/local/bin/start-rootless-docker.sh &
  DOCKER_PID=$!
}

start_sshd() {
  ssh-keygen -A >/dev/null
  log "starting sshd"
  /usr/sbin/sshd -D -e &
  SSHD_PID=$!
}

cleanup() {
  local exit_code=$?
  if [[ -n "${DOCKER_PID:-}" ]]; then
    kill "${DOCKER_PID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${SSHD_PID:-}" ]]; then
    kill "${SSHD_PID}" >/dev/null 2>&1 || true
  fi
  wait >/dev/null 2>&1 || true
  exit "${exit_code}"
}

trap cleanup EXIT INT TERM

ensure_identity
ensure_ssh_account_is_unlocked
configure_subids
ensure_runtime_paths
repair_runtime_ownership
install_authorized_key
start_rootless_docker
start_sshd

wait -n "${DOCKER_PID}" "${SSHD_PID}"
