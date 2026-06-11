# Agent Code Review Standard

This document defines the review gate that must be applied before any agent-generated code is considered complete. The goal is not merely to make code pass tests, but to ensure the implementation is consistent with the existing repository architecture, naming conventions, domain modelling approach, API contracts, frontend conventions, and maintainability standards.

Every code-producing agent must review its own changes against this document before presenting the result.

## Core Principle

Generated code should look as though it was written by a careful maintainer of this repository, not by an external tool trying to satisfy the immediate prompt.

Code that technically works but introduces avoidable inconsistency, hard-coded behaviour, unclear naming, misplaced validation, unnecessary abstraction, duplicated domain knowledge, defensive noise, permission gaps, or architectural drift is incomplete.

Prefer code that is explicit, boring, readable, domain-aligned, and consistent with nearby code.

## 1. Imports Must Belong at the Top of the File

Imports should always be placed at the top of the file unless there is an exceptional reason not to do so.

Local imports inside functions, methods, serializers, services, views, or React components are a smell. They are sometimes used to dodge circular dependencies, but circular dependencies usually indicate that the module boundaries are wrong.

Before accepting a local import, ask:

```text
Is this local import genuinely necessary, or is it hiding a circular dependency?
Can the dependency direction be reversed?
Should shared logic be moved into a lower-level module?
Should this function live somewhere else?
```

A local import is only acceptable when there is a clear, concrete reason, such as avoiding an expensive optional dependency or preventing a genuine import-time side effect. It should not be used as a default fix for poor structure.

## 2. API Views Must Stay Thin

API views should not become orchestration layers.

The normal shape of a backend endpoint should be:

```text
Authenticate / authorize at the boundary.
Deserialize and validate request shape.
Call one service-layer operation.
Serialize the response.
Return the response.
```

API views should not contain business workflows, multi-step ORM logic, branch-access logic, billing logic, state transitions, or large try/except blocks that merely catch and re-raise service exceptions.

Avoid this pattern:

```python
class SomeApi(APIView):
    def post(self, request):
        # lots of ORM access
        # business validation
        # state transitions
        # manual error mapping
        # response construction
```

Prefer this pattern:

```python
class SomeApi(APIView):
    def post(self, request):
        serializer = SomeInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        result = some_service_function(
            user=request.user,
            **serializer.validated_data,
        )

        return Response(SomeOutputSerializer(result).data)
```

In this repository, avoid combining unrelated actions into the same API class or endpoint. A view should represent one clear API operation. Do not combine list/create, update/delete, preview/generate, or unrelated actions merely because they touch the same model.

The review question is:

```text
Is this API view only adapting HTTP to the application/service layer?
```

If not, move the logic down.

## 3. Serializers Shape Contracts; Services Own Business Logic

Serializers should mainly validate and shape the API contract. They should answer questions such as:

```text
Is this field present?
Is this field the right primitive type?
Is this choice one of the model-defined valid choices?
Is this nested payload structurally valid?
Can this payload be safely passed into the application layer?
```

Serializers should not be the primary home for business rules.

Business validation belongs in the service layer. Services should answer questions such as:

```text
Is this state transition allowed?
Can this job be completed in its current state?
Is this account allowed to use this payment method?
Does this operation violate branch access?
Does this operation violate billing, invoicing, or operational rules?
```

The service layer should protect the application even if called from somewhere other than the API endpoint.

If a serializer starts computing business outcomes, running multi-step queries, checking permissions, or orchestrating writes, it is no longer really a serializer.

## 4. Services Own Writes, Authorization, and Workflows

All meaningful writes should go through service-layer functions.

Services should own:

```text
Create/update/delete workflows.
Permission and branch-access checks.
State transitions.
Cross-model validation.
Multi-step operations.
Billing, invoicing, payment, and job lifecycle rules.
Transaction boundaries.
```

A service function should expose a clear application operation, not a vague data manipulation helper.

Prefer:

```python
complete_bridge_ticket(...)
void_invoice(...)
create_recurring_charge(...)
generate_invoice_batch(...)
apply_customer_payment(...)
```

Avoid:

```python
process_data(...)
handle_update(...)
resolve(...)
do_action(...)
```

## 5. Validation Should Happen Once at the Agreed Boundary

Do not scatter defensive validation throughout the call chain.

