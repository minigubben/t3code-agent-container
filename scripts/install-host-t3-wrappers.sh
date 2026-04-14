#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

install_wrappers=true
update_t3_settings=true
default_target="container"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ensure-key-only)
      install_wrappers=false
      update_t3_settings=false
      ;;
    --skip-wrapper-install)
      install_wrappers=false
      ;;
    --skip-t3-settings)
      update_t3_settings=false
      ;;
    --default-target)
      [[ $# -ge 2 ]] || {
        printf 'missing value for --default-target\n' >&2
        exit 1
      }
      default_target="$2"
      shift
      ;;
    *)
      printf 'unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

load_env
ensure_t3_agent_key

case "${default_target}" in
  host|container)
    ;;
  *)
    printf 'unsupported default target: %s\n' "${default_target}" >&2
    exit 1
    ;;
esac

if [[ "${install_wrappers}" == true ]]; then
  install -d "${HOME}/.local/bin"
  install -m 0755 "${PROJECT_ROOT}/host-bin/codex-appimage" "${HOME}/.local/bin/codex-appimage"
  install -m 0755 "${PROJECT_ROOT}/host-bin/codex-host" "${HOME}/.local/bin/codex-host"
  install -m 0755 "${PROJECT_ROOT}/host-bin/codex-remote" "${HOME}/.local/bin/codex-remote"
  install -m 0755 "${PROJECT_ROOT}/host-bin/opencode-remote" "${HOME}/.local/bin/opencode-remote"
fi

if [[ "${update_t3_settings}" == true ]]; then
  bash "${PROJECT_ROOT}/scripts/set-t3-codex-target" "${default_target}"
fi

printf 'host wrappers ready\n'
