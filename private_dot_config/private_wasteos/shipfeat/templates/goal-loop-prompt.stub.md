# Goal-Loop Prompt — {{FEATURE_TITLE}}

Paste the block below to drive the implementation loop on branch `{{BRANCH}}`.

---

```
You are implementing {{FEATURE_TITLE}} on branch `{{BRANCH}}`.

Read before coding:
- docs/specs/{{FEATURE_SLUG}}/design.md
- docs/specs/{{FEATURE_SLUG}}/implementation-stages.md
- docs/steering/code-review-standard.md

Loop:
1. Open implementation-stages.md — first unchecked stage only.
2. Implement that stage; self-review against code-review-standard.md.
3. Run stage acceptance checks; log with: log_command.sh <phase> -- <cmd>
4. Commit; tick the stage + update Progress ledger (SHA + note).
5. Repeat until Terminal gate is complete.
6. Run: shipfeat review-diff — disposition every finding in .shipfeat/review-findings-status.json
7. Run: shipfeat done
```