Validate API shape at the serializer boundary. Validate business rules at the service boundary. Enforce unrepresentable states at the model/database boundary.

Avoid peppering code with repeated guards such as:

```python
if value is None:
    return default

if not hasattr(obj, "field"):
    return None

if maybe_list:
    ...
```

These often hide bad assumptions, weak contracts, or invalid states that should have been prevented earlier.

The review question is:

```text
Is this check enforcing a real boundary, or is it defensive noise compensating for uncertainty?
```

If the value should always exist, enforce that at creation time. If the state should be impossible, enforce it with a model constraint. If the caller violated the contract, raise loudly rather than silently continuing.

## 6. Prefer Model Invariants Over `clean()` Spaghetti

When a business rule describes an invalid state that should never exist, prefer a model/database constraint over scattered runtime checks.

Ask:

```text
Should this state be representable at all?
```

If the answer is no, use one of:

```text
CheckConstraint
UniqueConstraint
null=False
blank=False
model field validators
explicit model-level invariant
```

Do not rely on service conditionals, serializer validation, or `clean()` methods alone when the database can make the invalid state impossible.

`clean()` should remain thin. It should not become a large second service layer.

For cross-field invariants, consider whether a `CheckConstraint` can express the rule. For parent/child invariants, avoid child models poking at parent internals with `hasattr`. Add an explicit method on the parent instead.

Avoid:

```python
if hasattr(parent, "service_type"):
    ...
```

Prefer:

```python
parent.validate_primitive_code(code)
```

## 7. Do Not Hard-Code TextChoices Values

When a model field is backed by a Django `TextChoices` class, serializers and services must use the model-defined choices rather than hard-coded string lists.

Correct serializer pattern:

```python
class SomeSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=SomeModel.Status.choices)
```

Incorrect pattern:

```python
class SomeSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=["draft", "active", "cancelled"])
```

Hard-coded lists duplicate domain knowledge, drift from the model over time, and make refactors fragile.

## 8. Services Should Use TextChoices Constants and `.values`

Service-layer code should not compare against magic strings when a model `TextChoices` class exists.

Correct pattern:

```python
if status == SomeModel.Status.ACTIVE:
    ...
```

For membership checks, use `.values` where applicable.

Correct pattern:

```python
if status not in SomeModel.Status.values:
    raise ValidationError("Invalid status.")
```

Incorrect pattern:

```python
if status not in ["draft", "active", "cancelled"]:
    raise ValidationError("Invalid status.")
```

The model should remain the canonical source of valid symbolic values.

## 9. Keep Static Choices and Dynamic Configurable Choices Distinct

Do not blur the distinction between static backend-controlled choices and database-configurable choices.

Use `TextChoices` when the value controls backend behaviour, branching logic, state machines, permissions, billing semantics, or domain invariants.

Use a configurable choice model when the value is user-administered business configuration, usually for dropdowns, display, categorisation, filtering, or branch/customer-specific configuration.

Do not replace a `ForeignKey` to a configurable choice model with a raw integer or string field. Do not replace a behavioural `TextChoices` field with a database-backed choice merely because it appears as a dropdown in the UI.

The review question is:

```text
Is this value part of the software’s domain logic, or is it user-configurable business data?
```

## 10. Avoid Magic Strings, Magic Numbers, and Duplicated Domain Constants

Do not introduce raw string literals or numeric constants for values that already exist as model fields, choices, settings, constants, enums, or domain-level definitions.

Incorrect pattern:

```python
if invoice_level == "site":
    ...
```

Correct pattern:

```python
if invoice_level == Account.InvoiceLevel.SITE:
    ...
```

Hard-coded literals are especially dangerous in state, status, payment, invoice, job, route, material, branch, permission, service, and pricing logic.

The review question is:

```text
Is this literal value already represented somewhere canonical?
```

If yes, use the canonical representation.

## 11. Frontend Must Not Hard-Code Backend-Owned Enums

The frontend should not hard-code option lists, enum values, labels, or backend-owned status mappings when the backend owns those values.

Avoid:

```tsx
const STATUS_OPTIONS = [
    { value: 'draft', label: 'Draft' },
    { value: 'active', label: 'Active' },
];
```

Prefer consuming options from the API, generated schema, or a shared contract.

If the backend owns the domain, the frontend should consume the contract. It should not independently recreate the domain.

