---
name: cmux-fanout
description: >-
  Fan out multiple tickets across parallel cmux workspaces, one spawned Claude
  agent per ticket, with this session acting as the orchestrator. Each ticket
  gets its own git worktree and branch and an agent that plans, implements,
  runs the project check and opens a draft MR or PR. The orchestrator assigns
  the tickets, spawns the agents without stealing focus, watches each branch
  and reviews each diff. USE WHEN the user says "tackle these tickets at once",
  "fan out", "orchestrate these tickets", "spawn agents for PROJ-1 and PROJ-2",
  "work on these in parallel", or hands over a set of tickets to implement
  together.
---

# cmux-fanout: parallel ticket orchestrator

Run N tickets at once. The orchestrator (this session) sets up an isolated git
worktree per ticket and spawns one Claude agent per worktree in its own cmux
workspace. Each agent plans, implements, runs the project check and opens a
**draft** MR or PR. The orchestrator stays free to watch progress and review.

If you do not need to watch the agents live, the `ticket-fanout` workflow in
this repo does the same job without cmux.

## When to use / not

- **Use** for 2-4 independent, small-to-medium tickets that can land as separate
  MRs in parallel.
- **Don't** use for a single ticket (just implement it here), for tickets that
  touch the same files (they will conflict at merge), or for more than ~4 at
  once (token cost scales linearly and you lose oversight).

## Why the spawn pattern, not `cmux claude-teams`

Each ticket needs its **own branch**, and git only checks out one branch per
working tree. `cmux claude-teams` teammates share the lead's single working
directory, so they cannot each be on a different branch. This skill spawns
**independent** workspaces, one per worktree and branch.

## Resolve the repo conventions first

Read the repo's README, contributing guide and agent instructions, then settle
these before creating anything. Ask the user for whatever the repo does not
answer.

| Convention | Example |
|---|---|
| Ticket keys | `PROJ-101`, `PROJ-102` |
| Base branch | `main` |
| Branch name | `PROJ-101-short-slug` |
| Worktree path | a sibling of the repo, `../<repo>-proj-101` |
| Install command | `pnpm install` |
| Check command | `pnpm check` (types, lint, tests) |
| Bootstrap files | gitignored files a fresh worktree needs, such as `.env.development.local` or local keys |
| Implement flow | the repo's own implement skill or command if it has one, otherwise the explicit flow in Step 3 |
| MR or PR rules | title and commit format, description template, draft by default |

## Prerequisites

- You are running **inside a cmux session** (`$CMUX_WORKSPACE_ID` set). Rename
  this workspace to something like "ORCHESTRATOR" so it is easy to find.
- The ticket CLI is authenticated (`acli jira auth status`, `gh auth status`
  or `glab auth status`). Ticket lookups go through a CLI, not an MCP tool
  that asks for a manual approval on every call. A prompt per call breaks the
  unattended flow.
- You have the ticket keys. Confirm with the user how far each agent should go
  (default: implement end to end and open a **draft** MR).

## Step 1: Assign the tickets to the user

```bash
acli jira workitem assign --key "PROJ-101,PROJ-102" --assignee "@me" -y
```

`@me` is the authenticated `acli` user. Comma-separate keys for a batch.

## Step 2: Per ticket, fetch context, create the worktree, bootstrap, install

Pull each ticket's description. You embed it in the kickoff prompt so the
spawned agent never has to touch the tracker, which avoids approval prompts in
its session.

```bash
acli jira workitem search --jql 'key in (PROJ-101, PROJ-102)' \
  --fields "key,summary,description,status" --json > /tmp/fanout-desc.json
# description is ADF JSON, so flatten the text nodes before embedding it
```

Create a worktree off the **latest** base branch for each ticket, copy in the
bootstrap files, and start the install.

```bash
MAIN="$(git rev-parse --show-toplevel)"
cd "$MAIN" && git fetch origin main --quiet
git worktree add ../myrepo-proj-101 -b PROJ-101-short-slug origin/main

# bootstrap gitignored files (copies, not symlinks)
for f in .env.development.local; do
  [ -f "$MAIN/$f" ] && cp "$MAIN/$f" ../myrepo-proj-101/
done

( cd ../myrepo-proj-101 && pnpm install )   # run in the background, a few minutes each
```

