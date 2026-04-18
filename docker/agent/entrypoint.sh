#!/usr/bin/env bash
set -euo pipefail

AGENT_USER="agent"
AGENT_GROUP="agent"
AGENT_HOME="/home/${AGENT_USER}"
AGENT_UID="${AGENT_UID:-1000}"
AGENT_GID="${AGENT_GID:-1000}"
DISABLED_PASSWORD_HASH="${DISABLED_PASSWORD_HASH:-\$6\$agent-harness\$xCBbYfQHAtzmgAE4B4Uzx5ElLFw2dzF/8JXJmZ27KIpG6NbejprAjHKl3bPCH6P51BapHdJvOaFSyRtl3/fKp1}"
SERVICE_RESTART_BACKOFF_SECONDS="${SERVICE_RESTART_BACKOFF_SECONDS:-2}"
SERVICE_RESTART_WINDOW_SECONDS="${SERVICE_RESTART_WINDOW_SECONDS:-30}"
SERVICE_MAX_RESTARTS="${SERVICE_MAX_RESTARTS:-5}"

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

run_rootless_docker() {
  exec sudo -u "${AGENT_USER}" -H env \
    XDG_RUNTIME_DIR="/run/user/${AGENT_UID}" \
    HOME="${AGENT_HOME}" \
    DOCKER_HOST="unix:///run/user/${AGENT_UID}/docker.sock" \
    DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS="${DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS:---propagation=private}" \
    /usr/local/bin/start-rootless-docker.sh
}

run_t3_server() {
  exec sudo -u "${AGENT_USER}" -H env \
    XDG_RUNTIME_DIR="/run/user/${AGENT_UID}" \
    HOME="${AGENT_HOME}" \
    DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/${AGENT_UID}/docker.sock}" \
    GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-}" \
    GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-}" \
    GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-}" \
    GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-}" \
    OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
    OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}" \
    ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
    OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD:-}" \
    TZ="${TZ:-UTC}" \
    T3CODE_HOME="${T3CODE_HOME:-${AGENT_HOME}/.t3}" \
    T3_PORT="${T3_PORT:-3773}" \
    NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-${AGENT_HOME}/.t3/npm-cache}" \
    /usr/local/bin/start-t3-server.sh
}

supervise_service() {
  local service_name="$1"
  shift

  local child_pid=""
  local consecutive_restarts=0
  local last_start_epoch=0

  cleanup_child() {
    if [[ -n "${child_pid}" ]]; then
      kill "${child_pid}" >/dev/null 2>&1 || true
      wait "${child_pid}" >/dev/null 2>&1 || true
    fi
  }

  trap 'cleanup_child; exit 0' INT TERM

  while true; do
    last_start_epoch="$(date +%s)"
    log "starting ${service_name}"
    "$@" &
    child_pid=$!

    local exit_code=0
    if wait "${child_pid}"; then
      exit_code=0
    else
      exit_code=$?
    fi
    child_pid=""

    local now_epoch runtime_seconds
    now_epoch="$(date +%s)"
    runtime_seconds=$((now_epoch - last_start_epoch))

    if (( runtime_seconds >= SERVICE_RESTART_WINDOW_SECONDS )); then
      consecutive_restarts=0
    fi

    consecutive_restarts=$((consecutive_restarts + 1))
    if (( consecutive_restarts >= SERVICE_MAX_RESTARTS )); then
      log "${service_name} exited ${consecutive_restarts} times within ${SERVICE_RESTART_WINDOW_SECONDS}s; giving up"
      return "${exit_code}"
    fi

    log "${service_name} exited with status ${exit_code}; restarting in ${SERVICE_RESTART_BACKOFF_SECONDS}s"
    sleep "${SERVICE_RESTART_BACKOFF_SECONDS}"
  done
}

cleanup() {
  local exit_code=$?
  if [[ -n "${DOCKER_SUPERVISOR_PID:-}" ]]; then
    kill "${DOCKER_SUPERVISOR_PID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${T3_SUPERVISOR_PID:-}" ]]; then
    kill "${T3_SUPERVISOR_PID}" >/dev/null 2>&1 || true
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
supervise_service "rootless Docker" run_rootless_docker &
DOCKER_SUPERVISOR_PID=$!
supervise_service "T3 server" run_t3_server &
T3_SUPERVISOR_PID=$!

wait -n "${DOCKER_SUPERVISOR_PID}" "${T3_SUPERVISOR_PID}"
