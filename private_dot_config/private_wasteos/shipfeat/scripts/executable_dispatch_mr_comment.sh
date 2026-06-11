#!/usr/bin/env bash
# Signal agent after build_mr_comment_prompt.sh (Cursor hook or tmux pane).
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
session="${repo_root}/.shipfeat/session.json"
[[ -f "$session" ]] || {
  echo "dispatch_mr_comment: no session.json" >&2
  exit 1
}

pending="${repo_root}/.shipfeat/pending-mr-comment-prompt.md"
[[ -f "$pending" ]] || {
  echo "dispatch_mr_comment: no pending prompt (run build_mr_comment_prompt.sh first)" >&2
  exit 1
}

read_session() {
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); v=d.get(sys.argv[2]); print("" if v is None else v)' "$session" "$1"
}

agent="$(read_session agent)"
branch="$(read_session branch)"
mr_url="$(read_session mr_url)"
tmux_target="$(read_session tmux_agent_target)"
dispatch_mode="$(read_session dispatch_mode)"

cd "$repo_root"
log="${repo_root}/.shipfeat/mr-watch-dispatch.log"

if [[ -z "$dispatch_mode" ]]; then
  if [[ -n "$tmux_target" ]] && tmux display-message -t "$tmux_target" -p '' >/dev/null 2>&1; then
    dispatch_mode="tmux"
  else
    dispatch_mode="cursor"
  fi
fi

if [[ "$dispatch_mode" == "cursor" ]]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) dispatch → cursor (mr-comment-ready.json)" >>"$log"
  echo "dispatch_mr_comment: queued for Cursor (.shipfeat/mr-comment-ready.json)" | tee -a "$log"
  exit 0
fi

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) dispatch → tmux agent=${agent} branch=${branch}" >>"$log"

if [[ -z "$tmux_target" ]]; then
  echo "dispatch_mr_comment: no tmux_agent_target in session.json" | tee -a "$log" >&2
  exit 1
fi

if ! tmux display-message -t "$tmux_target" -p '' >/dev/null 2>&1; then
  echo "dispatch_mr_comment: tmux pane not found: ${tmux_target}" | tee -a "$log" >&2
  exit 1
fi

instruction="MR review on ${branch}. Read .shipfeat/pending-mr-comment-prompt.md — follow wasteos-mr-comment-watch. Push before resolve; consume_mr_comment_prompt.sh when batch done."

tmux select-pane -t "$tmux_target"
tmux send-keys -t "$tmux_target" C-u 2>/dev/null || true
tmux send-keys -t "$tmux_target" -l "$instruction"
tmux send-keys -t "$tmux_target" Enter

echo "dispatch_mr_comment: sent to tmux pane ${tmux_target}" | tee -a "$log"
