#!/usr/bin/env bash
set -euo pipefail

agent_home="${HOME:-/home/agent}"
t3_port="${T3_PORT:-3773}"
t3_base_dir="${T3CODE_HOME:-${agent_home}/.t3}"
npm_cache="${NPM_CONFIG_CACHE:-${t3_base_dir}/npm-cache}"

mkdir -p "${t3_base_dir}" "${npm_cache}"
/usr/local/bin/bootstrap-t3-settings.sh

cd "${agent_home}"
export HOME="${agent_home}"
export T3CODE_HOME="${t3_base_dir}"
export NPM_CONFIG_CACHE="${npm_cache}"

# Preserve the existing runtime environment so agents spawned by T3 inherit
# Docker access and provider credentials from the container.
exec t3 serve --host 0.0.0.0 --port "${t3_port}" --base-dir "${t3_base_dir}" --no-browser
