# claude-toolkit

Personal collection of Claude Code skills and workflows.

- **Skills** live in `skills/<name>/SKILL.md` and symlink into `~/.claude/skills/<name>/`.
- **Workflows** live in `workflows/<name>.js` and symlink into `~/.claude/workflows/<name>.js`.

Both get picked up by Claude Code in every project once installed.

## Install

```bash
./bin/install.sh
```

Symlinks every skill and workflow into `~/.claude/`. Re-run after adding or pulling new ones. Existing real directories are left alone, so remove a local copy first if you want the repo version linked in its place.

## Skills

### Git and branches

| Skill | What it does | Trigger |
| --- | --- | --- |
| [git-commit](skills/git-commit/SKILL.md) | Writes a storytelling Conventional Commits message, pulling in Jira ticket context when the branch has a key, then commits and pushes. | "commit", "git commit" |
| [merge](skills/merge/SKILL.md) | Commits, rebases and merges the current branch. | `/merge` |
| [rebase](skills/rebase/SKILL.md) | Rebases the current branch with smart conflict resolution. | `/rebase` |
| [rebase-on-target](skills/rebase-on-target/SKILL.md) | Catches one MR branch up to its target when it has fallen behind: fetch, rebase in the right worktree, sanity check, force-push with lease. Conflicts stop the line. | "rebase from main", "it's behind, catch it up" |
| [worktree](skills/worktree/SKILL.md) | Launches one or more tasks in new git worktrees via `workmux`. | `/worktree` |

### Code review and QA

| Skill | What it does | Trigger |
| --- | --- | --- |
| [augmented-review](skills/augmented-review/SKILL.md) | Human-first review guided by research-backed strategies, then two LLM arms: one investigates your hotspots, one does a mechanical sweep. LLM results are held until you have formed your own view. | `/augmented-review [range, !MR or paths]` |
| [generate-review-skill](skills/generate-review-skill/SKILL.md) | Mines review comments from your GitLab MRs and turns the recurring themes into personalized review checklist skills. | "generate a review skill" |
| [resolve-reviews](skills/resolve-reviews/SKILL.md) | Pulls the open threads on the current MR, fixes each finding, reacts with a fitting emoji and replies inside the thread in your conversational voice. | "fix the review comments", "address the MR comments" |
| [qa-script](skills/qa-script/SKILL.md) | Writes a numbered manual QA run-book and demo-recording script from the ticket and the diff. | "how do I test this", "what do I record for the demo" |

### GitLab and Jira

| Skill | What it does | Trigger |
| --- | --- | --- |
| [gitlab](skills/gitlab/SKILL.md) | Reference for `glab`: MRs, issues, pipelines, projects and more. | any GitLab task |
| [jira-cli](skills/jira-cli/SKILL.md) | Reference for `acli jira`: view, create with ADF descriptions, edit, search with JQL and filters, transition. | any Jira task |
| [mr-draft](skills/mr-draft/SKILL.md) | Writes or updates an MR description from the repo's own template, plain language, no AI slop, and keeps the screenshots and recording links already there. | "draft MR", "fill in the MR description" |
| [open-pr](skills/open-pr/SKILL.md) | Writes a PR description from conversation context and opens PR creation in the browser. | `/open-pr` |
| [rebase-mrs](skills/rebase-mrs/SKILL.md) | Scans your open MRs across projects, server-side rebases the unapproved-but-behind ones, and flags approved-but-stale MRs and conflicts. Schedule with `/loop 1h /rebase-mrs --working-hours-only` or launchd (`skills/rebase-mrs/launchd/install.sh`). | `/rebase-mrs` (`--dry-run` to preview) |
| [rebase-mrs-review](skills/rebase-mrs-review/SKILL.md) | Reads the rebase-mrs state file and gives a triage briefing: what was rebased, what is stale, what conflicted, proposed next actions. Read-only. | `/rebase-mrs-review` |
| [rebase-stale-mrs](skills/rebase-stale-mrs/SKILL.md) | Rebases every open, non-draft, unapproved MR through GitLab's server-side rebase API. | `/rebase-stale-mrs` |

### Writing and learning

| Skill | What it does | Trigger |
| --- | --- | --- |
| [rephrase](skills/rephrase/SKILL.md) | Rephrases pasted text to be clearer and more empathetic while keeping your voice. | `/rephrase <text>` |
| [teach](skills/teach/SKILL.md) | Teacher mode. Checks you deeply understand the current session, with incremental verification before moving on. | `/teach`, "walk me through this" |
| [handoff](skills/handoff/SKILL.md) | Writes or updates a handoff document so the next agent with fresh context can continue the work. | "write a handoff" |

### Orchestration and meta

| Skill | What it does | Trigger |
| --- | --- | --- |
| [coordinator](skills/coordinator/SKILL.md) | Orchestrates multiple worktree agents via `workmux`: spawn, monitor, communicate, merge. | `/coordinator` |
| [create-skill](skills/create-skill/SKILL.md) | Interactively authors a new Claude Code skill. | `/create-skill [personal\|project] [name]` |

## Workflows

Deterministic, multi-agent orchestration scripts for the Claude Code `Workflow` tool. Invoke with `Workflow({ name: "<name>", args: ... })`.

| Workflow | What it does | Best for |
| --- | --- | --- |
| [ticket-fanout](workflows/ticket-fanout.js) | Implements N tickets in parallel. Each ticket gets an isolated-worktree agent that installs, implements to a green project check and opens a draft MR or PR, then a reviewer agent reviews the diff. Repo conventions are detected or passed via `args`. | Batches of small, independent tickets you review after the fact. Not for work that needs live QA or tickets that touch the same files. |

```js
Workflow({ name: "ticket-fanout", args: ["ENG-1", "ENG-2"] })
Workflow({ name: "ticket-fanout", args: {
  tickets: [{ key: "ENG-1", spec: "narrow the pagination" }],
  check: "pnpm check",
  bootstrapFiles: [".env.development.local"],
  contextCommand: "acli jira workitem view {key}",
}})
```

## Adding a new skill

1. Create `skills/<name>/SKILL.md` with frontmatter:
   ```
   ---
   name: <name>
   description: <when to use this skill>
   ---
   ```
2. Write the body: instructions Claude follows when the skill runs.
3. Run `./bin/install.sh` to symlink it.
4. Add a row to the table above, commit and push.

## Adding a new workflow

1. Create `workflows/<name>.js`. It must `export const meta = { name, description, phases }` (a pure literal) followed by the script body using `agent()` / `pipeline()` / `parallel()`.
2. Run `./bin/install.sh` to symlink it into `~/.claude/workflows/`.
3. Invoke with `Workflow({ name: "<name>", args: ... })`.
4. Add a row to the table above, commit and push.
