#!/usr/bin/env bash
# Re-enqueue unresolved GitLab discussions missing from terminal ledger states.
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
session="${repo_root}/.shipfeat/session.json"
[[ -f "$session" ]] || exit 0

mr_iid="$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get("mr_iid"); print(v or "")' "$session")"
[[ -n "$mr_iid" ]] || exit 0

script_dir="$(cd "$(dirname "$0")" && pwd)"
count="$(python3 "${script_dir}/mr_comment_ledger.py" reconcile "$repo_root" "$mr_iid")"
if (( count > 0 )); then
  echo "reconcile_mr_discussions: re-queued ${count} discussion(s)"
fi