The review question is:

```text
Will this frontend value drift if the backend choices change?
```

If yes, remove the hard-coding.

## 12. Use Explicit Nested Serializers for Structured Data

Do not use loose `ListField(DictField())` or undocumented dictionary shapes for structured API responses unless the shape is genuinely arbitrary.

Avoid:

```python
sample_recipients = serializers.ListField(
    child=serializers.DictField()
)
```

Prefer:

```python
class SampleRecipientSerializer(serializers.Serializer):
    email = serializers.EmailField()
    name = serializers.CharField()
    status = serializers.ChoiceField(choices=RecipientStatus.choices)

class BulkEmailPreviewSerializer(serializers.Serializer):
    sample_recipients = SampleRecipientSerializer(many=True)
```

Structured API responses should be explicit, typed, documented, and reflected in the OpenAPI schema.

After API contract changes, regenerate or check the OpenAPI artifact.

## 13. Branch Access and Permissions Must Be Checked in Services

Every create, update, delete, generation, posting, voiding, billing, bridge, pricing, payment, and job operation on branch-owned records must check branch access in the service layer.

Do not rely only on frontend route guards, API permission classes, or queryset filtering.

Service-layer checks should happen before writes and before expensive queries where possible.

The review question is:

```text
Can this user perform this operation on this branch-owned resource?
```

For write paths, the pattern should be explicit:

```python
if branch_id not in user.branch_ids:
    raise PermissionDenied(...)
```

or the repository’s equivalent branch-access helper.

Separate these two concepts:

```text
Does the resource state allow this action?
Is the current user permitted to perform this action?
```

Both must be true.

## 14. Backend Should Derive Permission-Aware UI Affordances

Frontend affordances such as `can_void`, `can_take_payment`, `can_edit`, `can_delete`, `can_invoice`, and `can_complete` should be derived by the backend when they depend on domain state plus user permissions.

The frontend should not infer permission-sensitive actions using partial local state.

Avoid:

```tsx
const canVoid = ticket.status === 'completed';
```

Prefer receiving:

```tsx
ticket.can_void;
```

from a backend serializer that knows both the ticket state and the current user’s permissions.

The frontend may still hide or disable controls, but the backend must remain authoritative.

## 15. Permissions Should Distinguish Loading, Denied, and Missing Data

Permission-gated frontend routes must distinguish:

```text
Permissions are still loading.
Permissions loaded and access is denied.
The requested resource does not exist.
The user is allowed but the data request failed.
```

Do not redirect authorized users merely because permission data is temporarily stale or loading.

## 16. Services Should Express Domain Logic, Not API Formatting

Services should not return large API-shaped dictionaries unless that is clearly the established local pattern and genuinely appropriate.

As a default, services should perform domain operations and return domain objects, querysets, dataclasses, simple result objects, or explicitly named DTOs. Serializers should own response formatting and API representation.

The review question is:

```text
Is this formatting logic here because it belongs to the domain, or because the API response happens to need this shape?
```

If the answer is “because the frontend/API needs this shape,” the logic probably belongs in a serializer or presentation layer.

## 17. One Concept Should Have One Owner

Do not re-encode the same domain mapping in multiple places.

Before writing a helper that maps one domain concept to another, search for an existing canonical function.

Examples of mappings that should not be duplicated:

```text
charge scope → account/site/job
job line type → billing primitive
ticket → invoiceability
branch-owned object → branch access check
payment method → payment behaviour
invoice level → grouping behaviour
```

If a concept already has a resolver, use it. If the resolver is in the wrong place, move it to the owning module rather than creating a second idiom.

The review question is:

```text
If this domain rule changes, how many files would need to be edited?
```

The answer should usually be one.

## 18. Remove Thin Wrappers That Add No Semantics

Do not create wrapper functions that merely rename another function call without adding meaning, validation, transaction handling, or a useful abstraction boundary.

Avoid:

```python
def get_invoice_lines(invoice):
    return fetch_invoice_lines(invoice)
```

A wrapper is justified only when it introduces a meaningful domain phrase, stabilises an interface, adds validation, or hides implementation detail that callers should not know.

The review question is:

```text
Does this wrapper make the code easier to understand, or does it only add another jump?
```

## 19. Helper Functions Are Not Automatically Good

Do not break code into helper functions merely to make the top-level function shorter.

