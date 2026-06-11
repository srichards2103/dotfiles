#!/usr/bin/env bash
# shellcheck shell=bash
# Resolve the active feature worktree (cwd or SHIPFEAT_WORKTREE), not the tooling install.

shipfeat_worktree_root() {
  if [[ -f "${PWD}/.worktree.env" ]]; then
    printf '%s\n' "$PWD"
    return 0
  fi
  if [[ -n "${SHIPFEAT_WORKTREE:-}" && -f "${SHIPFEAT_WORKTREE}/.worktree.env" ]]; then
    printf '%s\n' "$SHIPFEAT_WORKTREE"
    return 0
  fi
  echo "shipfeat: run from the feature worktree root (or set SHIPFEAT_WORKTREE)" >&2
  return 1
}

shipfeat_tooling_root() {
  local tooling="${SHIPFEAT_HOME:-${SHIPFEAT_TOOLING:-$HOME/.config/wasteos/shipfeat}}"
  if [[ ! -f "${tooling}/SKILL.md" ]]; then
    echo "shipfeat: install not found at ${tooling}" >&2
    return 1
  fi
  printf '%s\n' "$tooling"
}
