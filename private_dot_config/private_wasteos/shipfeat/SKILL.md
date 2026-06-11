---
name: wasteos-ship-feat
description: End-to-end WasteOS feature delivery in a worktree — feature profile, scenario plan, implement with code-review-standard gate, drst, docker pytest, open GitLab MR, Playwright UI review + screenshots, MR comment loop. Use when shipfeat launches you or the user says ship feature / wasteos-ship-feat.
disable-model-invocation: true
argument-hint: '<feature-branch> [extra context from user]'
---

# WasteOS ship feature (end-to-end)

You are running the full feature-ship workflow for branch **$ARGUMENTS** (branch name is the first token; remaining text is optional user context).

Work only inside the **feature worktree** (`SHIPFEAT_WORKTREE` in the prompt, or current directory with `.worktree.env`). Do not skip phases. Do not open the MR until backend tests pass.

Helper scripts live in the **global shipfeat install** (`SHIPFEAT_HOME`, default `~/.config/wasteos/shipfeat`). Always run them from the feature worktree root.

**Run `shipfeat status` before starting, before `open_mr.sh`, after MR comments, and before claiming done.**  
**Run `shipfeat done` — it must exit 0 before you tell the user the feature is finished.**

If you started outside `shipfeat` tmux (e.g. Cursor only): run `shipfeat repair` once from the worktree root.

## Credentials (local only)

Before Playwright login, `source ~/.config/wasteos/shipfeat.env` if the file exists.

- `SHIPFEAT_APP_EMAIL`
- `SHIPFEAT_APP_PASSWORD`
- optional `SHIPFEAT_APP_HOST` (default `wskips.encore.localhost`)

Never commit credentials.

## Phase 0 — Classify and plan (mandatory)

1. Read user context and matching `docs/specs/*/design.md`.
2. Read repo steering: `AGENTS.md`, `docs/steering/structure.md`, `docs/steering/architecture.md`, `docs/steering/conventions.md`, `docs/steering/frontend-ui-consistency.md`, and `~/.config/wasteos/code-review-standard.md`.
3. Write `.shipfeat/context-summary.md` (short scope).
4. Write `.shipfeat/feature-profile.json` (copy from `${SHIPFEAT_HOME}/templates/feature-profile.example.json` and edit):

   - `tier`: `S` | `M` | `L`
   - `change_types`: e.g. `backend_api`, `frontend_ui`, `model_migration`, `permissions`, `etl_import`, `billing_or_pricing`, `async_worker`, `infra_ci`
   - boolean gates: `requires_frontend_build`, `requires_playwright_review`, `requires_openapi_regen`, `requires_db_restore`, `requires_domain_parity_check`, `requires_external_review`

5. Generate the plan from templates (do not invent a generic checklist):

   ```bash
   "${SHIPFEAT_HOME:?}"/scripts/generate_plan_from_profile.sh
   ```

6. **Tier L only:** run `scaffold_implementation_stages.sh <feature-slug>` (or set `feature_slug` in the profile so `generate_plan_from_profile.sh` runs it). Maintain `docs/specs/<feature>/implementation-stages.md` as the committed durable ledger.

7. If `frontend_ui` or `requires_playwright_review`: copy `${SHIPFEAT_HOME}/templates/ui-review.md` → `.shipfeat/ui-review.md`.

Do not mark tasks complete in `.shipfeat/plan.md` until the work is actually done.

## Phase 1 — Scope (within profile)

Search the codebase for patterns required by your `change_types` (see generated plan sections). Adjust `.shipfeat/plan.md` only if the profile missed a concrete file or test path — do not drop template tasks.

## Phase 2 — Implement (task by task)

For each unchecked task in `.shipfeat/plan.md`:

1. Implement the smallest vertical slice.
2. Self-review against `~/.config/wasteos/code-review-standard.md`.
3. Fix before moving on.
4. Commit logical chunks.

Migrations: `.agents/skills/backwards-compatible-migrations/SKILL.md`.