Wait for every install to finish before spawning (confirm the test runner
binary exists in each worktree) so the agents do not run tests against a
half-linked tree.

## Step 3: Kickoff prompt and launcher per ticket

Write a kickoff prompt to `/tmp/<ticket>-kickoff.txt`. It MUST:

- State that the agent is **already** in its worktree on its branch. It must
  not create another worktree or switch branches. An implement skill will
  otherwise try to make its own.
- Embed the ticket's full context from Step 2 (summary, description, named
  files, acceptance criteria) so the agent needs no tracker access.
- Define the flow. Either name the repo's implement skill, or spell it out:
  plan, implement incrementally, run the check command until it is green,
  commit using the repo's subject format, push, open a **draft** MR against
  the base branch using the repo's template.
- Name any repo gates the agent has to satisfy (pre-commit hooks, required
  template sections, a recording that is still pending). No `--no-verify`.
- If the ticket is ambiguous or may need a design decision, tell the agent to
  research first and **bail back to the orchestrator** with findings rather
  than force it.

Then a launcher. A shell wrapper guarantees the `$(cat ...)` prompt expands.

```bash
cat > /tmp/launch-proj-101.sh <<'EOF'
#!/bin/bash
cd /absolute/path/to/myrepo-proj-101 || exit 1
exec claude "$(cat /tmp/proj-101-kickoff.txt)"
EOF
chmod +x /tmp/launch-proj-101.sh
```

## Step 4: Spawn one workspace per ticket, without stealing focus

```bash
CURRENT=$(cmux current-workspace 2>&1 | awk '{print $NF}')   # the workspace ref; adjust the field if your cmux prints it elsewhere
cmux workspace create --name "PROJ-101" --cwd /absolute/path/to/myrepo-proj-101 --command "/tmp/launch-proj-101.sh"
cmux workspace create --name "PROJ-102" --cwd /absolute/path/to/myrepo-proj-102 --command "/tmp/launch-proj-102.sh"
cmux workspace select "$CURRENT"   # re-select to keep focus on the orchestrator
```

`--name` labels the tab, `--cwd` sets the worktree, `--command` runs the
launcher. Re-selecting `$CURRENT` is what prevents the focus steal. After
spawning, run `cmux read-screen --workspace workspace:N | tail -20` on each to
confirm it booted `claude` and started on the ticket.

## Step 5: Orchestrate

- **Watch each branch** for its first push with a background loop, then surface
  the MR:
  ```bash
  until [ -n "$(git ls-remote origin PROJ-101-short-slug)" ]; do sleep 20; done
  ```
- **Check progress** any time without switching tabs:
  `cmux read-screen --workspace workspace:N`.
- **Review** when each lands. Run your review against
  `origin/main...PROJ-101-short-slug`. Git refs are shared across worktrees,
  so you can review from the orchestrator. Dispatch fixes back to the owning
  agent with
  `cmux send --workspace workspace:N "..." && cmux send-key --workspace workspace:N Enter`.

## Step 6: Teardown

When a ticket's MR is merged, or you are done:

```bash
cmux workspace close workspace:N
git worktree remove ../myrepo-proj-101   # or: git worktree prune
```

## Gotchas (learned running this)

- **Spawned agents are separate Claude sessions.** Their approval prompts (push,
  MR create, anything permission-gated) pop **in their own cmux tabs**, not
  here. Keep an eye on those tabs or they stall waiting for input.
- **Agents can exceed a dispatched instruction.** One was told not to cc anyone
  and added the pings anyway because it mirrored a reference repo. Always diff
  what the agent actually committed against what you dispatched before treating
  a decision as applied. Do not trust the agent's self-report alone.
- **Worktree bootstrap is mandatory.** The most common way an agent stalls is a
  worktree missing an env file or a local key. See Step 2.
- **cmux socket** is at `$CMUX_SOCKET_PATH`, not `/tmp/cmux.sock`. Legacy verbs
  (`new-workspace` and friends) still work but print a deprecation hint.
  `cmux workspace <verb>` is canonical.
- **Rebase before merge if behind.** Long-lived branches drift. Run
  `git rebase origin/main` per worktree.
- **Partition by files.** Do not fan out tickets that edit the same files. The
  parallel MRs will conflict at merge.
