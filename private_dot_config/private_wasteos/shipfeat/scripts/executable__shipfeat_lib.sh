#!/usr/bin/env bash
# Shared helpers for shipfeat scripts (source only).
set -euo pipefail

shipfeat_home() {
  shipfeat_tooling_root
}

shipfeat_profile_path() {
  local root
  root="$(shipfeat_worktree_root)"
  printf '%s/.shipfeat/feature-profile.json\n' "$root"
}

shipfeat_session_path() {
  local root
  root="$(shipfeat_worktree_root)"
  printf '%s/.shipfeat/session.json\n' "$root"
}

shipfeat_head_sha() {
  git -C "$(shipfeat_worktree_root)" rev-parse HEAD
}

shipfeat_frontend_changed_since() {
  local since_sha="$1"
  local root
  root="$(shipfeat_worktree_root)"
  git -C "$root" diff --name-only "${since_sha}..HEAD" -- frontend/ 2>/dev/null | grep -q .
}
