#!/usr/bin/env bash
# Clear MR comment queue after push + GitLab discussion verification.
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"
script_dir="$(cd "$(dirname "$0")" && pwd)"

"${script_dir}/require_branch_pushed.sh" || {
  echo "consume_mr_comment_prompt: blocked — commit, push, then consume" >&2
  exit 1
}

session="${repo_root}/.shipfeat/session.json"
[[ -f "$session" ]] || {
  echo "consume_mr_comment_prompt: no session.json" >&2
  exit 1
}
mr_iid="$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get("mr_iid"); print(v or "")' "$session")"
[[ -n "$mr_iid" ]] || {
  echo "consume_mr_comment_prompt: mr_iid not set" >&2
  exit 1
}

# Verify every discussion in the active batch is resolved or explicitly blocked+replied.
python3 "${script_dir}/mr_comment_ledger.py" verify "$repo_root" "$mr_iid"

queued="$(python3 "${script_dir}/mr_comment_ledger.py" queue-count "$repo_root")"
if (( queued > 0 )); then
  echo "consume_mr_comment_prompt: ${queued} item(s) still queued — handle before consume" >&2
  exit 1
fi

python3 "${script_dir}/mr_comment_ledger.py" consume "$repo_root" "$mr_iid"
python3 "${script_dir}/mr_comment_ledger.py" render-md "$repo_root" >/dev/null

echo "consume_mr_comment_prompt: batch consumed and archived"
