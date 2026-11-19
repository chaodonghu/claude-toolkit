---
name: cross-lab-review
description: Fully automated cross-lab adversarial code review — Claude and Codex (OpenAI) each review the changeset independently and blind, then attack each other's findings, then defend their own. Surfaces which defects survived cross-examination, which were killed, which remain contested, and which one lab saw that the other missed entirely. No human in the loop during the debate. Works on GitLab MR URLs, `!IID` refs, branch diffs, or the working tree. Use when the user invokes `/cross-lab-review`, or asks for a cross-lab review, two-lab review, adversarial review, Claude-vs-Codex review, "have the models fight about it", or wants findings stress-tested by a second lab rather than a single model's opinion.
argument-hint: "<mr-url|!IID|branch|--staged> [focus... (default: high+ only)]"
allowed-tools: Read, Glob, Grep, Write, Agent, SendMessage, mcp__codex__codex, mcp__codex__codex-reply, Bash(git:*), Bash(glab:*), Bash(codex:*), Bash(jq:*), Bash(wc:*)
---

# Cross-Lab Adversarial Review

Two labs review the same changeset blind, then cross-examine each other. The output is not
a findings list — it is a findings list **with the survival record attached**.

Why this exists: a single model's review has a 32–73% false-positive rate on correct code,
and a second model shown the first model's conclusions tends to ratify them. Blind
independent passes plus forced refutation is what converts opinion into evidence.

## Non-negotiable: two labs or abort

**Preflight before anything else.** Confirm the Codex arm is reachable:

```bash
codex --version   # must be >= 0.144 for the gpt-5.6 family
```

Then make one trivial `mcp__codex__codex` call to confirm the MCP server answers.

If Codex is unreachable — **stop and tell the user.** Do not fall back to a Claude-only
review. A single-lab run wearing this skill's name is worse than no run: it reports
cross-examined confidence that was never cross-examined. Say what broke and point at
`brew upgrade codex` or `claude mcp list`.

## Input resolution

This skill targets **GitLab** via `glab`; there is no GitHub path.

| Argument | Action |
|---|---|
| MR URL or `!IID` | `glab mr diff` + `glab mr view` for the description |
| `--staged` | `git diff --cached` |
| branch name or `a..b` | `git diff <range>` |
| nothing | `git diff` → if empty `git diff --cached` → if empty `git diff origin/<default-branch>...HEAD` |

Trailing text after the target is **focus** — pass it into both find prompts verbatim.
With no trailing text, focus defaults to this, verbatim: `only looking for
high+ priority issues. showstoppers/blockers/big regressions.` Explicit trailing text
replaces the default (e.g. "all severities").

Measure size with `git diff --shortstat` (or `--stat` on the MR). Past ~500 changed lines,
select the highest-risk files rather than sending everything, and **record in the report
what you excluded and why**. Silent truncation reads as full coverage.

On an MR, also fetch existing discussion notes and skip anything human reviewers already
raised — say so rather than re-reporting it.

## Phases

Prompt templates are in `references/prompts.md`. Read it before Phase 1. The wording is
load-bearing; do not paraphrase.

### Phase 1 — Blind independent find

Run both arms **concurrently**, neither seeing the other:

- **Claude arm**: dispatch via `Agent` with the FIND prompt. Use a subagent, not this
  conversation — if the changeset has already been discussed here, that context
  contaminates the pass and destroys independence. **Background Agent subagents do not
  auto-deliver their plain-text final answer** — the orchestrator never sees it, only
  idle notifications. Append this line, verbatim, to every Claude-arm spawn prompt
  (find, refute, and defend alike): "When you have your final answer, call SendMessage
  with `{\"to\": \"main\", \"message\": \"<your JSON>\"}`, and start that message with one
  line of plain text before the JSON — a `message` beginning with `{` is parsed as a
  protocol object and rejected. Do not just end your turn with plain text; it will not be
  delivered." If a spawned agent goes idle without having sent that message, SendMessage
  it a one-line reminder rather than re-spawning.