A helper function is justified when it improves readability, names a real domain concept, is reused in multiple places, isolates complex logic, or creates a meaningful test boundary.

A helper function is suspicious when it:

```text
Is used only once.
Simply wraps one or two obvious lines.
Has a vague name.
Forces the reader to jump around the file.
Hides important logic behind unnecessary indirection.
Exists only because the agent reflexively decomposed the code.
```

Single-use helper functions are not forbidden, but they must earn their existence. The standard is readability, not arbitrary decomposition.

Prefer direct, linear code when the operation is easier to understand in one place.

## 20. Avoid Both Over-Abstraction and Giant Functions

The desired code shape is neither a forest of tiny one-use helpers nor a 600-line god function.

Inline code when:

```text
The logic is called once.
The helper name does not clarify a real concept.
The helper merely wraps a direct call.
Inlining makes the operation easier to read.
```

Extract code when:

```text
The function has multiple responsibilities.
The code has repeated domain logic.
The nesting is becoming difficult to follow.
The extracted concept has a strong name.
The extracted unit is independently testable.
```

For backend services, prefer a clear main service function near the top of the file, with private helpers below in order of use.

For React, prefer presentational subcomponents and hooks when a component is carrying data loading, mutation logic, form state, rendering, and conditional UI all at once.

## 21. Naming Is a Code Review Issue

Function, variable, class, and module names must describe the domain purpose of the code.

Vague names such as `resolve`, `source`, `handle`, `process`, `data`, `payload`, `item`, `obj`, `config`, `preview`, or `result` should be treated as smells unless the surrounding context makes their meaning obvious.

Avoid names like:

```python
resolve_status(...)
process_data(...)
handle_item(...)
get_source(...)
```

Prefer names that expose the business meaning:

```python
determine_invoice_level(...)
apply_credit_hold(...)
build_service_price_lines(...)
calculate_excess_weight_charge(...)
validate_job_can_be_completed(...)
invoice_bridge_ticket(...)
cascade_void_jobs_for_failed_bin_delivery(...)
```

Name by resource and action where possible.

A well-named function should reduce the amount of code the reader needs to inspect. A poorly named function makes the codebase feel larger than it is.

The review question is:

```text
Would a maintainer understand what this function does from its name without opening the body?
```

If not, rename it.

## 22. Put Code in the Owning Module

Code should live in the module that owns the domain concept.

Do not put bridge permissions in invoices, payment concepts in customers, pricing rules in views, or invoice-generation logic in projection code unless that is genuinely where the domain responsibility belongs.

The review question is:

```text
Which app owns this concept?
```

If the answer is not the current module, move the code.

## 23. Preview and Generation Must Use the Same Rules

If the system has a preview path and a generation/persistence path, they must agree on:

```text
Inputs.
Date fields.
Validation rules.
Eligibility rules.
Permission checks.
Grouping logic.
Deduplication logic.
Model invariants.
```

A preview that succeeds while generation fails is a serious pipeline bug.

Intermediate projection objects must either satisfy the same invariants as the persisted models or be validated before preview results are shown.

The review question is:

```text
Could preview pass while generation fails?
```

If yes, fix the seam.

## 24. Billing, Invoicing, and Batch Pipelines Need Deduplication Checks

For batch operations, ask:

```text
Can two bundlers, grouping stages, or pipeline branches emit the same charge?
Can sibling jobs produce duplicate rental or service charges?
Can a later stage silently drop lines?
Can partial selection violate a ticket-level or invoice-level invariant?
```

If duplicate emission is possible, deduplicate at the seam using an explicit key and add a regression test.

Domain operations that should be atomic, such as invoicing a whole bridge ticket, must not allow partial selection unless the partial behaviour is explicitly designed and tested.

## 25. Date and Time Semantics Must Be Explicit

Dates and datetimes must be handled deliberately.

Use branch-local dates for business dates where branch locality matters. Use UTC for stored datetimes unless the project has a more specific convention.

Billing logic must be explicit about which date drives:

```text
Rate selection.
Invoice period eligibility.
Surcharge selection.
Display on PDFs.
Reconciliation.
Generation.
Preview.
```

Do not casually mix `invoice_date`, `charge_date`, `ticket_date`, `completed_at`, `period_start`, and `period_end`.

The review question is:

