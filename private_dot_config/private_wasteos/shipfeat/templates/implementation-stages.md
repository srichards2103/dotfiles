# {{FEATURE_TITLE}} — Implementation Stages

**Branch:** `{{BRANCH}}`
**Design:** `design.md` — source of truth for scope. This file sequences work into reviewable stages.
**Companion:** `goal-loop-prompt.md` — pasteable agent loop over these stages.
**Review gate:** `../../steering/code-review-standard.md` (or `~/.config/wasteos/code-review-standard.md`).

---

## How this document is used

1. Find the **first unchecked stage** below.
2. Implement only that stage (cite design sections in Notes).
3. Self-review against `code-review-standard.md`; fix violations.
4. Run stage acceptance checks (tests, `manage.py check`, `makemigrations --check` as applicable).
5. **Commit** one logical commit per stage.
6. **Tick the box** and append commit SHA + one-line note in the Progress ledger.
7. Repeat until all stages are checked, then run the **Terminal gate**.

Do not tick a stage until its gate passes. Do not skip ahead.

---

## Stage 0 — Baseline & harness

- [ ] Capture baseline / verification harness (if applicable)
  - Acceptance:
  - Notes:

---

## Stage 1 — {{STAGE_1_TITLE}}

- [ ] {{STAGE_1_TITLE}}
  - Design refs:
  - Acceptance:
  - Notes:

---

## Stage 2 — {{STAGE_2_TITLE}}

- [ ] {{STAGE_2_TITLE}}
  - Design refs:
  - Acceptance:
  - Notes:

---

## Terminal gate

- [ ] Full backend test suite for touched apps
- [ ] Frontend build + lint (if UI changed)
- [ ] OpenAPI regenerated with no drift (if API changed)
- [ ] Migrations clean / rebased on develop
- [ ] `db_deploy_and_restore_fast` green (if profile requires)
- [ ] `shipfeat review-diff` findings dispositioned
- [ ] MR open, screenshots on MR (if UI), no unresolved discussions

---

## Progress ledger

| Stage | State | Commit | Note |
|-------|-------|--------|------|
| 0 | pending | | |
| 1 | pending | | |
| 2 | pending | | |
