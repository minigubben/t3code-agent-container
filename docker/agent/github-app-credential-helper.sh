#!/usr/bin/env bash
set -euo pipefail

# Git calls credential helpers with one of get/store/erase. Only get needs an
# answer; installation tokens are cached and minted by github-app-token.
operation="${1:-get}"
declare -A request=()
while IFS='=' read -r key value; do
  [[ -n "${key}" ]] || break
  request["${key}"]="${value}"
done

if [[ "${operation}" != "get" || "${request[protocol]:-}" != "https" || "${request[host]:-}" != "github.com" ]]; then
  exit 0
fi

if [[ -z "${GITHUB_APP_ID:-}" ]]; then
  exit 0
fi

if token="$(/usr/local/bin/github-app-token)"; then
  printf 'username=x-access-token\npassword=%s\n\n' "${token}"
fi
