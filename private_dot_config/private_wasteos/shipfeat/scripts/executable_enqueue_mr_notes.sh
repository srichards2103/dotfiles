#!/usr/bin/env bash
# Enqueue new MR notes into .shipfeat/mr-comments/queued/ + ledger (no prompt overwrite).
set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: enqueue_mr_notes.sh <notes-json-file>" >&2
  exit 1
fi

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
notes_file="$1"
[[ -f "$notes_file" ]] || { echo "enqueue_mr_notes: missing ${notes_file}" >&2; exit 1; }

script_dir="$(cd "$(dirname "$0")" && pwd)"
count="$(python3 "${script_dir}/mr_comment_ledger.py" enqueue "$repo_root" "$notes_file")"
python3 "${script_dir}/mr_comment_ledger.py" render-md "$repo_root" >/dev/null

if (( count > 0 )); then
  echo "enqueue_mr_notes: queued ${count} note(s)"
fi
