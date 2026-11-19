---
name: upstream-watch
description: Recurring watch on the upstream work a feature depends on. Checks the upstream repo's code and API spec, related MRs, the epics and their children, contract drift against your local client, and the team's Slack channels, then reports only what changed since the last dated entry in the watch log. Use for scheduled morning and afternoon runs, or when the user asks "anything new on the backend?" or "did anything change upstream?".
---

# Upstream watch

Report only changes since the last check, in a short message. If nothing changed, say so in one line.

The baseline is the latest dated entry in the watch log, `~/.claude/upstream-watch/<watch-name>.md`. Read its last three entries first. They hold the current MR numbers, open questions and pending triggers.

Argument: `morning`, `afternoon` or `now` (ad hoc). It only changes the wording of the report header.

## Configure once per feature

Keep this block at the top of the watch log and fill it in. The checks below refer to these names.

| Setting | What goes here |
|---|---|
| Upstream repo | local checkout path and the remote project path |
| Watched paths | the directories and spec file your feature depends on |
| MR filter | a regex of keywords and ticket prefixes that mark an MR as relevant |
| Epics | the initiative and epic keys the upstream tickets live under |
| Contract | the upstream spec path and your local copy of it, plus the routes and schemas you care about |
| Channels | the Slack channel ids to read |
| Your repo | your checkout, plus any open worktree that carries a newer contract |

## Constraints

- Slack is read only. Never send or draft unless the user asks.
- Tickets through `acli jira` or the Atlassian MCP, whichever is authenticated.
- Wrap `glab` calls in `timeout 60`.
- No em dashes in anything written as the user.

## Checks

Run the independent ones in parallel. `SINCE` is the timestamp of the baseline entry.

### 1. Upstream commits

```bash
cd <upstream-checkout> && git fetch -q origin main
git log origin/main --since="$SINCE" --format="%h %ad %an %s" --date=iso -- <watched paths>
```

If `git fetch` hangs on a large repo, use the API instead:
`glab api "projects/<url-encoded-project>/repository/commits?ref_name=main&since=$SINCE&path=<watched path>"`, once per watched path, and fetch the spec with the repository files API for the drift check.

### 2. Upstream merge requests

List MRs on the upstream project with `updated_after=$SINCE&state=all&order_by=updated_at&per_page=100` and keep those whose title or description matches the MR filter. Then fetch each MR named in the baseline entry directly (state, draft flag, `head_pipeline.status`, `merged_at`). An MR for a ticket listed under Triggers is a trigger.

### 3. Tickets

Upstream tickets fan out across epics and move between them, so resolve the epic set first instead of hardcoding one parent.

Step one, the epics under the configured initiatives plus any standalone epics:

```
(parent in (<initiative keys>) AND issuetype = Epic) OR key in (<standalone epic keys>)
```

Step two, everything under those epics that moved, plus anything new that mentions the feature:

```
(parent in (<epic keys from step one>) AND updated >= "<SINCE local>")
OR (project in (<projects>) AND text ~ "<feature keyword>" AND created >= "<SINCE local>")
```

Report status changes, new children, assignees and re-parenting. When a new epic appears in step one, add it to the config block. When work rolls over from one epic to another, query both until the old one is closed.

### 4. Contract drift

Compare the upstream spec on `origin/main` with your local copy. Only lines touching the routes and schemas in the config matter. Flag changed limits, renamed fields or enum values, id patterns, new required fields and new error codes. Drift outside your routes (other teams' endpoints) is a one-line mention, not an action.

When relevant drift exists, the fix is to regenerate the client in a branch, keeping only the changes to the client you depend on and reverting unrelated churn.

### 5. Slack (read only)

Read new messages since `SINCE` in the configured channels, including any recurring review or demo threads. If a channel has been archived or merged into another, update the config block and stop checking it.

### 6. Adjacent tracks

Anything else that will change what your feature shows or needs once it lands, such as enforcement going live, a new required step in the flow or a schema version change. Query those epics the same way as check 3, and list MRs in the related repos updated since `SINCE` that reference their keys. Skip dependency-bot MRs.

Call out anything that changes behavior your feature depends on. Be specific about what is harmless (an unused variant removed) and what is not (the shape you read changing).

## Triggers

Keep a short list in the watch log of the conditions you are waiting on. Each trigger has three parts:

- **Condition.** A named ticket moves, or its MR opens or merges.
- **Impact.** What changes in the contract or the behavior.
- **Action.** What you do on your side when it fires, down to the command.

When a trigger fires and the action is done, mark it done with the MR numbers and times, and from then on only flag new changes.

Standing trigger: **before a scheduled demo**, confirm the demo still matches the environment it runs against and flag any upstream MR that landed there since it was prepared.

## Report

One short message in this order: merged, opened, moved, drift, Slack, adjacent tracks. Only the items that changed. For anything that changes the contract or behavior your feature depends on, say exactly what would need to change on your side and offer to start it. Finish with one line saying whether anything changes the feature or the demo.

If you own a queue of dependent tickets, end with: "Next pickable ticket: <key> because <reason>". A ticket is pickable when its blockers are Done or when it can be built against mocks shaped like the agreed contract.

## Memory

Only if something changed, append one dated paragraph to the watch log with the same facts, including MR numbers, commit hashes and merge times, so the next run has its baseline.
