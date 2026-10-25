---
name: resolve-reviews
description: Pulls open review threads on the current branch's GitLab MR (async-agent, design review, human reviewers), fixes each finding in code, reacts to the reviewer's comment with a fitting emoji, and replies inside each thread in the user's conversational voice (no em dashes, first-person, grounded in what they actually tested) rather than posting a new top-level comment. Use when the user says "go through the async agent comments", "fix the review comments", "address the MR comments", "resolve the review threads", or pastes reviewer feedback and asks to fix and reply.
metadata:
  tags:
    - gitlab
    - code-review
    - workflow
  status: recommended
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(glab mr list:*), Bash(glab mr view:*), Bash(glab api:*), Bash(rg:*), Bash(cat:*)
---

# Resolve Reviews

Work through the open review threads on an MR: understand each finding, fix it in code, and reply **in that thread**. This skill exists because the user does this almost weekly (async-agent + design review + human reviewers) and has had to correct the same things repeatedly: reply *in the thread* not as a separate comment, write the reply in their actual conversational voice (not a robotic acknowledgement + spec), and react to the reviewer's comment with a fitting emoji before replying.

## When to Use

- "go through the async agent comments and solve them"
- "fix the review comments" / "address the MR comments"
- "resolve the review threads" / "reply to the threads"
- The user pastes reviewer feedback (often async-agent or a design-review block) and asks to fix it

## Non-Negotiable Rules

1. **React to the reviewer's comment with a fitting emoji before replying.** Award an emoji on their note, then post the reply. Pick one that matches the situation (see the palette in step 4) rather than always using the same one.
2. **Reply in the thread, not as a new comment.** Use the discussion-notes API so the reply threads under the original finding. A fresh top-level comment is the wrong place. The user has corrected this explicitly.
3. **The user's conversational voice, not a robotic acknowledgement + spec.** This is the one they flagged hardest. Replies that open "Good callout. Made the three pre-submit validation toasts transient with an explicit 5s duration..." read AI-written. Their real replies are casual and first-person, often opening with "Yeah" or "Hmm yeah", and they say what they actually saw or did while testing. One they wrote themselves: *"Hmm yeah it looks like right just trying to break the multi-file upload failure at most I can see a max of 5 error toasts being rendered at once... I think it's worth capping here."* Aim for that texture: agree naturally, describe the change like you're talking to a colleague, and mention testing only when it's the deciding reason (see rule 6 on length).
4. **No em dashes. No exclamation points. No "Great catch" / "Thanks".** Capitalize "I". Keep it brief. Own mistakes plainly ("Oops, mine. Removed."). When pushing back, stay non-confrontational, explain current behavior matter-of-factly, link evidence, and offer a follow-up rather than asserting someone is wrong.
5. **Don't silently skip findings.** If you can't address one, ask a clarifying question in the thread first.
6. **Two or three sentences, max.** Lead with the verdict, give the one reason that settles it, put evidence in hyperlinks instead of prose, end with the follow-up offer if any. Cut the walkthrough (how the bug happens, what the alternative would cost, what staging showed) unless the reviewer asked. A six-sentence pushback once got cut to: *"Hmm I think this one's on the upstream service. It writes the two tiers when Auto Mode is enabled ([policy-sync.ts](link)), and its legacy approve path already fails on them, editor or not ([approval-decision.ts](link)). Could file a follow-up there."*

## Workflow

### 1. Find the MR and its threads

```bash
git branch --show-current
glab mr list --source-branch="$(git branch --show-current)" --state=opened
```

Pull the discussions (threads) for the MR. Resolve project + MR iid, then:

```bash
glab api "projects/:id/merge_requests/<iid>/discussions?per_page=100"
```

Each discussion has an `id` and one or more `notes`. Focus on unresolved discussions with `resolvable: true` and `resolved: false`. Capture for each: the discussion `id`, the file/line, and the finding text.

**Pre-flight: is the branch behind its target?** While you have the MR, check the drift, because a stale branch is worth catching up in the same pass:

```bash
TARGET=$(glab api "projects/:id/merge_requests/<iid>" | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_branch"])')
git fetch origin "$TARGET" && git rev-list --left-right --count origin/"$TARGET"...HEAD   # "<behind>\t<ahead>"
```

If it's behind by more than a couple commits (GitLab will also show "this branch is N commits behind"), hand off to the `rebase-on-target` skill to fetch + rebase + force-push-with-lease, then come back and finish the threads on the rebased head.

### 2. Triage each finding

For every open thread, decide: fix it, or push back with reasoning.

- **Fix**: make the code change. Group related fixes into a sensible commit.
- **Push back**: only when the current behavior is intentional. Explain it plainly with a link (code permalink, ticket, docs) and suggest a follow-up if it is non-blocking.

### 3. Apply fixes and push

Make the edits, run the project's checks (`pnpm check` / tests as relevant), then commit and push. Use the `git-commit` skill for the message. (`git push` and commits stay user-confirmed.)

### 4. React, then reply in each thread

For each thread, first react to the **reviewer's** note with a fitting emoji, then post the reply note under that same discussion.

**4a. React to the reviewer's note.** The first note in a discussion's `notes` array is the original finding. Award an emoji on it:

```bash
glab api -X POST \
  "projects/:id/merge_requests/<iid>/notes/<reviewer_note_id>/award_emoji" \
  -f name=<emoji>
```

Pick the emoji to match the situation, don't default to the same one every time:

| Situation | Emoji (`name`) |
| --- | --- |
| Agreed and fixing / fixed it | `thumbsup` (👍) |
| Acknowledging, digging in now (or replying with a clarifying question) | `eyes` (👀) |
| Good catch on a real bug / sharp point | `bulb` (💡) or `100` (💯) |
| Done / resolved cleanly | `white_check_mark` (✅) |
| Pushing back, friendly disagreement | `thinking` (🤔) |

**4b. Reply under the discussion** (not a new top-level discussion):

```bash
glab api -X POST \
  "projects/:id/merge_requests/<iid>/discussions/<discussion_id>/notes" \
  -f body="<reply in the user's conversational voice>"
```

Reply content: agree naturally, say what you changed like you're talking to a colleague, mention what testing showed, append the commit short-hash. Match the texture of their real replies, not a formal acknowledgement + spec. Examples:

- "Yeah agreed, those don't really need to stick around since you just re-drop. Put them back to a 5s duration so they self-clear. <commit>"
- "Yeah went ahead and capped it at 5, that's the most I could get to render at once when I was trying to break it. Past that the oldest drop off. <commit>"
- "Hmm I think this one's working as intended actually, the early-return guard at server.ts:162 already covers it. <link> Could file a follow-up if it's worth a second look."

Avoid: "Good callout. Made the three pre-submit validation toasts transient with an explicit 5s duration..." (reads AI-written).

### 5. Optionally resolve

If a thread is fully addressed and the user wants it closed, resolve it:

```bash
glab api -X PUT \
  "projects/:id/merge_requests/<iid>/discussions/<discussion_id>?resolved=true"
```

Ask before mass-resolving. Some reviewers prefer to resolve their own threads.

## Output

Summarize what you fixed, what you pushed back on (with reasoning), and which threads you replied to. List anything you need the user to decide before replying.
