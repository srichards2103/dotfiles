#!/usr/bin/env bash
set -euo pipefail

if (( $# < 2 )); then
  echo "Usage: run-agent.sh <codex|claude|agent|cursor> <worktree-path>" >&2
  exit 1
fi

agent="$1"
worktree="$2"
prompt_file="${worktree}/.shipfeat/prompt.md"

if [[ ! -f "$prompt_file" ]]; then
  echo "run-agent: missing ${prompt_file}" >&2
  exit 1
fi

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

export SHIPFEAT_WORKTREE="$worktree"
export SHIPFEAT_HOME="$(shipfeat_tooling_root)"
export SHIPFEAT_TOOLING="$SHIPFEAT_HOME"

cd "$worktree"

trust_script="$(dirname "$0")/trust_worktree.sh"
[[ -x "$trust_script" ]] && "$trust_script" "$worktree" || true

prompt="$(<"$prompt_file")"

case "$agent" in
  codex)
    exec codex "$prompt"
    ;;
  claude)
    exec claude "$prompt"
    ;;
  agent | cursor)
    if command -v agent >/dev/null 2>&1; then
      exec agent "$prompt"
    fi
    exec cursor agent "$prompt"
    ;;
  *)
    echo "run-agent: unknown agent '${agent}' (use codex, claude, or agent)" >&2
    exit 1
    ;;
esac