## Phase 3 — Stack + database

When `requires_db_restore` is true in the profile (or migrations / import):

```bash
cd "${SHIPFEAT_WORKTREE:-$PWD}"
sed -i '' 's/^BOOTSTRAP_WSKIPS=.*/BOOTSTRAP_WSKIPS=True/' dev.env
sed -i '' 's/^RUN_MIGRATIONS=.*/RUN_MIGRATIONS=True/' dev.env
./deploy/db_deploy_and_restore_fast.sh
```

Then:

```bash
"${SHIPFEAT_HOME:?}"/scripts/wait_for_backend_ready.sh
```

Readiness: `http://127.0.0.1:${BACKEND_PORT}/api/common/readyz/` (body `READY`).

## Phase 4 — Tests (log evidence)

Record every important command in `.shipfeat/commands.jsonl`:

```bash
"${SHIPFEAT_HOME:?}"/scripts/log_command.sh tests -- \
  docker exec "${COMPOSE_PROJECT_NAME}-backend-1" pytest <paths from plan>
```

Also log when applicable:

```bash
"${SHIPFEAT_HOME:?}"/scripts/log_command.sh drst -- ./deploy/db_deploy_and_restore_fast.sh
"${SHIPFEAT_HOME:?}"/scripts/log_command.sh frontend -- <frontend build/lint command>
"${SHIPFEAT_HOME:?}"/scripts/log_command.sh ui -- "${SHIPFEAT_HOME}/scripts/upload_mr_screenshots.sh" ...
```

`shipfeat done` runs `require_commands_logged.sh` against your feature profile.

## Phase 5 — GitLab MR

```bash
"${SHIPFEAT_HOME:?}"/scripts/open_mr.sh
```

`open_mr.sh` **fails** if `session.json` cannot be initialized or `record_mr_open.sh` cannot set `mr_iid` / `mr_url`.

Confirm with `shipfeat status` or `glab mr view`.

## Phase 5b — MR comment watcher

Follow **`wasteos-mr-comment-watch`**. Comments are **queued** per note (`.shipfeat/mr-comments/queued/`, ledger `.shipfeat/mr-comment-ledger.jsonl`). Push before resolve; use `resolve_mr_discussion.sh`; then `consume_mr_comment_prompt.sh` when the batch is handled (consume verifies GitLab resolution).

## Phase 6 — UI review + screenshots (when profile requires)

1. Complete `.shipfeat/ui-review.md` (walkthrough checklist + findings).
2. Capture screenshots (1920×1080, playwright-cli).
3. Upload:

   ```bash
   export SHIPFEAT_UI_ROUTES_REVIEWED="/route1,/route2"   # optional, stored in marker
   "${SHIPFEAT_HOME:?}"/scripts/upload_mr_screenshots.sh \
     "$(git branch --show-current)" \
     .shipfeat/screenshots \
     "UI verification — $(git branch --show-current)"
   "${SHIPFEAT_HOME:?}"/scripts/require_mr_photos_uploaded.sh
   ```

Marker includes `commit_sha`; re-upload if frontend changed after upload.

## Phase 7 — Review diff (Tier M / L)

```bash
shipfeat review-diff
```

Review output: `.shipfeat/review-findings.md`. Disposition every item in `.shipfeat/review-findings-status.json` (`accepted_fixed`, `accepted_not_fixed_with_reason`, `rejected_with_reason`, `needs_human`). For a clean review with no issues, add one finding: `id: "none"`, `disposition: "accepted_fixed"`.

## Completion

```bash
shipfeat done
```

`done` checks: feature profile, plan tasks checked, `commands.jsonl` gates, clean pushed branch, MR session, MR comment queue empty, batch consumed, no unresolved GitLab discussions, UI review + screenshots when required, Tier L `implementation-stages.md`, Tier M/L review diff dispositioned.

Then tell the user: branch, MR URL, test summary, screenshot list, MR note link.
