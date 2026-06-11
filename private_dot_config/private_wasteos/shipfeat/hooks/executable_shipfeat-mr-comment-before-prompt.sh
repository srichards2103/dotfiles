#!/usr/bin/env bash
# When MR feedback is queued, inject instructions into every user prompt turn.
set -euo pipefail

ready_file=".shipfeat/mr-comment-ready.json"
pending_file=".shipfeat/pending-mr-comment-prompt.md"

if [[ ! -f "$ready_file" ]] || [[ ! -f "$pending_file" ]]; then
  echo '{}'
  exit 0
fi

cat <<'EOF'
{
  "continue": true,
  "agent_message": "SHIPFEAT MR COMMENT QUEUED: Read `.shipfeat/pending-mr-comment-prompt.md` first. Any tracked change needs commit+push; run require_branch_pushed.sh before resolve_mr_discussion.sh. Then consume_mr_comment_prompt.sh."
}
EOF
