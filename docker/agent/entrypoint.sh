#!/usr/bin/env bash
set -euo pipefail

AGENT_USER="agent"
AGENT_GROUP="agent"
AGENT_HOME="/home/${AGENT_USER}"
AGENT_UID="${AGENT_UID:-1000}"
AGENT_GID="${AGENT_GID:-1000}"
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
    "${AGENT_HOME}/.codex" \
    "${AGENT_HOME}/.opencode" \
    "${AGENT_HOME}/.t3" \
    "${AGENT_HOME}/.local/share/docker" \
    "/run/user/${AGENT_UID}"

  chown -R "${AGENT_USER}:${AGENT_GROUP}" \
    "${AGENT_HOME}" \
    "/run/user/${AGENT_UID}"
  chmod 0700 \
    "${AGENT_HOME}" \
    "${AGENT_HOME}/.codex" \
    "${AGENT_HOME}/.opencode" \
    "${AGENT_HOME}/.t3"
}

repair_runtime_ownership() {
  chown -R "${AGENT_USER}:${AGENT_GROUP}" \
    "${AGENT_HOME}/.codex" \
    "${AGENT_HOME}/.opencode" \
    "${AGENT_HOME}/.t3" \
    "${AGENT_HOME}/.local"
}

ensure_account_is_unlocked() {
  local shadow_hash
  shadow_hash="$(getent shadow "${AGENT_USER}" | cut -d: -f2 || true)"
  if [[ -z "${shadow_hash}" || "${shadow_hash}" == "!" || "${shadow_hash}" == "*" || "${shadow_hash}" == '!'* || "${shadow_hash}" == '*'* ]]; then
    usermod -p "${DISABLED_PASSWORD_HASH}" "${AGENT_USER}"
  fi
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

start_t3_server() {
  log "starting T3 server for ${AGENT_USER}"
  sudo -u "${AGENT_USER}" -H env \
    XDG_RUNTIME_DIR="/run/user/${AGENT_UID}" \
    HOME="${AGENT_HOME}" \
    T3CODE_HOME="${T3CODE_HOME:-${AGENT_HOME}/.t3}" \
    T3_PORT="${T3_PORT:-3773}" \
    NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-${AGENT_HOME}/.t3/npm-cache}" \
    /usr/local/bin/start-t3-server.sh &
  T3_PID=$!
}

cleanup() {
  local exit_code=$?
  if [[ -n "${DOCKER_PID:-}" ]]; then
    kill "${DOCKER_PID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${T3_PID:-}" ]]; then
    kill "${T3_PID}" >/dev/null 2>&1 || true
  fi
  wait >/dev/null 2>&1 || true
  exit "${exit_code}"
}

trap cleanup EXIT INT TERM

ensure_identity
ensure_account_is_unlocked
configure_subids
ensure_runtime_paths
repair_runtime_ownership
start_rootless_docker
start_t3_server

wait -n "${DOCKER_PID}" "${T3_PID}"
