#!/usr/bin/env bash
set -euo pipefail

agent_home="${HOME:-/home/agent}"
t3_base_dir="${T3CODE_HOME:-${agent_home}/.t3}"
state_dir="${t3_base_dir}/userdata"
settings_path="${state_dir}/settings.json"

mkdir -p "${state_dir}"

if [[ -f "${settings_path}" ]]; then
  exit 0
fi

node - "${settings_path}" "${agent_home}" <<'NODE'
const fs = require("node:fs");
const settingsPath = process.argv[2];
const agentHome = process.argv[3];

const settings = {
  providers: {
    codex: {
      binaryPath: "/usr/local/bin/codex",
      homePath: `${agentHome}/.codex`,
    },
  },
};

fs.writeFileSync(settingsPath, `${JSON.stringify(settings, null, 2)}\n`, "utf8");
NODE
