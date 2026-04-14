#!/usr/bin/env bash
set -euo pipefail

T3_USER="t3"
T3_HOME="/home/${T3_USER}"
T3CODE_HOME="${T3CODE_HOME:-${T3_HOME}/.t3}"
KEY_SOURCE="/run/secrets/t3_agent_key"
KEY_TARGET="${T3_HOME}/.ssh/id_ed25519"

log() {
  printf '[t3-entrypoint] %s\n' "$*"
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

prepare_home
install_key
su -s /bin/bash "${T3_USER}" -c "T3CODE_HOME='${T3CODE_HOME}' /usr/local/bin/bootstrap-t3-settings.sh"

quoted_args=()
for arg in "$@"; do
  quoted_args+=("$(printf '%q' "${arg}")")
done

exec su -s /bin/bash "${T3_USER}" -c \
  "HOME='${T3_HOME}' T3CODE_HOME='${T3CODE_HOME}' NPM_CONFIG_CACHE='${NPM_CONFIG_CACHE:-${T3CODE_HOME}/npm-cache}' exec npx --yes t3 ${quoted_args[*]}"
