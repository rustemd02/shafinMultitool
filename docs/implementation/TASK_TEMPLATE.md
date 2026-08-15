# Luna / Max task packet template

Каждая user-visible Luna-задача получает полный пакет. Заполнители перед отправкой запрещены.

```text
ROLE
Act as the implementation worker in Sol Advisor's user-visible Luna task lane.
Prepare only the requested changes and evidence. Do not redesign architecture,
broaden ownership, create a PR, push, merge, rebase, or modify another stack.
You are not alone in the repository: preserve unrelated edits and never revert them.

OBJECTIVE
<Observable outcome, user/release value, and acceptance condition.>

FILES AND OWNERSHIP
You own only:
- <exact paths>
You do not own:
- <exact exclusions>
Return a blocker before touching a path outside ownership.

INTERFACES
- <contracts, schemas, commands and behavior that remain compatible>

CONSTRAINTS
- Product authority: docs/app-store-product-plan.md.
- Execution state: docs/implementation/STATUS.md.
- Use GPT-5.6 Luna at Max reasoning.
- Do not substitute another model, native agent or effort.
- Do not turn an audit assumption into a product or architecture decision.

STARTING STATE / BASE
- Project ID: ac45e24e-80ce-4fad-803a-731a0a84ee27
- Git repository: true
- Environment: isolated worktree
- Base: <exact branch and SHA>
- Prior accepted stack: <exact branch/SHA or none>

VERIFICATION
- Run: <exact command>
  Success: <exit code/output>
- Inspect: <exact artifact/diff>
  Success: <required evidence>

GIT / PR BOUNDARY
- Report git status --short --branch, base, changed files, complete diff and commit state.
- Commit only if this packet explicitly requests it; report exact SHA.
- PR/push/merge/rebase are not authorized.

STRUCTURED RETURN
STATUS: complete | partial | blocked
TASK ID: <id, threadId, hostId>
OBJECTIVE: <one line>
STARTING STATE: <project, worktree, branch, base>
CHANGES: <file-by-file diff summary>
VERIFIED: <commands and concrete results>
GIT: <status, changed files, commit SHA or none, branch, base>
PR: not authorized
JUDGMENT CALLS: <none or explicit list>
GAPS: <none or explicit blockers>
```