- **Codex arm**: `mcp__codex__codex` with the same FIND prompt.
  ```
  model: "gpt-5.6-terra"        // gpt-5.6-sol if the user asks for maximum depth
  sandbox: "read-only"
  approval-policy: "never"
  cwd: "<repo root>"            // required, or Codex cannot read the files
  config: {"model_reasoning_effort": "high"}
  ```
  **Store the returned `threadId`** — Phase 3 needs it.

Assign stable `finding_id`s, namespaced by origin (`c1, c2…` Claude / `x1, x2…` Codex).
Track which lab found what, but **never reveal origin to the other lab.**

Do not merge near-duplicates yet. Two labs describing the same line differently is signal
about which framing holds up — collapsing it early throws that away. Only merge when the
claim is genuinely identical.

### Phase 2 — Blind cross-refutation

Each lab attacks the other's findings. **Send the stripped projection only:**

```
{finding_id, file, line_range, claim}
```

No severity, no confidence, no rationale, no origin. Withholding severity is the whole
mechanism — see `references/prompts.md` §2.

Fan out concurrently: one Codex call per Claude finding, one Agent per Codex finding.
Batch them into as few turns as possible.

### Phase 3 — Defend

Send each refutation back to the lab that originated the finding, with the REFUTE
reasoning. For Codex use **`mcp__codex__codex-reply` with the stored `threadId`** so it
still remembers its own analysis — a fresh session defends worse.

Skip findings whose refuter already conceded; nothing to defend.

### Phase 4 — Resolve, don't adjudicate

Classify mechanically:

| Refuter | Originator | Verdict |
|---|---|---|
| conceded | — | **Survived** |
| refuted | concede | **Killed** |
| refuted | hold | **Contested** |
| partial | narrow / hold | **Narrowed** — record the surviving claim |

**Contested stays contested.** Do not break the tie. You are a participant in this debate,
so casting the deciding vote hands the outcome back to one lab. Present both positions with
their code references and let the user rule.

Then compute the highest-value output — **blind-spot findings**: anything one lab found
that the other neither found independently *nor* successfully refuted. That is the direct
measure of what a single-lab review would have missed.

### Phase 5 — Report

Write to `/tmp/cross-lab-review-<identifier>.md` and print the tables plus the contested
section inline. Do not print the whole document.

```markdown
# Cross-Lab Review: <target>

| | |
|---|---|
| Scope | <files; note exclusions> |
| Input | <MR !N / range / staged> |
| Arms | Claude <model> vs Codex <model> |
| Raw findings | <n> Claude, <m> Codex |
| Survived / Killed / Contested | <a> / <b> <c> |
| High+ routing | <ids → implementer, not posted / not reachable / none> (Phase 6) |
| Re-checks (round ≥2) | <id: fixed / still standing> |

## Survived cross-examination
| ID | Severity | File:line | Claim | Refuter conceded because |

## Contested — needs your call
For each: the claim, the refutation, the defence, all with file:line. State the crux —
the one factual question that settles it. No recommendation.

## Blind spots
| ID | Found by | Claim | Why the other lab missed it |

## Killed
| ID | Claim | What disproved it |
One line each. Present so the user can spot a wrongly-killed finding.

## Coverage gaps
Files excluded, findings not fully cross-examined, arms that errored.
```

Severity in the final report is the **refuter's independent `own_severity`**, not the
originator's self-assessment. Never auto-upgrade: if the blind severity came back *higher*
than the originator's, flag it as `disputed_severity` for the user rather than silently taking
the larger number.

### Phase 6 — High+ goes back to the implementer, not the MR

Don't post high+ defects on an MR when the agent that wrote the
change can just fix them. A fix is invisible; a note isn't.

