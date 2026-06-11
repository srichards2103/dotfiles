#!/usr/bin/env bash
# One-shot: pre-trust every ~/code/wasteos* directory (existing worktrees).
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
trust="${script_dir}/trust_worktree.sh"
[[ -x "$trust" ]] || { echo "missing ${trust}" >&2; exit 1; }

shopt -s nullglob
for dir in "${HOME}/code"/wasteos*; do
  [[ -d "$dir" ]] || continue
  echo "trust: ${dir}"
  "$trust" "$dir"
done

echo "done."
