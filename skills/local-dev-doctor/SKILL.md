---
name: local-dev-doctor
description: Diagnoses common local-dev failures of a multi-service web stack in order. Covers a request or job that hangs forever, EADDRINUSE port conflicts, NextAuth OAuthCallback / no-Set-Cookie login loops, an account or data that will not sync after pulling env, and worktree or branch mismatches. Use when the user says local dev is "stuck" or "broken", something spins forever, a port is in use, login keeps failing, the account won't sync, or they are unsure their localhost is on the right branch.
metadata:
  tags:
    - local-dev
    - debugging
allowed-tools: Bash(lsof:*), Bash(git rev-parse:*), Bash(git branch:*), Bash(git status:*), Bash(rg:*), Bash(tail:*), Bash(grep:*), Bash(cat:*), Bash(ls:*), Bash(curl:*), Bash(ps:*)
---

# Local Dev Doctor

Ordered diagnostic for the local-dev failures that keep recurring on a stack with a web app, an API and a background worker. Run the checks top to bottom and stop when one explains the symptom. This is diagnosis and repair of an already-set-up stack, not a cold start.

## Know the stack first

Find these in the repo's README or dev docs before running anything. The commands below use them as placeholders.

| What | Placeholder |
|---|---|
| Log directory and files | `<logs>/web.log`, `<logs>/api.log`, `<logs>/worker.log` |
| Ports | `<web-port>`, `<api-port>`, plus any admin port |
| Env files | one per app, for example `apps/web/.env`, `apps/api/.env` |
| How worktrees get ports | fixed, or offset per worktree by a dev manager |

## When to Use

- A request, chat run or job that spins and never resolves
- `EADDRINUSE` / "address already in use"
- Login loops: `OAuthCallback`, "NextAuth handler produced no Set-Cookie headers"
- "my account isn't syncing" or "user not found" right after pulling env
- "am I even on the right branch / worktree?"

## Diagnostic Order

### 1. Something hangs forever

The request never completes. It is usually the worker or the database, not the web app.

```bash
tail -n 80 <logs>/worker.log
rg -n "error|exception|failed|ECONNREFUSED|timeout" <logs>/worker.log | tail -30
tail -n 40 <logs>/api.log
```

- Is the queue or task worker actually running and consuming? A job sits in progress forever if nothing picks it up.
- Is the database reachable? If the `docker compose` database is down, the job cannot progress.
- Align timestamps across `api.log` and `worker.log` to see where it dies.

### 2. EADDRINUSE / port already in use

```bash
lsof -i :<web-port> -i :<api-port>   # adjust for worktree offset ports
```

A stale dev process, or a sibling worktree's stack, owns the port. Identify the PID and confirm with the user before killing it. When several worktrees run at once, the conflict is often a leftover process from a previous session, not the current worktree.

### 3. NextAuth login loop (OAuthCallback / no Set-Cookie)

Symptoms: `GET /api/auth/signin?error=OAuthCallback`, or a warning that the NextAuth handler produced no Set-Cookie headers.

```bash
rg -n "NEXTAUTH_URL|CLIENT_SECRET|CLIENT_ID" apps/web/.env
```

- `NEXTAUTH_URL` must match the port this stack actually serves. On a worktree with an offset port, a mismatch sends the OAuth callback to the wrong stack and no cookie is set.
- Confirm the OAuth client id and secret are present in the web app's env file.

### 4. Account or data not syncing after an env pull

Pulling env from a shared secret store can bring along production-shaped values. The usual footgun is a flag that is off in the shared config and has to be on locally, such as a background sync or sweeper toggle, which breaks first-login sync.

```bash
rg -n "ENABLED|_URL|_ENV" apps/api/.env   # look for flags and hosts that point at the wrong environment
```

- Compare the env against what the repo's local-dev docs say it should be. Fix the value in every app that reads it, then restart dev.
- Expect to redo this after every env pull.
- Symptom match: "user not found" on a bootstrap or session endpoint, or local clearly reading another environment's data.

### 5. Worktree / branch mismatch

"Is my localhost actually on this branch?"

```bash
git rev-parse --show-toplevel    # which worktree am I in
git branch --show-current        # which branch
```

- If the running dev server was started from a different worktree, your code edits are not what localhost serves.
- Confirm the dev process serving your port was launched from this worktree root. If not, restart dev from the correct worktree.

## Output

State which check matched, the evidence (the log line, the env value, the PID) and the exact fix. Do not kill processes or edit env files without confirming, since other worktrees may depend on them.
