# Shipfeat diff review

Review the git diff against `develop` for this feature branch.

Read:
- `.shipfeat/feature-profile.json`
- `.shipfeat/plan.md`
- `docs/steering/code-review-standard.md`
- Any `docs/specs/*/design.md` relevant to the branch

Write findings to `.shipfeat/review-findings.md` using this structure:

```markdown
# Review findings

## Critical
- [ ] ...

## Major
- [ ] ...

## Minor
- [ ] ...
```

The implementing agent must disposition each finding in `.shipfeat/review-findings-status.json`:

```json
{
  "reviewed_at": "...",
  "base_ref": "develop",
  "head_sha": "...",
  "findings": [
    {
      "id": "1",
      "severity": "major",
      "summary": "...",
      "disposition": "accepted_fixed | accepted_not_fixed_with_reason | rejected_with_reason | needs_human",
      "note": ""
    }
  ]
}
```

Do not mark shipfeat done until every finding has a disposition.
