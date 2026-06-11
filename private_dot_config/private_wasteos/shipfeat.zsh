# shipfeat — launch end-to-end feature ship agent in a new tmux window
# Canonical install: ~/.config/wasteos/shipfeat.zsh
# Usage: shipfeat <branch-name> <codex|claude|agent|cursor> [extra context...]

[[ -f "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/worktree.zsh" ]] && \
    source "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/worktree.zsh"

: "${SHIPFEAT_HOME:=$HOME/.config/wasteos/shipfeat}"
: "${SHIPFEAT_TOOLING:=$SHIPFEAT_HOME}"

_shipfeat_env_file="${HOME}/.config/wasteos/shipfeat.env"

_shipfeat_ensure_tooling() {
    if [[ ! -f "${SHIPFEAT_HOME}/SKILL.md" ]]; then
        echo "shipfeat: install not found at SHIPFEAT_HOME=${SHIPFEAT_HOME}" >&2
        return 1
    fi
}

_shipfeat_link_skills() {
    local skills_root="${HOME}/.config/wasteos/skills"
    mkdir -p "${HOME}/.cursor/skills" "${HOME}/.codex/skills" "${HOME}/.claude/skills" 2>/dev/null

    _shipfeat_link_one_skill() {
        local name=$1 src=$2
        [[ -e "$src" ]] || return 0
        for agent_dir in "${HOME}/.cursor/skills" "${HOME}/.codex/skills" "${HOME}/.claude/skills"; do
            local dest="${agent_dir}/${name}"
            rm -f "$dest" 2>/dev/null || true
            ln -sf "$src" "$dest" 2>/dev/null || true
        done
    }

    _shipfeat_link_one_skill wasteos-ship-feat "${SHIPFEAT_HOME}"
    _shipfeat_link_one_skill wasteos-mr-upload-photos "${skills_root}/wasteos-mr-upload-photos"
    _shipfeat_link_one_skill wasteos-mr-comment-watch "${skills_root}/wasteos-mr-comment-watch"
}