```text
Would preview, generation, PDF display, and reconciliation all agree on this date?
```

If not, make the date semantics explicit.

## 26. Multi-Write Operations Must Be Atomic

Any service operation that performs multiple writes must use `transaction.atomic` or an explicit atomic transaction boundary.

This includes:

```text
Creating records plus child records.
Updating status plus creating ledger entries.
Sending/queueing emails plus updating invoice state.
Deleting or archiving related records.
Posting payments.
Generating invoices.
Voiding invoices or tickets.
Batch operations.
```

Avoid two-write operations where the first write can succeed and the second can fail, leaving partial state.

The review question is:

```text
What happens if this crashes halfway through?
```

If the answer is “partial state remains,” add a transaction or redesign the workflow.

## 27. Async and Operational Flows Need Recoverable States

Async/task flows must not leave records stranded in dead-end statuses.

Do not mark a batch as successful if some sub-step failed. Do not swallow errors and report success. Do not create terminal states that require manual database surgery to recover.

For task workflows, define:

```text
Queued state.
In-progress state.
Succeeded state.
Failed state.
Retryable failure behaviour.
Operator-visible error state.
```

The review question is:

```text
If this external service fails, can the operator see and recover from the failure?
```

## 28. Never Silently Swallow Errors

Do not catch broad exceptions and continue as though the operation succeeded.

Avoid:

```python
try:
    send_email(...)
except Exception:
    pass

return SuccessResponse(...)
```

Prefer surfacing the failure, marking the operation as failed, or returning a partial failure result that the UI can display.

The review question is:

```text
Could the system tell the user this worked when it did not?
```

If yes, fix it.

## 29. Frontend Forms Must Follow Repository Form Standards

Modal and CRUD forms should use the repository’s established form stack and error-handling conventions.

Expected pattern:

```text
react-hook-form.
Zod schema.
zodResolver.
parseApiError for mutation failures.
field errors mapped with form.setError.
unmapped errors shown in an alert/banner.
consistent destructive error label, border, and message styling.
```

Validation errors must actually display useful messages to the user.

Do not rely on network-tab errors, console logs, or silent disabled states as the only feedback.

## 30. Frontend Components Should Use Shared UI Conventions

Frontend components should use the established design system and import conventions.

Expected pattern:

```text
Use shadcn/ui components where the repo already uses them.
Use absolute `@/` imports where that is the established convention.
Use semantic CSS variables rather than raw Tailwind palette colours.
Use constant maps instead of long ternary chains for status/display mapping.
Use consistent badge, icon, modal, and error styles.
```

Avoid raw palette classes such as:

```tsx
bg - amber - 100;
text - red - 700;
border - gray - 300;
```

unless nearby code clearly establishes that as acceptable.

For button icons, apply icon sizing according to the repo’s button convention, for example via button-level selectors rather than one-off icon hacks where applicable.

## 31. Disable Impossible Frontend Actions Early

The frontend should prevent users from attempting actions that are obviously impossible from current state, such as adding a service line before selecting a site.

However, frontend disabling is not a substitute for backend validation.

The correct model is:

```text
Frontend prevents obvious invalid interactions.
Backend enforces the true rule.
Service layer remains authoritative.
```

## 32. Use Existing Repository Factories and Test Helpers

Tests should use existing factories, fixtures, and permission helpers.

Do not hand-roll users, branches, permissions, model graphs, or setup data if the repository already has helpers.

Prefer:

```python
user = user_with_permission(...)
```

over custom ad hoc user creation, if that is the established repo pattern.

The review question is:

```text
Am I using the same test helpers as nearby tests?
```

## 33. API Changes Need Happy and Sad Path Tests

API changes should normally include:

```text
Happy path test.
Permission denied test.
Branch access denied test, where branch ownership matters.
Validation failure test.
Relevant state-transition failure test.
```

For billing, invoicing, payments, bridge tickets, job completion, and batch operations, add regression tests for edge cases that would cause financial or operational errors.

When a bug or review comment identifies a mechanism failure, add the test that would have caught it.

## 34. Frontend Changes Need Meaningful Coverage Where Practical

For frontend work, test or manually verify the actual behaviours reviewers care about:

```text
Validation errors are visible.
Permission loading does not redirect authorized users.
Denied users cannot act.
Mutation errors display correctly.
Disabled states match backend affordances.
Status/enum labels come from the API contract where applicable.
```

