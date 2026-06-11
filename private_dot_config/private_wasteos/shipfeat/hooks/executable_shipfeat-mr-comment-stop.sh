#!/usr/bin/env bash
# When shipfeat MR watcher queues feedback, auto-continue the agent loop.
set -euo pipefail

ready_file=".shipfeat/mr-comment-ready.json"
pending_file=".shipfeat/pending-mr-comment-prompt.md"

if [[ ! -f "$ready_file" ]] || [[ ! -f "$pending_file" ]]; then
  echo '{}'
  exit 0
fi

# Do not delete ready here — consume_mr_comment_prompt.sh clears it after work is done.
# That way the Cursor rule + beforeSubmitPrompt hook keep nudging until consumed.

python3 <<'PY'
import json

msg = (
    "SHIPFEAT MR COMMENT QUEUED.\n\n"
    "Read `.shipfeat/pending-mr-comment-prompt.md` now and execute every item per "
    "`wasteos-mr-comment-watch` — commit, push, require_branch_pushed.sh, then "
    "resolve_mr_discussion.sh (never resolve before push). When finished: "
    "require_branch_pushed.sh && consume_mr_comment_prompt.sh."
)
print(json.dumps({"followup_message": msg}))
PY
