#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"

set -a
# shellcheck disable=SC1091
source .worktree.env
set +a

host="${SHIPFEAT_APP_HOST:-wskips.encore.localhost}"
port="${NGINX_PORT:-}"

if [[ -z "$port" ]]; then
  echo "app_url: NGINX_PORT not set in .worktree.env" >&2
  exit 1
fi

# Use nginx (not FRONTEND_PORT): API + SPA are served together for Playwright login.
printf 'http://%s:%s/\n' "$host" "$port"