Do not ship frontend behaviour that only works in the happy path.

## 35. Migrations Must Be Clean

On active development branches, prefer clean migration history over stacked fix-up migrations when safe.

Expected migration hygiene:

```text
No duplicate leaf migrations.
No stale migrations from abandoned approaches.
No unnecessary RunPython backfills on develop when delete-and-recreate is safe.
No destructive one-step migration on live data paths.
Merge leaf-node migrations before shipping.
Follow expand → migrate → contract for live paths.
```

If the schema approach changes mid-branch, remove stale migrations rather than preserving every intermediate attempt.

## 36. Do Not Ship Cruft

Do not expand the diff with noise.

Remove:

```text
Unused files.
Unused imports.
Commented-out code.
Temporary debug code.
Console logs.
Implementation notes.
Spec markdown.
Dead helpers.
Stale migrations.
One-off scripts.
```

Do not include design documents, steering docs, or implementation plans in feature MRs unless explicitly requested.

The review question is:

```text
Would a reviewer have to ask me to delete this?
```

If yes, delete it first.

## 37. Code Must Be Easy to Review

Generated code should minimise unnecessary diff noise.

Avoid unrelated formatting changes, unnecessary reordering, broad rewrites, or opportunistic refactors unless the task explicitly calls for them.

Prefer the smallest coherent change that solves the actual problem while preserving code quality.

Before finishing, check:

```text
Did I change files unrelated to the task?
Did I rewrite code that did not need to be rewritten?
Did I introduce a new abstraction where a local change would have been clearer?
Would this diff be annoying to review?
```

## 38. Respect Existing Architecture Before Inventing New Patterns

Before introducing a new pattern, abstraction, folder, naming convention, hook, service style, serializer shape, or layer boundary, inspect nearby code and follow the existing repository style unless there is a strong reason not to.

Do not introduce a new architecture to solve a small local problem.

Do not create one-off abstractions that are inconsistent with the rest of the module.

Do not move logic across layers merely because another architecture style would do so in a greenfield project.

The review question is:

```text
Does this change look native to this repository?
```

## 39. Required Agent Self-Review

Before presenting code as complete, the agent must explicitly self-review against this standard.

The agent should not stop after making the implementation compile or pass obvious tests.

If the agent intentionally violates one of these standards, it must explicitly explain why the exception is justified.

Acceptable explanation:

```text
I used a local import here because importing this optional dependency at module load time triggers an external service initialisation. There is no circular dependency involved.
```

Unacceptable explanation:

```text
I used a local import to avoid an import error.
```

That usually means the structure is wrong and should be reconsidered.

## Pre-Submit Checklist

Before opening an MR or handing work back, verify:

```text
Imports
- Are all imports at the top of the file?
- Are there any local imports?
- If there are local imports, are they genuinely justified?
- Is any circular dependency being hidden rather than fixed?

Layering
- Are API views thin?
- Does each API view represent one clear operation?
- Is business logic in services?
- Are serializers limited to API contract validation and representation?
- Are services responsible for writes, authorization, and workflows?

Validation and invariants
- Is API shape validation in serializers?
- Is business validation in services?
- Are impossible states prevented by model/database constraints where possible?
- Is clean() thin?
- Are defensive downstream sanity checks removed?

Choices and contracts
- Are model TextChoices used instead of hard-coded strings?
- Do serializers use model-defined choices?
- Do services use TextChoices constants or .values where applicable?
- Are configurable choices represented with the correct model relationships?
- Are structured API responses represented with explicit nested serializers?
- Has OpenAPI/schema drift been checked after API changes?

Permissions
- Are branch-access checks performed in services?
- Are permissions checked before writes and expensive queries where possible?
- Does the backend derive permission-aware UI affordances?
- Does the frontend distinguish loading from denied?

Naming and module ownership
- Are function names specific and domain-oriented?
- Are vague names like resolve, process, handle, source, config, or data avoided?
- Does the code live in the owning module?
- If naming is hard, has the function been split or clarified?

Duplication and abstraction
- Is there one owner for each domain concept?
- Has the agent searched for existing canonical resolvers/helpers?
- Are thin wrappers removed?
- Are single-use helpers justified?
- Has the agent avoided both over-abstraction and giant functions?

Pipelines
- Do preview and generation use the same inputs, dates, validation, and eligibility rules?
- Can preview pass while generation fails?
- Are batch operations protected against duplicate charge emission?
- Are atomic domain operations kept atomic?

Transactions and failures
- Are multi-write operations wrapped in transaction.atomic?
- Do async flows have recoverable states?
- Are errors surfaced instead of swallowed?
- Could the system report success when a sub-step failed?

Frontend
- Do forms use Zod, zodResolver, parseApiError, form.setError, and visible error messages?
- Are shadcn/ui and repo UI conventions followed?
- Are semantic colours used instead of raw palette classes?
- Are backend-owned enums not hard-coded in the frontend?
- Are impossible actions disabled early while still enforced by the backend?

Tests
- Are API happy paths covered?
- Are permission, branch-access, and validation sad paths covered?
- Are existing factories and permission helpers used?
- Has a regression test been added for any bug-prone mechanism?

Migrations and diff hygiene
- Are migrations clean?
- Are duplicate leaf migrations resolved?
- Are stale migrations removed?
- Is there any unused code, commented-out code, debug code, docs, or dead files?
- Is the diff focused and reviewable?

Dates and timezones
- Are branch-local dates and UTC datetimes handled deliberately?
- Is the date driving billing, display, rate selection, preview, and generation explicit?
```

