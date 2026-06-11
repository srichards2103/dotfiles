# MR review comment — required agent behaviour

You were dispatched because a **new human GitLab MR comment** arrived on this branch. Read every comment in the batch below (and any inline context on GitLab).

Follow `~/.config/wasteos/code-review-standard.md` for all code changes.

## Hard rules

### 1. When the feedback requires any change on the branch

This includes **code, UI, deleting files, or any tracked git change** (even under `.shipfeat/`).

You **must** complete **all** of these **in order** before you stop:

1. **Implement** the change.
2. **Run tests** when you touched backend or risky areas — `docker exec ${COMPOSE_PROJECT_NAME}-backend-1 pytest …` from `.worktree.env`.
3. **Commit** on the feature branch.
4. **Push** to origin and verify:

   ```bash
   git push origin "$(git branch --show-current)"
   "${SHIPFEAT_HOME:-$HOME/.config/wasteos/shipfeat}/scripts/require_branch_pushed.sh"
   ```

   **`require_branch_pushed.sh` must exit 0** before you reply or resolve on GitLab.

5. **UI feedback** — capture Playwright screenshots and upload:

   ```bash
   "${SHIPFEAT_HOME:-$HOME/.config/wasteos/shipfeat}/scripts/upload_mr_screenshots.sh" \
     "$(git branch --show-current)" \
     .shipfeat/screenshots \
     "Addressing MR feedback — $(git branch --show-current)"
   ```

6. **Reply on GitLab** in the **same discussion thread** (what changed + commit SHA on origin). For **visible UI changes** (tables, columns, labels, layout), upload a screenshot and **link it in that thread reply** — not only a top-level MR note.

7. **Resolve the thread** only after steps 4–6 succeeded — use the helper (do not call resolve APIs by hand):

   ```bash
   "${SHIPFEAT_HOME:-$HOME/.config/wasteos/shipfeat}/scripts/resolve_mr_discussion.sh" \
     <mr_iid> <discussion_id> -m "Fixed in <sha>: …"
   ```

   `resolve_mr_discussion.sh` runs `require_branch_pushed.sh` first and **will refuse** to resolve if anything is unpushed.

### 2. When you cannot or should not change the branch

Examples: requirement is ambiguous, needs product decision, or a question you cannot answer from the repo.

You **must**:

1. **Reply on GitLab** with a **clear question** (or what is blocking).
2. **Leave the discussion unresolved** — do **not** call `resolved=true`.
3. **Do not push** an empty or no-op commit.

### 3. Never do this

- Delete, edit, or add **tracked** files locally without **commit + push**.
- Resolve a thread before `require_branch_pushed.sh` passes.
- Resolve without a GitLab reply.
- Resolve when you only asked a question and shipped no change.
- Run `consume_mr_comment_prompt.sh` while the branch is ahead of origin or dirty.
- Skip UI screenshots for visual feedback.

## Clear the queue

Only after every comment in the batch is handled **and** the branch is pushed:

```bash
"${SHIPFEAT_HOME:-$HOME/.config/wasteos/shipfeat}/scripts/require_branch_pushed.sh"
"${SHIPFEAT_HOME:-$HOME/.config/wasteos/shipfeat}/scripts/consume_mr_comment_prompt.sh"
```

`consume_mr_comment_prompt.sh`:

1. Runs `require_branch_pushed.sh` (exits 1 if unpushed or dirty).
2. Verifies each `discussion_id` in `.shipfeat/mr-comment-active-batch.json` is **resolved on GitLab**, or listed in `.shipfeat/human-blocked-discussions.json` **with a reply from you**.
3. Archives the batch and clears the pending prompt.

Do not run consume while any thread in the batch is still unresolved without a blocking reply.

## Completion checklist

```text
[ ] Read every comment in this batch
[ ] Chosen path: branch change OR clarifying question only
[ ] If branch change: committed
[ ] If branch change: pushed — require_branch_pushed.sh passed
[ ] If UI: screenshots uploaded to MR
[ ] GitLab: reply on each thread
[ ] GitLab: resolve only via resolve_mr_discussion.sh (after push)
[ ] consume_mr_comment_prompt.sh succeeded
```
