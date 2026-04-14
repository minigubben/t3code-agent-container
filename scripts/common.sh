#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

load_env() {
  if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
    set +a
  fi

  export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-agent-harness}"
  export WORKSPACE_MODE="${WORKSPACE_MODE:-local-bind}"
  export HOST_WORKSPACE_ROOT="${HOST_WORKSPACE_ROOT:-$HOME}"
  export CONTAINER_WORKSPACE_ROOT="${CONTAINER_WORKSPACE_ROOT:-/home/workspaces}"
  export AGENT_UID="${AGENT_UID:-$(id -u)}"
  export AGENT_GID="${AGENT_GID:-$(id -g)}"
  export T3_WEB_PORT="${T3_WEB_PORT:-3773}"
  export AGENT_SSH_PORT="${AGENT_SSH_PORT:-47722}"
  export T3_AGENT_PRIVATE_KEY_PATH="${T3_AGENT_PRIVATE_KEY_PATH:-$HOME/.config/agent-harness/t3-agent/id_ed25519}"
  export T3_AGENT_PUBLIC_KEY_PATH="${T3_AGENT_PUBLIC_KEY_PATH:-$HOME/.config/agent-harness/t3-agent/id_ed25519.pub}"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

ensure_t3_agent_key() {
  local key_dir
  key_dir="$(dirname "${T3_AGENT_PRIVATE_KEY_PATH}")"
  mkdir -p "${key_dir}"

  if [[ ! -f "${T3_AGENT_PRIVATE_KEY_PATH}" ]]; then
    ssh-keygen -q -t ed25519 -N "" -f "${T3_AGENT_PRIVATE_KEY_PATH}"
  fi

  chmod 0700 "${key_dir}"
  chmod 0600 "${T3_AGENT_PRIVATE_KEY_PATH}"
  chmod 0644 "${T3_AGENT_PUBLIC_KEY_PATH}"
}

compose_args() {
  local args=("-f" "${PROJECT_ROOT}/compose.yml")

  case "${WORKSPACE_MODE}" in
    local-bind)
      args+=("-f" "${PROJECT_ROOT}/compose.local.yml")
      ;;
    remote-volume)
      args+=("-f" "${PROJECT_ROOT}/compose.remote.yml")
      ;;
    *)
      printf 'unsupported WORKSPACE_MODE: %s\n' "${WORKSPACE_MODE}" >&2
      exit 1
      ;;
  esac

  if [[ -f "${PROJECT_ROOT}/compose.usb.generated.yml" ]]; then
    args+=("-f" "${PROJECT_ROOT}/compose.usb.generated.yml")
  fi

  printf '%s\n' "${args[@]}"
}

compose_cmd() {
  mapfile -t _compose_args < <(compose_args)
  docker compose "${_compose_args[@]}" "$@"
}
