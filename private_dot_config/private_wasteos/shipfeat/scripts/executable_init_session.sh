#!/usr/bin/env bash
# Write .shipfeat/session.json for MR watcher + agent resume context.
set -euo pipefail

if (( $# < 3 )); then
  echo "Usage: init_session.sh <branch> <agent> <worktree-path> [tmux-agent-target]" >&2
  exit 1
fi

branch="$1"
agent="$2"
worktree="$(cd "$3" && pwd)"
tmux_target="${4:-}"
poll_interval="${SHIPFEAT_MR_POLL_SEC:-45}"

mkdir -p "${worktree}/.shipfeat"

python3 - "$worktree/.shipfeat/session.json" "$branch" "$agent" "$worktree" "$poll_interval" "$tmux_target" <<'PY'
import json, sys
from datetime import datetime, timezone

out, branch, agent, worktree, poll, tmux_target = sys.argv[1:7]
cursor_agents = {"agent", "cursor"}
dispatch_mode = "cursor" if agent in cursor_agents else "tmux"
include_own = agent in cursor_agents

payload = {
    "branch": branch,
    "agent": agent,
    "worktree": worktree,
    "tmux_agent_target": tmux_target or None,
    "dispatch_mode": dispatch_mode,
    "include_own_mr_notes": include_own,
    "mr_iid": None,
    "mr_url": None,
    "poll_interval_sec": int(poll),
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")
PY

echo "session: ${worktree}/.shipfeat/session.json"
echo "session: dispatch_mode=$(python3 -c 'import json; print(json.load(open("'"${worktree}/.shipfeat/session.json"'"))["dispatch_mode"])')"
[[ -n "$tmux_target" ]] && echo "session: agent tmux target=${tmux_target}"