**Reachable implementer** means one of:
- you wrote this change in this conversation;
- an agent you spawned wrote it and still answers `SendMessage` (if the send errors, it's
  not reachable);
- your brief says `Implementer: <name>`.

Anything else (a teammate's MR, the user's own MR built in another session, any doubt) is not
reachable. When you spawn a reviewer for work you or your subagent implemented, put the
`Implementer:` line in its brief. The reviewer can't know otherwise. For round 2 and later,
the brief also carries the previous round's handoff set (id, `file:line`, final claim, old
SHA) so the reviewer can run the re-checks. It never passes that set to its FIND arms.

**Handoff set:** Survived or Narrowed findings at `critical`/`major` (by the refuter's
`own_severity`) that this change introduced. Contested findings and pre-existing defects go
to the user instead, because fixing those means picking a side or widening the MR without their OK.

**Reachable:**
1. No high+ finding goes on the MR, not even under a posting grant. The fix replaces the note.
2. Route the handoff set:
   - You wrote the change: fix the findings yourself.
   - An agent you spawned wrote it: `SendMessage` it the handoff, and ask it to send the
     new head SHA back by `SendMessage`, with a plain-text first line.
   - You're a nested reviewer: `SendMessage` the handoff to your spawner, marked "for
     <implementer>, not posted", then stop. The spawner relays it and runs the next round.

   For each finding the handoff gives `file:line`, the final claim (the narrowed one if it
   was Narrowed), the failure scenario, what convinced the refuter, and the invariant the
   fix must restore. Give the invariant, not a patch recipe. Add the reviewed head SHA and
   the report path. The handoff grants no commit or push authority the implementer didn't
   already have.
3. If the implementer disputes a finding instead of fixing it, the finding is Contested and
   both positions go to the user.
4. Re-review the fixed head:
   - Do a full blind run of this skill on the whole MR, not a delta, with fresh arms and
     threads. Fixes open new holes. The FIND arms never see earlier rounds. Only the
     orchestrator sees them, for the re-checks.
   - Re-check each handed-off finding. Send its stripped projection to a fresh refute
     thread in each lab, prefixed: "This claim was made against an earlier commit of this
     MR (<old sha>). The worktree is at the MR's current head (<new sha>). Evaluate whether
     the claim holds at the current head." It counts as fixed only if both labs refute it.
   - Each round writes its own report (`-r<N>`).
5. Stop when a round leaves nothing for the implementer, or after 3 review rounds. If any
   high+ still stands after round 3, post nothing. Give the user the findings and a draft note.
6. When the loop ends, the user's posting or approval grant covers the final round only, and
   still never high+. Fixed findings stay in the local reports and the terminal, so the user
   sees everything. Only the MR stays clean.

**Not reachable:** no change. Report the findings, and post only on the user's explicit grant
for this MR. Otherwise give them a draft. Don't fix a change you didn't implement unless they
ask.

## Anti-patterns

- **Never run one-armed.** No Codex, no review. Abort loudly.
- **Never leak severity or rationale into a refute prompt.** That single slip converts the
  whole run from independent verification into confirmation bias.
- **Never let one lab see the other's findings during Phase 1.** Blindness is the design.
- **Never resolve a contested finding yourself.** Surface the crux instead.
- **Never drop a killed finding silently.** A wrong kill is a miss, and the user can only catch
  it if they see it.
- **Never claim full coverage after truncating.** Log exclusions in the report.
- **Never put high+ on the MR while its implementer is reachable.** Hand it back (Phase 6).
- **Do not ask the user anything mid-run.** This skill runs start to finish unattended.

## Cost

Roughly 2 + 2n agent/model calls for n findings, split across labs. A 10-finding changeset
runs ~20 calls and takes a while. If the user wants it cheaper, drop
`model_reasoning_effort` to `medium` and cross-examine only `critical` and `major`
findings — and say in the report that minors went un-refuted. A Phase 6 fix loop repeats
the run up to 3 times.