_shipfeat_render_prompt() {
    local branch=$1
    local skill_path=$2
    local tooling=$3
    local worktree=$4
    shift 4
    local extra_context="$*"

    cat <<EOF
MANDATORY: You must follow the wasteos-ship-feat skill in full before doing anything else.

Read and execute every phase in:
  ${skill_path}

Also invoke it as \$wasteos-ship-feat if your runtime supports skill commands.

Before editing code, read (in the feature worktree):
  - AGENTS.md
  - docs/steering/structure.md
  - docs/steering/architecture.md
  - docs/steering/conventions.md
  - docs/steering/frontend-ui-consistency.md
  - docs/steering/product.md (if product behaviour is in scope)
  - ~/.config/wasteos/code-review-standard.md

Then create (before implementation):
  - .shipfeat/context-summary.md — short scope summary
  - .shipfeat/feature-profile.json — tier + change_types + gates (see ${tooling}/templates/feature-profile.example.json)
  - Run: ${tooling}/scripts/generate_plan_from_profile.sh → .shipfeat/plan.md

Run \`shipfeat status\` (or ${tooling}/scripts/status.sh) before starting, before open_mr, after MR comments, and before claiming done.
Completion gate: \`shipfeat done\` must exit 0 before you tell the user the feature is finished.

MANDATORY (Phase 5b / MR review): Read and follow wasteos-mr-comment-watch:
  ${HOME}/.config/wasteos/skills/wasteos-mr-comment-watch/SKILL.md

When .shipfeat/pending-mr-comment-prompt.md exists, handle it before other work.
Never resolve GitLab threads before require_branch_pushed.sh passes.
Use resolve_mr_discussion.sh (not raw glab resolve). Run consume_mr_comment_prompt.sh when done.

MANDATORY (Phase 6 / any UI work): Read and follow wasteos-mr-upload-photos:
  ${HOME}/.config/wasteos/skills/wasteos-mr-upload-photos/SKILL.md

Complete .shipfeat/ui-review.md for frontend changes. Upload screenshots after the latest UI commit.
You must run upload_mr_screenshots.sh and require_mr_photos_uploaded.sh before shipfeat done.

SHIPFEAT_HOME=${tooling}
SHIPFEAT_TOOLING=${tooling}
SHIPFEAT_WORKTREE=${worktree}
Export these variables in your shell before running helper scripts from the skill.

Feature branch: ${branch}
EOF

    if [[ -n "$extra_context" ]]; then
        printf '\nUser context:\n%s\n' "$extra_context"
    fi
}

_shipfeat_run_script() {
    local script=$1
    _shipfeat_ensure_tooling || return 1
    if [[ ! -f "${SHIPFEAT_HOME}/.worktree.env" && -f "${PWD}/.worktree.env" ]]; then
        export SHIPFEAT_WORKTREE="$PWD"
    fi
    "${SHIPFEAT_HOME}/scripts/${script}"
}

shipfeat() {
    case "${1:-}" in
        status)
            _shipfeat_run_script status.sh
            return $?
            ;;
        done)
            _shipfeat_run_script done.sh
            return $?
            ;;
        repair)
            _shipfeat_run_script repair.sh
            return $?
            ;;
        review-diff)
            _shipfeat_run_script review_diff.sh
            return $?
            ;;
        help|--help|-h)
            cat <<EOF
Usage:
  shipfeat <branch> <codex|claude|agent|cursor> [context...]
      Launch tmux + agent + MR watcher in a feature worktree.

  shipfeat status       — print session, MR, watcher, plan, gates (from feature worktree)
  shipfeat done         — exit 0 only when all completion gates pass
  shipfeat repair       — init session, record MR, install Cursor hooks, status
  shipfeat review-diff  — second-pass diff review (Tier M/L); writes .shipfeat/review-findings*.md/json

Install: \${SHIPFEAT_HOME:-~/.config/wasteos/shipfeat}
Credentials: ~/.config/wasteos/shipfeat.env
EOF
            return 0
            ;;
    esac

    if (( $# < 2 )); then
        shipfeat help
        return 1
    fi

    _shipfeat_ensure_tooling || return 1

    local branch=$1
    local agent=$2
    shift 2

    case "$agent" in
        codex | claude | agent | cursor) ;;
        *)
            echo "shipfeat: agent must be codex, claude, agent, or cursor" >&2
            return 1
            ;;
    esac
    [[ "$agent" == cursor ]] && agent=agent

    local repo
    repo=$(_wt_repo_root) || {
        echo "shipfeat: run this inside a WasteOS repository worktree" >&2
        return 1
    }

    if [[ -z "$TMUX" ]]; then
        local session="ship-${branch//\//-}"
        session="${session:0:32}"
        echo "shipfeat: starting tmux session '${session}'..."
        tmux new-session -d -s "$session" -c "$PWD" \
            "shipfeat '$branch' '$agent' $*"
        tmux attach -t "$session"
        return
    fi

    local target
    target=$(_wt_worktree_path "$repo" "$branch")
    if [[ -z "$target" ]]; then
        echo "shipfeat: creating worktree for ${branch}..."
        command "$repo/deploy/setup_worktree.sh" "$branch" develop || return $?
        target=$(_wt_worktree_path "$repo" "$branch")
    fi
    [[ -n "$target" ]] || {
        echo "shipfeat: worktree path not found for ${branch}" >&2
        return 1
    }

    _shipfeat_link_skills

    local trust_script="${SHIPFEAT_HOME}/scripts/trust_worktree.sh"
    if [[ -x "$trust_script" ]]; then
        "$trust_script" "$target" || echo "shipfeat: warning — could not pre-trust ${target}" >&2
    fi

    local skill_md="${SHIPFEAT_HOME}/SKILL.md"
    local run_dir="${target}/.shipfeat"
    mkdir -p "$run_dir/screenshots"
    _shipfeat_render_prompt "$branch" "$skill_md" "$SHIPFEAT_HOME" "$target" "$@" >"${run_dir}/prompt.md"

    local runner="${SHIPFEAT_HOME}/scripts/run-agent.sh"
    chmod +x "${SHIPFEAT_HOME}/scripts/"*.sh 2>/dev/null || true

    local window_name="ship-${branch##*/}"
    window_name="${window_name:0:32}"

    tmux new-window -n "$window_name" -c "$target"
    local win=$TMUX_WINDOW

    tmux split-window -h -t "$win" -c "$target" -l 38%
    tmux split-window -v -t "${win}.1" -c "$target" -l 65%

    local agent_tmux_target="${TMUX}:${win}.1"
    "${SHIPFEAT_HOME}/scripts/init_session.sh" "$branch" "$agent" "$target" "$agent_tmux_target"
    "${SHIPFEAT_HOME}/scripts/install_cursor_hooks.sh"

    local watcher="${SHIPFEAT_HOME}/scripts/watch_mr_comments.sh"

    tmux send-keys -t "${win}.0" "nvim" Enter
    tmux send-keys -t "${win}.1" \
        "export SHIPFEAT_HOME='${SHIPFEAT_HOME}' SHIPFEAT_TOOLING='${SHIPFEAT_HOME}' && cd '${target}' && '${runner}' '${agent}' '${target}'" Enter
    tmux send-keys -t "${win}.2" \
        "export SHIPFEAT_HOME='${SHIPFEAT_HOME}' && cd '${target}' && '${watcher}'" Enter

    tmux select-pane -t "${win}.1"

    echo "shipfeat: branch=${branch} agent=${agent}"
    echo "shipfeat: feature worktree=${target}"
    echo "shipfeat: install=${SHIPFEAT_HOME}"
    echo "shipfeat: prompt=${run_dir}/prompt.md"
    echo "shipfeat: MR watcher → tmux pane ${win}.2; Cursor dispatch via .cursor/hooks (stop: touch .shipfeat/stop-mr-watch)"
    if [[ -f "$_shipfeat_env_file" ]]; then
        echo "shipfeat: credentials → ${_shipfeat_env_file}"
    else
        echo "shipfeat: warning — no ${_shipfeat_env_file} (UI login phase will fail)"
    fi
}

# Ctrl-X Ctrl-S: shipfeat (prompts for branch + agent in the widget below)
shipfeat-widget() {
    vared -p 'branch: ' -c _shipfeat_branch
    [[ -n "$_shipfeat_branch" ]] || return 0
    vared -p 'agent (codex|claude|agent): ' -c _shipfeat_agent
    [[ -n "$_shipfeat_agent" ]] || return 0
    BUFFER="shipfeat ${_shipfeat_branch} ${_shipfeat_agent}"
    zle accept-line
}
zle -N shipfeat-widget
bindkey -M viins '^X^S' shipfeat-widget
bindkey -M vicmd '^X^S' shipfeat-widget

compdef '_wt_branch_complete' shipfeat 2>/dev/null || true
