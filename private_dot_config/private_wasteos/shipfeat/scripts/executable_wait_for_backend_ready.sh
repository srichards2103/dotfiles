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

backend_port="${BACKEND_PORT:-}"
if [[ -z "$backend_port" ]]; then
  echo "wait_for_backend_ready: BACKEND_PORT not set in .worktree.env" >&2
  exit 1
fi

# Django mounts readiness at api/common/readyz/ (see common.urls + wasteos.urls).
# /readyz/ at the host root is not routed and returns 404.
url="http://127.0.0.1:${backend_port}/api/common/readyz/"
max_attempts=120
sleep_seconds=5

echo "Waiting for ${url} (max $((max_attempts * sleep_seconds))s)..."

for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  body="$(curl -sf "$url" 2>/dev/null || true)"
  if [[ "$body" == '"READY"' || "$body" == "READY" ]]; then
    echo "Backend ready after ${attempt} attempt(s)."
    exit 0
  fi
  sleep "$sleep_seconds"
done

echo "wait_for_backend_ready: timed out (expected HTTP 200 body READY from ${url})" >&2
exit 1
