---
name: jira-cli
description: Reference for interacting with Jira via the official Atlassian CLI (`acli jira`). Covers viewing tickets, creating tickets with custom fields, and searching with JQL/filters.
metadata:
  tags:
    - project-management
  status: recommended
allowed-tools:
  - Bash(acli jira auth:*)
  - Bash(acli jira workitem view:*)
  - Bash(acli jira workitem search:*)
  - Bash(acli jira workitem comment list:*)
  - Bash(acli jira filter list:*)
  - Bash(acli jira filter get:*)
---

# Jira CLI Reference (`acli jira`)

Use `acli jira` for all Jira operations. Do NOT use the unofficial `jira` CLI.

## Authentication

Always authenticate with `acli jira auth` (not `acli auth` — that subcommand does not exist):

```bash
acli jira auth status         # check current auth
acli jira auth login          # log in
```

## View a Ticket

```bash
acli jira workitem view KEY-123
acli jira workitem view KEY-123 --fields '*all'    # all fields
acli jira workitem view KEY-123 --json              # JSON output
acli jira workitem view KEY-123 --web               # open in browser
```

## Create a Ticket

### IMPORTANT: Descriptions must use ADF, not Markdown

Jira does **not** render Markdown. The `--description` flag sends plain text only — headings, links, bold, lists, and code will appear as raw text.

**Always use `--from-json` with Atlassian Document Format (ADF)** for descriptions that need any formatting. Write the JSON to a temp file and pass it with `--from-json /tmp/workitem.json`.

### Simple (plain text only, no formatting)

Only use `--description` when the description is truly plain text with no formatting needed:

```bash
acli jira workitem create \
  --project PROJECT \
  --type Story \
  --summary "Do the thing" \
  --assignee user@example.com \
  --parent EPIC-123 \
  --description "Plain text description with no formatting"
```

### With ADF description (recommended)

Use `--from-json` for any description that needs headings, links, lists, bold, or code:

```json
{
  "projectKey": "PROJECT",
  "type": "Story",
  "summary": "Do the thing",
  "assignee": "user@example.com",
  "parentIssueId": "EPIC-123",
  "description": {
    "type": "doc",
    "version": 1,
    "content": [
      {
        "type": "heading",
        "attrs": { "level": 2 },
        "content": [{ "type": "text", "text": "Section heading" }]
      },
      {
        "type": "paragraph",
        "content": [
          { "type": "text", "text": "Regular text, " },
          { "type": "text", "text": "bold text", "marks": [{ "type": "strong" }] },
          { "type": "text", "text": ", " },
          { "type": "text", "text": "code", "marks": [{ "type": "code" }] },
          { "type": "text", "text": ", and " },
          {
            "type": "text",
            "text": "a link",
            "marks": [{ "type": "link", "attrs": { "href": "https://example.com" } }]
          },
          { "type": "text", "text": "." }
        ]
      },
      {
        "type": "bulletList",
        "content": [
          {
            "type": "listItem",
            "content": [{
              "type": "paragraph",
              "content": [{ "type": "text", "text": "List item one" }]
            }]
          },
          {
            "type": "listItem",
            "content": [{
              "type": "paragraph",
              "content": [{ "type": "text", "text": "List item two" }]
            }]
          }
        ]
      },
      {
        "type": "codeBlock",
        "attrs": { "language": "python" },
        "content": [{ "type": "text", "text": "def example():\n    return True" }]
      }
    ]
  }
}
```

```bash
acli jira workitem create --from-json /tmp/workitem.json
```

### ADF quick reference

| Element | ADF type | Key attributes |
|---------|----------|----------------|
| Heading | `heading` | `attrs.level` (1-6) |
| Paragraph | `paragraph` | — |
| Bullet list | `bulletList` > `listItem` > `paragraph` | — |
| Numbered list | `orderedList` > `listItem` > `paragraph` | — |
| Code block | `codeBlock` | `attrs.language` |
| Bold | text mark `strong` | — |
| Italic | text mark `em` | — |
| Inline code | text mark `code` | — |
| Link | text mark `link` | `attrs.href` |

## Edit a Ticket

```bash
acli jira workitem edit --key KEY-123 --summary "Updated summary"
acli jira workitem edit --key KEY-123 --assignee user@example.com
```

For editing descriptions or custom fields, use `--from-json` with ADF (same format as create). Include `"issues": ["KEY-123"]` in the JSON instead of using `--key`:

```json
{
  "issues": ["KEY-123"],
  "description": { "type": "doc", "version": 1, "content": ["...ADF content..."] }
}
```

```bash
echo "y" | acli jira workitem edit --from-json /tmp/edit.json
```

Note: `workitem edit` does not support `--yes` — pipe `echo "y"` to confirm.

## Search (JQL / Filters)

### By JQL

```bash
acli jira workitem search --jql "project = PROJ AND assignee = currentUser() ORDER BY priority DESC"
acli jira workitem search --jql "sprint in openSprints() AND assignee = currentUser()"
acli jira workitem search --jql "..." --fields "key,summary,status,priority" --limit 20
```

### By Filter ID

```bash
acli jira workitem search --filter 12345
acli jira workitem search --filter 12345 --fields "key,summary,status,priority"
```

### List Your Filters

```bash
acli jira filter list --my
acli jira filter list --favourite
acli jira filter get --id 12345          # view filter details/JQL
```

## Comments

```bash
acli jira workitem comment list KEY-123
acli jira workitem comment create KEY-123 --body "Comment text"
```

## Transition (move status)

```bash
acli jira workitem transition --key KEY-123 --status "In Progress" --yes
```

Use `--yes` to skip confirmation prompt (required for non-interactive use).

## Common Mistakes

- **Auth is under `acli jira auth`, not `acli auth`** — `acli auth` does not exist. Use `acli jira auth status` / `acli jira auth login`
- **No `--action` flag** — `acli jira` uses subcommands, not `--action`. Use `acli jira workitem create`, not `acli jira --action createIssue`
- **No `--issue` flag** — use `--key` for identifying work items
- **No `--state` flag** — use `--status` for transitions
