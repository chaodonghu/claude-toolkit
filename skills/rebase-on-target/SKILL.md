---
name: rebase-on-target
description: Catch a single MR branch up to its target branch when it has fallen behind. Fetches the target (usually main), rebases this branch onto it in the correct worktree, runs a quick sanity check, and force-pushes with lease. Use when reviewing an MR and you notice it is N commits behind the target branch, or when the user says "rebase from main", "it's behind, catch it up", "rebase the branch", or "this MR is X commits behind". This is the single-branch local rebase, not the bulk server-side sweep (that's rebase-stale-mrs).
metadata:
  tags:
    - git
    - gitlab
    - code-review
    - workflow
---

# Rebase on target

Catch the current MR branch up to its target branch when it has drifted behind. This exists because it comes up almost every review cycle: the user is working an MR's comments, GitLab shows "this branch is N commits behind main", and the fix is always the same small dance (fetch, rebase, sanity-check, force-push with lease) done in the right worktree.

This is the **single-branch, local rebase** triggered during review. For a periodic sweep that rebases every open MR via GitLab's server-side API, use `rebase-stale-mrs` instead.

## When to Use

- While reviewing/addressing MR comments you notice the branch is behind its target ("20 commits behind main").
- "rebase from main" / "rebase the branch" / "catch it up" / "it's behind the target branch".
- `resolve-reviews` hands off here after it spots the branch is behind (see that skill's pre-flight).

## Non-Negotiable Rules

1. **Work in the worktree that has the branch checked out.** A branch can only be checked out in one worktree. Confirm `git rev-parse --show-toplevel` and `git branch --show-current` match the branch before touching anything. Never rebase from the primary tree if the branch lives in a worktree (or vice versa).
2. **Clean tree first.** If `git status --porcelain` is non-empty, STOP and surface it. Do not rebase over uncommitted work, do not `git reset --hard`, do not auto-stash without saying so.
3. **Rebase, don't merge.** Keep history linear. `git rebase origin/<target>`, not a merge commit, unless the user asks otherwise.
4. **Conflicts stop the line.** On a conflict, do not guess a resolution. Surface the conflicting files and the conflict hunks, and ask. `git rebase --abort` leaves the branch exactly as it was, so aborting is always safe if unsure.
5. **Force-push with lease, and keep it user-confirmed.** Always `git push --force-with-lease` (never bare `--force`), so a teammate's push isn't clobbered. Pushing stays a confirmed action per the user's conventions.

## Workflow

### 1. Establish context

```bash
git rev-parse --show-toplevel        # which worktree am I in?
git branch --show-current            # is this the MR's branch?
```

Find the MR and its real target branch (don't assume `main`):

```bash
glab mr list --source-branch="$(git branch --show-current)" --state=opened
glab api "projects/:id/merge_requests/<iid>" | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_branch"])'
```

### 2. Measure the drift

```bash
git fetch origin <target>
git rev-list --left-right --count origin/<target>...HEAD   # "<behind>\t<ahead>"
```

If `behind` is 0, there's nothing to do. Say so and stop.

### 3. Confirm the tree is clean

```bash
git status --porcelain
```

Non-empty → STOP (rule 2). Otherwise continue.

### 4. Rebase

```bash
git rebase origin/<target>
```

- Success → continue.
- Conflict → surface the files (`git status`, the conflict hunks), ask how to resolve, or `git rebase --abort` and report. Do not invent resolutions.

### 5. Sanity check

Run a fast, relevant check so the rebase didn't silently break the branch. Scale it to the change:

- Touched components/hooks → the affected test suites.
- Touched types broadly → the typecheck (or the affected package).
- Trivial / docs-only branch → eyeball `git diff origin/<target>...HEAD --stat`.

Confirm the post-rebase divergence is `0 <ahead>`:

```bash
git rev-list --left-right --count origin/<target>...HEAD
```

### 6. Force-push (confirmed)

```bash
git push --force-with-lease
```

Report the old→new head and the new divergence.

## Output

Report: which worktree/branch, the target branch, how far behind it was, whether the rebase was clean or hit conflicts, what sanity check was run and its result, and the new head SHA after force-push. If anything stopped the line (dirty tree, conflict), say exactly what and what you need from the user.
