---
name: mr-draft
description: Writes or updates a GitLab MR description using the repo's MR template, in the user's voice (no AI slop, no em dashes, reviewer-readable), preserving any screenshots/Looms already added. Use when the user says "draft MR", "open a draft MR", "fill in/out the MR description", "write the MR description", "update the MR description", or "make a draft MR and fill in the description".
metadata:
  tags:
    - gitlab
    - workflow
    - writing
  status: recommended
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(glab mr list:*), Bash(glab mr view:*), Bash(ls:*), Bash(cat:*), Bash(find:*), AskUserQuestion
---

# MR Draft

Generate or update a GitLab MR description that follows the repo's own template and reads like the user wrote it. This skill exists because the same instruction was given ~19 times in 30 days: "make a draft MR, fill in the description using the template, don't make it AI slop, and keep my screenshots."

## When to Use

- "open a draft MR" / "make a draft MR and fill in the description"
- "fill in/out the MR description"
- "update the MR description" / "rewrite the MR description"
- After work is committed and pushed, when an MR description is needed

## Non-Negotiable Rules

These are the corrections the user has had to repeat. Follow them every time.

1. **Use the repo's MR template.** Find it at `.gitlab/merge_request_templates/*.md` (usually `Default.md`). Use its exact section structure. Do not invent your own layout.
2. **No AI slop.** No filler, no "This MR introduces a comprehensive solution that…", no restating the obvious. Say what it does and why, plainly.
3. **No em dashes.** Ever. Use commas, parentheses, or short sentences.
4. **Capitalize "I".**
5. **Preserve what the user already added.** If an MR already exists, fetch the current description first (`glab mr view`). Never strip screenshots, Loom links, images, or the recording link they pasted. Edit around them.
6. **Plain language, assume a non-technical reader.** Write as if a PM or anyone without an engineering background will read this, not just other developers. No file paths, function/variable names, package names, or code-level detail in the description body, that belongs in the diff, not the prose. Every section should be a sentence or two. Say what changed and why in terms of user/business outcome, not implementation. Before finalizing, sanity-check: could a PM read this and understand it without knowing the codebase? If not, cut the jargon and simplify further.
7. **Hyperlink** the Jira ticket, related MRs, and relevant commits.
8. **Draft by default.** Create MRs as draft unless told otherwise.
9. **Never fabricate a recording link.** If the template has a "Recording link" field and the user hasn't given one, leave the placeholder and remind them to paste the Loom.

## Workflow

### 1. Gather context

```bash
git branch --show-current
git diff main...HEAD            # full cumulative diff, not just last commit
git log main..HEAD --oneline
glab mr list --source-branch="$(git branch --show-current)" --state=opened
```

If an MR already exists, read its current description so you preserve media:

```bash
glab mr view <iid>
```

### 2. Locate the template

```bash
find .gitlab/merge_request_templates -iname "*.md"
cat .gitlab/merge_request_templates/Default.md
```

Adopt its sections verbatim (e.g. Demo Recording, Summary, Test Plan, Related). Some repos require a demo recording before merge. honor that section.

### 3. Pull the Jira ticket (if branch has one)

Parse the ticket key (e.g. `PROJ-1234`) from the branch. Use the `jira-cli` skill (`acli jira workitem view <KEY>`) to pull title and intent so the Summary reflects the real purpose, not a diff restatement.

### 4. Write the description

Fill every section. Keep it tight:

- **Summary**: what changed and why, in 2-5 sentences. Reviewer-first.
- **Test Plan**: how it was verified beyond the recording (unit/integration/manual QA). If you need the manual QA steps, the `qa-script` skill generates them.
- **Related**: hyperlink the Jira ticket, related MRs, Slack threads.
- Preserve any recording link / screenshots already present.

### 5. Create or update (requires confirmation)

`glab mr create` / `glab mr update` are intentionally not in allowed-tools so the user approves the final text first.

New draft MR:

```bash
glab mr create --draft --source-branch "$(git branch --show-current)" \
  --title "<TICKET>: <concise title>" \
  --description "$(cat <<'DESC'
<filled template>
DESC
)"
```

Update existing:

```bash
glab mr update <iid> --description "$(cat <<'DESC'
<filled template, with their screenshots/Looms preserved>
DESC
)"
```

When updating, the description must reflect the **current cumulative state** of all commits, not just the latest one. Drop references to things added then removed during iteration.

## Voice Reference

Casual but professional, like talking to a colleague. No exclamation points. No em dashes. Short sentences. Own tradeoffs plainly. Write as if the user typed it themselves.
