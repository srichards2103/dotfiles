#!/usr/bin/env bash
# Fail if required command phases are missing from commands.jsonl after profile gates.
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
profile="${repo_root}/.shipfeat/feature-profile.json"
log_file="${repo_root}/.shipfeat/commands.jsonl"

[[ -f "$profile" ]] || {
  echo "require_commands_logged: missing feature-profile.json" >&2
  exit 1
}

python3 - "$profile" "$log_file" <<'PY'
import json
import sys
from pathlib import Path

profile = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
log_path = Path(sys.argv[2])
phases_ok: set[str] = set()
if log_path.is_file():
    for line in log_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        row = json.loads(line)
        if row.get("exit_code") == 0:
            phases_ok.add(row.get("phase", ""))

required: list[str] = []
types = profile.get("change_types") or []
if "backend_api" in types or profile.get("requires_db_restore"):
    required.append("tests")
if profile.get("requires_db_restore"):
    required.append("drst")
if profile.get("requires_frontend_build"):
    required.append("frontend")
if profile.get("requires_openapi_regen"):
    required.append("openapi")
if "model_migration" in types:
    required.append("migrate")
if profile.get("requires_playwright_review") or "frontend_ui" in types:
    required.append("ui")

missing = [p for p in required if p not in phases_ok]
if missing:
    print(
        "require_commands_logged: missing successful log_command.sh runs for: "
        + ", ".join(missing),
        file=sys.stderr,
    )
    print(
        "Example: log_command.sh tests -- docker exec \\${COMPOSE_PROJECT_NAME}-backend-1 pytest ...",
        file=sys.stderr,
    )
    raise SystemExit(1)
print("require_commands_logged: ok")
PY
