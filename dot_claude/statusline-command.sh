#!/bin/sh
# Claude Code status line — robbyrussell-inspired

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')

# Current directory (basename only, like %c in robbyrussell)
dir=$(basename "$cwd")

# Git branch and dirty state
git_branch=""
git_info=""
if git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
    if git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | grep -q .; then
        git_info=" $(printf '\033[1;34m')git:($(printf '\033[0;31m')${git_branch}$(printf '\033[1;34m')) $(printf '\033[0;33m')✗$(printf '\033[0m')"
    else
        git_info=" $(printf '\033[1;34m')git:($(printf '\033[0;31m')${git_branch}$(printf '\033[1;34m'))$(printf '\033[0m')"
    fi
fi

# Arrow: green normally
arrow="$(printf '\033[1;32m')➜$(printf '\033[0m')"

printf "%s %s%s%s" \
    "$arrow" \
    "$(printf '\033[0;36m')${dir}$(printf '\033[0m')" \
    "$git_info" \
    ""
