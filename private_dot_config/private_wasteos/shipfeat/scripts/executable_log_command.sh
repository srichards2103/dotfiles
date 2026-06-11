#!/usr/bin/env bash
# Run a command and append evidence to .shipfeat/commands.jsonl
set -euo pipefail

usage() {
  echo "Usage: log_command.sh <phase> -- <command...>" >&2
  echo "  phase: tests | drst | frontend | openapi | migrate | ui | mr | review | other" >&2
  exit 1
}

(( $# >= 1 )) || usage
phase="$1"
shift
[[ "${1:-}" == "--" ]] || usage
shift
(( $# >= 1 )) || usage

# shellcheck source=_worktree_root.sh
# shellcheck source=_shipfeat_lib.sh
source "$(dirname "$0")/_worktree_root.sh"
source "$(dirname "$0")/_shipfeat_lib.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"
log_file="${repo_root}/.shipfeat/commands.jsonl"
mkdir -p "${repo_root}/.shipfeat"

cmd_display="$*"
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set +e
"$@"
exit_code=$?
set -e
end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
commit_sha="$(shipfeat_head_sha)"

python3 - "$log_file" "$phase" "$exit_code" "$start" "$end" "$commit_sha" "$cmd_display" <<'PY'
import json, sys
from pathlib import Path

path, phase, code, start, end, sha, cmd = sys.argv[1:8]
entry = {
    "timestamp": end,
    "started_at": start,
    "phase": phase,
    "command": cmd,
    "exit_code": int(code),
    "commit_sha": sha,
}
with Path(path).open("a", encoding="utf-8") as f:
    f.write(json.dumps(entry, separators=(",", ":")) + "\n")
PY

exit "$exit_code"
