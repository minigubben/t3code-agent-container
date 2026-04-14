#!/usr/bin/env bash
set -euo pipefail

T3CODE_HOME="${T3CODE_HOME:-/home/t3/.t3}"
STATE_DIR="${T3CODE_HOME}/userdata"
SETTINGS_PATH="${STATE_DIR}/settings.json"

mkdir -p "${STATE_DIR}"

if [[ -f "${SETTINGS_PATH}" ]]; then
  exit 0
fi

node - "${SETTINGS_PATH}" <<'NODE'
const fs = require("node:fs");
const path = process.argv[2];
const settings = {
  providers: {
    codex: {
      binaryPath: "/usr/local/bin/codex-remote",
      homePath: "",
    },
  },
};
fs.writeFileSync(path, `${JSON.stringify(settings, null, 2)}\n`, "utf8");
NODE
