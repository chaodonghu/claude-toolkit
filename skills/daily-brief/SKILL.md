---
name: daily-brief
description: Start-of-day and end-of-day brief. Covers what needs you (reviews, threads, mentions), your open MRs and tickets, the upstream watch, the channels you follow and the next ticket to pick. Use for scheduled morning and end-of-day runs, or when the user asks "catch me up" or "what's going on".
---

# Daily brief

Argument: `morning`, `evening` or `now`.

- **Morning** covers everything since the last brief. Add today's calendar.
- **Evening** covers today. Add what is still open going into tomorrow.

The baseline is the last entry in `~/.cache/daily-brief/log.md`. Read it first. If it is missing, use the previous weekday at 17:00 local time.

## Configure once

Fill these in before the first run. Everything below refers to them by name.

| Setting | Value |
|---|---|
| GitLab username | `<gitlab-username>` |
| Jira account id | `<jira-account-id>` |
| Slack user id | `<slack-user-id>` |
| Channels to follow | `<channel ids>` |
| Epic to track | `<EPIC-KEY>` (optional) |
| Upstream watch | name of an `upstream-watch` config (optional) |
| Living docs | paths of the guides to keep current (optional) |

## Constraints

- Read only:
  - Never send Slack messages. Drafts only, and only if the user asks.
  - Never flip MR draft state or labels.
  - Never transition tickets.
- Wrap `glab` calls in `timeout 60`.
- Jira goes through `acli jira` or the Atlassian MCP, whichever is authenticated.
- No em dashes. Link every MR, ticket and Slack thread.
- Keep it concise. Skip any section with nothing new, and say "Nothing new" only if every section is empty.

## Checks

Run these in parallel where you can.

### 1. Needs you
- MRs where the user is a reviewer and has not approved: `glab api "merge_requests?scope=all&state=opened&reviewer_username=<gitlab-username>"`, then drop any whose `/approvals` already lists them in `approved_by`. An MR they approved is done from their side, even if it is still open or needs other approvers. Never list it again.
- Unresolved discussion threads on the user's open MRs whose last note is not theirs.
- Slack messages since the baseline that mention them, or DMs they have not replied to. Search `<@slack-user-id>` with an `after:` date.
- Jira comments since the baseline that mention them or are on their tickets.

### 2. Your MRs
The user's open MRs across all projects: `glab api "merge_requests?scope=all&state=opened&author_username=<gitlab-username>"`. For each, report:
- Draft or ready
- Pipeline status, with the failed job names if it is red
- Approvals
- New comments since the baseline
- Whether it is 5 or more commits behind the target

Also list the MRs that merged since the baseline.

### 3. Your Jira
Run `assignee = <jira-account-id> AND statusCategory != Done`, plus the user's tickets resolved since the baseline. Report:
- Status changes
- New tickets assigned to them
- Blockers that moved to Done, which means the ticket is now unblocked

If an epic is configured, give a one-line state for it.

### 4. Upstream
If an upstream watch is configured, run the `upstream-watch` skill checks with the same argument. Fold its report in as this section in three to six bullets, and let it update its own baseline as usual.

### 5. Channels
For each followed channel, summarize the threads since the baseline that touch the user's work in one line each. Skip anything the upstream section already covers.

### 6. Calendar (morning only)
List today's meetings with local times. Flag any that need prep, for example a demo or a review of the user's work.

### 7. Living docs (evening only)
Only when living docs are configured. If anything merged, shipped or got decided today that changes how the feature works (a slice landing, a flag or contract change, a decision closed, a new way to test it), update the affected paragraphs and refresh the "Where it stands" date. These are guides to what the feature is and how it works. Describe the behavior and the outcome, link the epic at most, never individual tickets or MRs, no ticket-by-ticket status. If nothing relevant happened, leave them alone and say nothing. If a write needs an approval, put the approval link in the brief under "Needs you" and retry once the user approves.

## Report format

```
**<Morning|Evening> brief, <date>**

**Needs you**
- ...

**Your MRs**
- ...

**Your Jira**
- ...

**Upstream**
- ...

**Channels**
- ...

**Today** (morning only)
- ...

**Living docs** (evening only, and only when something was updated)
- ...

**Next up:** <one ticket or action, and why>
```

"Needs you" always comes first. Each bullet is a single line led by a link.

## Log

After reporting, append one line to `~/.cache/daily-brief/log.md`:

```
<ISO timestamp> <morning|evening|now> mrs=<open MR iids> reviews=<pending review iids> jira=<open ticket keys>
```

The next run diffs against it.

## Scheduling

Meant to run twice on weekdays, once as the day starts and once as it ends (for example 09:03 and 16:57 local), from whatever scheduler you already use. Pass `morning` or `evening` as the argument.
