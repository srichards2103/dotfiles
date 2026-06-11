#!/usr/bin/env bash
# Build pending-mr-comment-prompt.md from queued ledger entries (does not dispatch).
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
script_dir="$(cd "$(dirname "$0")" && pwd)"

queued="$(python3 "${script_dir}/mr_comment_ledger.py" queued-count "$repo_root")"
if (( queued == 0 )); then
  exit 1
fi

count="$(python3 "${script_dir}/mr_comment_ledger.py" build "$repo_root")"
python3 "${script_dir}/mr_comment_ledger.py" render-md "$repo_root" >/dev/null

if (( count > 0 )); then
  echo "build_mr_comment_prompt: built batch with ${count} note(s)"
  exit 0
fi
exit 1
