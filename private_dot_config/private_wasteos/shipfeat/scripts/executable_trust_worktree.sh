#!/usr/bin/env bash
# Pre-trust a WasteOS worktree for Codex, Cursor agent, and Claude Code (no trust popup).
set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: trust_worktree.sh <worktree-path>" >&2
  exit 1
fi

worktree="$(cd "$1" && pwd)"

_shipfeat_cursor_project_slug() {
  local path="$1"
  path="${path#/}"
  printf '%s' "${path//\//-}"
}

_shipfeat_cursor_trust() {
  local slug
  slug="$(_shipfeat_cursor_project_slug "$worktree")"
  local dir="${HOME}/.cursor/projects/${slug}"
  mkdir -p "$dir"
  python3 - "$worktree" "$dir/.workspace-trusted" <<'PY'
import json, sys
from datetime import datetime, timezone

worktree, out = sys.argv[1], sys.argv[2]
payload = {
    "trustedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
    "workspacePath": worktree,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(payload, f)
    f.write("\n")
PY
}

_shipfeat_codex_trust() {
  local path="$1"
  local config="${HOME}/.codex/config.toml"
  [[ -f "$config" ]] || return 0
  if grep -Fq "[projects.\"${path}\"]" "$config"; then
    return 0
  fi
  cat >>"$config" <<EOF

[projects."${path}"]
trust_level = "trusted"
EOF
}

_shipfeat_claude_trust() {
  local path="$1"
  local config="${HOME}/.claude.json"
  [[ -f "$config" ]] || return 0
  python3 - "$path" "$config" <<'PY'
import json, sys

path, config_path = sys.argv[1], sys.argv[2]
with open(config_path, encoding="utf-8") as f:
    data = json.load(f)
projects = data.setdefault("projects", {})
entry = projects.setdefault(path, {})
entry["hasTrustDialogAccepted"] = True
with open(config_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

_shipfeat_cursor_trust
_shipfeat_codex_trust "$worktree"
_shipfeat_codex_trust "${HOME}/code"
_shipfeat_claude_trust "$worktree"
