#!/usr/bin/env bash
# Print or verify MR session state (.shipfeat/session.json).
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

require_ready=false
[[ "${1:-}" == "--require-ready" ]] && require_ready=true

repo_root="$(shipfeat_worktree_root)"
session="${repo_root}/.shipfeat/session.json"

if [[ ! -f "$session" ]]; then
  echo "MR session: missing (${session})" >&2
  $require_ready && exit 1
  exit 0
fi

python3 - "$session" "$require_ready" <<'PY'
import json, sys

path, require = sys.argv[1], sys.argv[2] == "True"
s = json.load(open(path, encoding="utf-8"))
iid, url = s.get("mr_iid"), s.get("mr_url")
print(f"MR session: branch={s.get('branch')} agent={s.get('agent')} dispatch={s.get('dispatch_mode')}")
if iid:
    print(f"MR: !{iid} {url or '(no url)'}")
else:
    print("MR: not recorded (run record_mr_open.sh or open_mr.sh)")
if require and (not iid or not url):
    raise SystemExit(1)
PY
