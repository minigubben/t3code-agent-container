#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

install_wrappers=true
update_t3_settings=true

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
    *)
      printf 'unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

load_env
ensure_t3_agent_key

if [[ "${install_wrappers}" == true ]]; then
  install -d "${HOME}/.local/bin"
  install -m 0755 "${PROJECT_ROOT}/host-bin/codex-remote" "${HOME}/.local/bin/codex-remote"
  install -m 0755 "${PROJECT_ROOT}/host-bin/opencode-remote" "${HOME}/.local/bin/opencode-remote"
fi

if [[ "${update_t3_settings}" == true ]]; then
  mkdir -p "${HOME}/.t3/userdata"
  python3 - "${HOME}/.t3/userdata/settings.json" "${HOME}/.local/bin/codex-remote" <<'PY'
import json
import os
import sys

settings_path = sys.argv[1]
wrapper_path = sys.argv[2]

if os.path.exists(settings_path):
    try:
        with open(settings_path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except Exception:
        data = {}
else:
    data = {}

providers = data.setdefault("providers", {})
codex = providers.setdefault("codex", {})
codex["binaryPath"] = wrapper_path
codex["homePath"] = ""

with open(settings_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
fi

printf 'host wrappers ready\n'
