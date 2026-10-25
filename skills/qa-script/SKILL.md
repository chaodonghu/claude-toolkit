---
name: qa-script
description: Generates a step-by-step manual QA run-book and a demo-recording script for the current change, derived from the Jira ticket and the diff. Use when the user says "how do I test this", "manual QA steps", "repeat the testing instructions", "what do I record for the demo/loom", "give me the QA steps", or "how do I reproduce this again".
metadata:
  tags:
    - testing
    - qa
    - workflow
  status: recommended
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(ls:*), Bash(cat:*), Bash(find:*), Bash(glab mr view:*)
---

# QA Script

Produce a manual QA walkthrough plus a demo-recording script for the change on the current branch. This skill exists because the user asks for this on almost every MR ("repeat the testing steps", "what do I record for the loom", "how do I reproduce this again") and the repo's MR template requires a recording before merge.

This is the human run-book the user follows while clicking through and recording. It is NOT an automated browser test (that is `/qa` and `/verify`).

## When to Use

- "how do I test this" / "manual QA steps" / "give me the QA steps"
- "repeat the testing instructions" / "how do I test the MR again"
- "what do I record for the demo" / "demo steps for the loom"
- "how do I reproduce this again" / "what are the repro steps"

## Workflow

### 1. Read the change

```bash
git branch --show-current
git diff main...HEAD
git log main..HEAD --oneline
```

Pull the Jira ticket from the branch (e.g. `PROJ-####`) via the `jira-cli` skill (`acli jira workitem view <KEY>`) to understand the intended user-facing behavior and any reported bug.

### 2. Identify user-facing scenarios

From the diff + ticket, enumerate every scenario a reviewer would care about:

- The happy path, end to end
- Error / edge cases (invalid input, empty state, permission denied)
- For a bugfix: the bug reproducing on `main`, then the fix working on this branch
- For a feature flag: behavior with the flag ON and OFF
- For UI: desktop and mobile (or note why mobile is N/A)
- For API: request/response examples (curl or Swagger UI)

These map directly to the "What to show in your recording" checklist in `.gitlab/merge_request_templates/Default.md`, so the output doubles as the Loom script.

### 3. Write the run-book

Output two clearly separated parts:

**Part A — Setup**
- Which worktree / branch, and how to confirm localhost is actually on it (`git rev-parse --show-toplevel`, branch check).
- Any seed/login/flag prerequisites.
- If dev is stuck or misbehaving (port conflicts, OAuth callback errors), sort that out before QA.

**Part B — Numbered QA + demo steps**
- One numbered step per action, with the exact UI path and the expected result.
- Mark which steps to capture on camera and which screenshots to grab.
- For bugfixes, lead with the before-on-`main` repro, then the after-on-branch fix.

### 4. Offer to persist it

Ask whether to drop the run-book into the MR's **Test Plan** section (via the `mr-draft` skill) so they do not have to re-ask next time.

## Output Format

```
## Setup
1. ...

## Manual QA + demo script
1. [RECORD] Go to … → expect …
2. [SCREENSHOT] …
3. ...
```

Keep it concrete and skimmable. They are reading this live while recording, so no preamble.
