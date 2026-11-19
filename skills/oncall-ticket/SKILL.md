---
name: oncall-ticket
description: Files or updates a Jira ticket under the current month's on-call epic, formatted in Jira wiki markup (not markdown) and written in the user's voice. Use when the user says "create a jira ticket in the on-call bucket", "file an on-call ticket", "make an on-call ticket for this", "put this in the on-call epic", or "fix the formatting on this jira ticket".
metadata:
  tags:
    - jira
    - oncall
    - workflow
allowed-tools: Bash(acli jira auth:*), Bash(acli jira workitem view:*), Bash(acli jira workitem search:*), Bash(acli jira filter list:*), Bash(acli jira filter get:*), AskUserQuestion
---

# On-call Ticket

File or update a Jira ticket placed under the current month's on-call epic, formatted correctly for Jira. This skill exists because on-call tickets get filed every month and the same two things keep needing a fix: (a) pointing the ticket at the right on-call epic and (b) the formatting, since Jira uses wiki markup, not markdown.

Builds on the `jira-cli` skill (`acli jira`). This skill adds the on-call placement and formatting.

## When to Use

- "create a jira ticket in the on-call bucket / on-call epic"
- "file an on-call ticket"
- "put this in the May/June on-call epic"
- "fix the formatting on this jira ticket" (it came out as markdown)

## Inputs

- **Project key** that holds the on-call epics (for example `OPS`). Ask if it is not given and not obvious from earlier in the session. Never guess.
- **Epic naming pattern**. Default: `On-Call [<Month> <Year>]`, one epic per month.

## Non-Negotiable Rules

1. **Jira wiki markup, not markdown.** This is the repeated correction. Jira does not render markdown.
   - Headings: `h2.` `h3.` (not `##`)
   - Bold: `*bold*` (not `**bold**`)
   - Inline code: `{{code}}`; code block: `{code}...{code}`
   - Bullets: `*` / `**` for nesting; numbered: `#`
   - Links: `[text|https://url]` (not `[text](url)`)
   - No em dashes anywhere.
2. **Place it under the current month's on-call epic** (see step 2). A team's standing epic is not the on-call epic.
3. **Follow the project's ticket rules**: use an issue type the project actually has, set `--parent` to the on-call epic, assign to the authenticated user (use the `acli jira auth status` email, not `@me`), and fill in any field the workflow requires before a ticket can move.
4. **The user's voice** in summary and description: plain, direct, short sentences, capitalize "I".

## Workflow

### 1. Confirm auth and identity

```bash
acli jira auth status     # also gives the email to assign to
```

### 2. Find the current month's on-call epic

The on-call epic is named for the month and year. Search for it:

```bash
acli jira workitem search --jql 'project = <PROJECT> AND issuetype = Epic AND summary ~ "On-Call" ORDER BY created DESC'
```

Match the epic for the current month and year (today is the reference). If several match or none clearly does, use AskUserQuestion to confirm the epic key before creating anything.

### 3. Gather ticket content

- Title: concise, names the problem.
- Description in wiki markup: what is broken or needed, context, a link to the similar MR or ticket if the user referenced one (`[MR !123|url]`), and acceptance criteria as a `#` numbered list.
- If this is paired with a fix MR, link it under a `h3. Related` section.

### 4. Create (or update) the ticket, with confirmation

`acli jira workitem create` is intentionally not in allowed-tools so the user approves the final content. Build the command with:

- `--type` set to an issue type the project has (Story, Task or Bug)
- `--parent <ONCALL-EPIC-KEY>`
- assignee = authenticated email
- any required custom fields
- description body in wiki markup

For an existing ticket whose **formatting is wrong**, re-render the existing description into proper wiki markup and update it in place, preserving the actual content and any links the user added.

### 5. Confirm

Show the epic it landed under, the ticket key and the URL. Keep the recap short.
