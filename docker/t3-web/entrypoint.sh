#!/usr/bin/env bash
set -euo pipefail

T3_USER="t3"
T3_HOME="/home/${T3_USER}"
T3CODE_HOME="${T3CODE_HOME:-${T3_HOME}/.t3}"
T3_UID="${T3_UID:-1000}"
T3_GID="${T3_GID:-1000}"
KEY_SOURCE="/run/secrets/t3_agent_key"
KEY_TARGET="${T3_HOME}/.ssh/id_ed25519"

log() {
  printf '[t3-entrypoint] %s\n' "$*"
}

ensure_identity() {
  local current_uid current_gid target_user target_group
  current_uid="$(id -u "${T3_USER}")"
  current_gid="$(id -g "${T3_USER}")"

  if [[ "${current_gid}" != "${T3_GID}" ]]; then
    target_group="$(getent group "${T3_GID}" | cut -d: -f1 || true)"
    if [[ -n "${target_group}" && "${target_group}" != "${T3_USER}" ]]; then
      log "requested T3_GID ${T3_GID} is already used by group ${target_group}"
      exit 1
    fi
    groupmod -o -g "${T3_GID}" "${T3_USER}"
  fi

  if [[ "${current_uid}" != "${T3_UID}" ]]; then
    target_user="$(getent passwd "${T3_UID}" | cut -d: -f1 || true)"
    if [[ -n "${target_user}" && "${target_user}" != "${T3_USER}" ]]; then
      log "requested T3_UID ${T3_UID} is already used by user ${target_user}"
      exit 1
    fi
    usermod -o -u "${T3_UID}" "${T3_USER}"
  fi
}

prepare_home() {
  mkdir -p "${T3_HOME}/.ssh" "${T3CODE_HOME}"
  chown -R "${T3_USER}:${T3_USER}" "${T3_HOME}"
  chmod 0700 "${T3_HOME}/.ssh"
}

install_key() {
  if [[ ! -f "${KEY_SOURCE}" ]]; then
    log "missing private key at ${KEY_SOURCE}"
    exit 1
  fi

  install -m 0600 -o "${T3_USER}" -g "${T3_USER}" "${KEY_SOURCE}" "${KEY_TARGET}"
}

ensure_identity
prepare_home
install_key
su -s /bin/bash "${T3_USER}" -c "T3CODE_HOME='${T3CODE_HOME}' /usr/local/bin/bootstrap-t3-settings.sh"

quoted_args=()
for arg in "$@"; do
  quoted_args+=("$(printf '%q' "${arg}")")
done

exec su -s /bin/bash "${T3_USER}" -c \
  "HOME='${T3_HOME}' T3CODE_HOME='${T3CODE_HOME}' NPM_CONFIG_CACHE='${NPM_CONFIG_CACHE:-${T3CODE_HOME}/npm-cache}' exec npx --yes t3 ${quoted_args[*]}"