## Definition of Done

A change is not complete until:

```text
The implementation solves the requested problem.
The code follows existing repository patterns.
The diff is focused and reviewable.
Imports are clean.
API views are thin.
Business logic is in services.
Serializers describe contracts rather than workflows.
Choices and constants are not duplicated.
Invalid states are prevented at the strongest sensible layer.
Branch access and permissions are enforced in services.
Frontend affordances are permission-aware.
Preview and generation paths agree.
Multi-write operations are atomic.
Errors are not silently swallowed.
Helper functions are justified.
Names are readable and domain-specific.
Tests cover happy and sad paths.
Migrations are clean.
Cruft has been removed.
The agent has reviewed the change against this document.
```

Code that works but fails these standards should be treated as unfinished.

## Suggested Agent Prompt Block

Use this block in task instructions, `AGENTS.md`, or a repo skill:

```text
Before submitting code, self-review against CODE_REVIEW_STANDARD.md.

In particular:

1. API views must be thin. Business logic, writes, permissions, branch access, and workflows belong in services.
2. Serializers validate API shape and represent API contracts. They should not become business-logic containers.
3. Avoid defensive programming. Validate once at the agreed boundary, enforce invariants at the model/database layer where possible, and fail loudly when contracts are violated.
4. Use model TextChoices, enum classes, .values, constants, and configurable-choice models correctly. Do not hard-code backend-owned values.
5. Do not hard-code backend-owned enums or option lists in the frontend.
6. Use explicit nested serializers for structured API data. Do not return loose dict shapes unless the structure is genuinely arbitrary.
7. Check branch access and permissions in services before writes and before expensive queries where possible.
8. Backend should derive permission-aware UI affordances such as can_void, can_edit, can_take_payment, and can_invoice.
9. Names must be resource/action-oriented and domain-specific. Avoid vague helpers such as resolve, process, handle, source, config, and data.
10. Put code in the module that owns the domain concept.
11. Avoid duplicated domain mappings. Search for the existing canonical resolver before writing another one.
12. Delete thin wrappers, unused files, commented-out code, stale migrations, debug code, and implementation notes.
13. Preview and generation paths must use the same dates, validation, eligibility rules, and invariants.
14. Batch billing/invoicing paths must be protected against duplicate emission and silent line dropping.
15. Multi-write operations require transaction.atomic or an explicit transaction boundary.
16. Async flows need recoverable failed states and must not report success when sub-steps fail.
17. Frontend forms should use the repo form stack: Zod, zodResolver, parseApiError, field errors via form.setError, and visible error messages.
18. Frontend UI should follow repo conventions: shadcn/ui, @/ imports, semantic colours, constant maps instead of ternary chains.
19. API changes need happy-path and sad-path tests, including permission denied, branch access denied, and validation failure where applicable.
20. Migrations must be clean: no duplicate leaves, stale migrations, unnecessary fix-up migrations, or unsafe destructive live-data changes.

If you cannot point to where each relevant rule is satisfied, fix the code before requesting review.
```
