# docent design

> Like a museum docent who notices a visitor asking "sorry, what does that mean?" and adjusts how they explain from then on, docent is a Claude Code plugin that adapts Claude's wording to the person it's talking to.

## 1. Problem

Users often re-ask, with "what do you mean?" or "explain it simply", even when Claude's explanation was technically correct. Real usage history (about 80 such re-asks in the author's Claude Code sessions) shows the cause is **wording**, not technical knowledge. It happens in every language and domain.

| Pattern | Generalized example |
|---|---|
| Coined terms or literal translations nobody actually says | "drain the queue", "pin the SHA", "the round fails", "caller-less code" |
| Claude's own labels used without saying what they are | "§4 ①", "Option A", "approach 2" |
| Several ideas packed into one sentence | "is it fixed within one round?" |
| Assumptions that don't match the user's situation | Explaining in terms of `main` to a team that only uses `develop` |

Today the user has to ask for a re-explanation every time. docent handles that automatically.

**Audience**: Claude Code users worldwide, regardless of language, domain, or stack.

## 2. Goals and non-goals

**Goals**
1. **Prevent**: keep explanations at an average level, but avoid the patterns above from the start.
2. **Detect**: Claude itself judges, in any language, when the user didn't follow, and marks that reply so a hook can record it.
3. **Adapt**: re-explain plainly in that turn; if it keeps happening, lower the level; remember the confusing terms and avoid them later.

**Non-goals**
- No longer answers. docent **rewords; it doesn't add explanation**.
- No output style change. Rules are layered on top of whatever style the user uses.
- No effect on code, commit messages, or file contents. Conversation prose only.
- No language-, domain-, or stack-specific rules in the core.
- No external runtimes (jq, python, node). Bash 3.2 and standard Unix tools only.
- No extra model calls. The judgment comes from the reply Claude is already writing.

## 3. Token budget

| Item | When | Cap |
|---|---|---|
| SessionStart injection (core rules + level + avoid list) | Session start, `/clear`, after compaction | ~650 tokens |
| UserPromptSubmit injection | **Only right after the level changed** | ~40 tokens |
| UserPromptSubmit injection | Every other message | **0** (prints nothing) |
| Output tokens | Normally | Unchanged (rewording only) |
| Output tokens | When re-explaining | Only the part in question, capped per level, plus the marker line (~5 tokens) |

- Recording runs in bash. No extra LLM calls.
- Claude never writes the data files itself. Tool calls would cost output tokens and trigger permission prompts; a marker line in the reply costs a few tokens and no prompt.

## 4. Flow

```
Session start ─▶ session-start.sh
                  ├ step the level back up after a quiet stretch (5.3)
                  ├ remember which level this session was told (sessions/<id>)
                  └ print: core rules + level rules + avoid list (global + project, max 30)

User message ──▶ Claude judges: did the user not follow my last explanation?
                  └ yes → re-explain briefly, end the reply with "(docent: X)" or "(docent)"

Reply done ────▶ stop.sh (last_assistant_message)
                  ├ no marker on the last line → count 0
                  └ marker → record X, count 1, lower the level past the threshold

Next message ──▶ prompt-submit.sh
                  └ level differs from what this session was told → print the new level rules once
```

## 5. Details

### 5.1 Detection: Claude judges, the reply carries the result

Earlier versions matched the user's prompt against per-language regex files (`signals/<lang>.txt`). That missed paraphrases, misfired on task requests and pasted text, and needed a file per language. Claude already reads the message in context and, under the core rules, already decides whether to re-explain. docent now just collects that decision.

**Marker**: the core rules tell Claude that when it re-explains because the user didn't follow something it wrote, it ends the reply with one last line, `(docent: X)` (X = its own word or short phrase that confused the user, as it wrote it) or `(docent)` (no single term). It adds the line only then. The format is fixed and language-neutral, so every language works without extra files.

**Why a visible line**: tested in a real session, the Claude Code terminal shows both HTML comments (`<!-- ... -->`) and Markdown link definitions (`[//]: # (...)`) as plain text, so there is no hidden channel in the reply. A short visible line also tells the user what was remembered; a wrong term can be removed with `/docent:status forget`.

**Reading it**: the Stop hook input has `last_assistant_message`. Verified in a real session (2026-10):
- The hook input is one line of JSON; newlines in the message are `\n` escapes and non-ASCII text (e.g. Korean) is raw UTF-8.
- For a reply with several text blocks (text, tool calls, more text), the field holds **only the last text block**. The marker therefore goes at the very end.
- A change to hook settings applied to a running session without a restart.

`stop.sh` matches the raw JSON: `\n(docent[: X])` followed only by whitespace or `\n` and the closing quote. So the marker must be the last line; a marker quoted mid-reply or inline in backticks doesn't count. No jq is needed.

**Gaps**: if the user interrupts the reply, Stop doesn't run and that re-ask isn't recorded. If Claude forgets the marker, the re-ask isn't recorded either; the re-explanation itself still happens.

### 5.2 Recording terms

- Terms: up to 3 comma-separated in one marker, ASCII letters lowercased, control characters removed, at most 60 bytes each.
- `(docent)` with no term only counts.
- Storage
  - Project: `~/.claude/docent/projects/<path-as-name>/avoid.txt` first, since the term may be specific to this project's domain. Nothing is written inside the user's repo, so nothing gets committed by accident.
  - Global: `~/.claude/docent/avoid.txt`. A term is promoted once it's been recorded in **two or more different projects**, tracked as `term<TAB>project-path` lines in `seen.txt`.
- Format: `term<TAB>count<TAB>last-epoch` lines. A term may appear on several lines (each record is appended); counts are summed on read and merged at session start once a file passes 200 lines. Only the terms are injected, most frequent first, up to 30.
- Terms are recorded with a fixed `level` too; only counting is skipped.

### 5.3 Levels

| Level | Meaning | Re-explain cap |
|---|---|---|
| `normal` (default) | Average level; core rules only | 5 lines |
| `plain` | One idea per sentence; abbreviations spelled out | 5 lines |
| `plainer` | Also: conclusion first, one concrete example | 6 lines |

- **Down**: 3 marked replies within the last 20 replies lower the level one step (in `stop.sh`). The running session gets the new level rules on its next message (`prompt-submit.sh`, once per session, tracked in `~/.claude/docent/sessions/<session_id>`; files older than 7 days are removed at session start).
- **Up**: 7 days without a marked reply raises it one step, at SessionStart.
- State lives in `~/.claude/docent/state` (`level=`) and `~/.claude/docent/events` (one `epoch<TAB>0|1` line per reply, `epoch<TAB>R` on a level change). The window is the last 20 replies after the latest `R`; the quiet stretch is measured from the latest `1` or `R`.
- Parallel sessions (e.g. several panes in one app) write these files at the same time. Per-reply writes only append one short line (`>>`), so no session loses another's record and no hook ever waits on a lock. Avoid lists are appended too (`term<TAB>1<TAB>epoch`) and summed on read. Files are rewritten only on a level change, at session start when they grow large (compaction), and by `/docent:status`.
- The level is global only. It reflects the person, not the project.

### 5.4 Injected text

Injected text is **written in English**: one file works for users of any language, it costs fewer tokens, and the reply language is set by an explicit rule. No language-specific example words.

**core (SessionStart, always)** — `profiles/core.md`
```
# docent — plain wording
Applies to prose you write to the user (not code, commits, or file contents).
Do not make answers longer; only change word choice and sentence shape.
- Use words practitioners actually say. Avoid coined terms, literal translations, and internal shorthand.
- When you mention your own labels (section numbers, "Option A"), add a few words saying what they are.
- Reuse the user's own terms for things.
- If the user signals they didn't follow something you wrote (in any language), re-explain only that part in everyday words, within 5 lines. No new concepts, no preamble. Then end the reply with one last line: `(docent: X)`, where X is your word or short phrase that confused them, as you wrote it; or `(docent)` if it wasn't one term. Never add that line otherwise.
- Terms listed under "avoid" confused this user before; say what they mean instead.
Reply in the user's language.
```

**familiar (SessionStart, only when `familiar` is set)** — about 40 tokens
```
familiar: {stacks}. The user knows these well. When explaining a concept from another stack, relate it to a close equivalent in these if one exists; skip the comparison if none fits.
```
The user writes the stacks themselves; docent never guesses them from projects, since a wrong guess gives misleading comparisons.

**Level change (UserPromptSubmit, only on the first message after the level changed)**
```
<docent>The explanation level changed. From now on: {level rules}</docent>
```

### 5.5 Configuration

| Key | Where | Default | Meaning |
|---|---|---|---|
| `enabled` | `~/.claude/docent/config` or `<project>/.claude/docent/config` (project wins) | `true` | Turn docent off |
| `level` | Same files | `auto` | `auto` adjusts per 5.3; `normal` / `plain` / `plainer` pins it |
| `familiar` | Same files; also `/docent:status familiar <stacks>` (writes the global file) | unset | Stacks the user knows well, e.g. `react, typescript`; concepts from other stacks are related to these |

To turn the whole plugin off, disable it in `/plugin`. `enabled` is for turning it off in one project.

## 6. Layout

Standard Claude Code plugin layout: only the manifest goes in `.claude-plugin/`; everything else sits at the root.

```
claude-docent/                 # repo root = plugin root
├── .claude-plugin/
│   ├── plugin.json            # name: "docent" (names starting with claude- are reserved)
│   └── marketplace.json       # the repo doubles as its own marketplace
├── hooks/
│   └── hooks.json             # registers SessionStart, UserPromptSubmit, and Stop
├── scripts/
│   ├── session-start.sh
│   ├── prompt-submit.sh       # announces a level change mid-session
│   ├── stop.sh                # reads the marker, records terms and re-asks
│   ├── status.sh              # backs /docent:status
│   └── lib.sh                 # config, state, events, and avoid-list helpers
├── profiles/                  # injected text (English)
│   ├── core.md
│   └── levels/{normal,plain,plainer}.md
├── skills/
│   └── status/SKILL.md        # /docent:status [familiar <stacks> | forget <term> | reset]
├── tests/
│   └── run.sh                 # runs the hooks against a temp data dir
├── .gitattributes             # *.sh text eol=lf
├── CONTRIBUTING.md            # docs and release rules
├── LICENSE                    # MIT
├── README.md
└── README.ko.md               # Korean translation of README.md
```

- The `status` skill sets `disable-model-invocation: true`, so it runs only when the user calls it and uses no context otherwise.
- State lives in `~/.claude/docent/` rather than `${CLAUDE_PLUGIN_DATA}` for two reasons: `--plugin-dir` development and a marketplace install share the same data, and the history survives a reinstall.

## 7. Development and testing

```bash
claude plugin validate .                         # manifest and path checks
claude --plugin-dir .                            # run without installing
bash tests/run.sh                                # hook tests
/plugin marketplace add <path-to-this-repo>
/plugin install docent@docent                    # install for all projects (user scope)
```

### Scenarios

| # | Input | Expected |
|---|---|---|
| 1 | An ordinary question | No marker; Stop counts 0; prompt-submit prints nothing |
| 2 | "what do you mean?" / "이게 무슨말인가요" / "どういう意味？" | Claude re-explains and ends with `(docent)`; count +1, no term |
| 3 | Last reply used "drain"; user asks "what does drain mean?" | Reply ends with `(docent: drain)`; "drain" recorded in the project avoid.txt |
| 4 | "what's a monad?" when the last reply didn't use it | Ordinary answer, no marker |
| 5 | 3 marked replies within 20 | Level goes from normal to plain; the next message gets the plain rules once |
| 6 | Same term recorded in two projects | Promoted to the global avoid.txt |
| 7 | New session after 7 quiet days | Level goes up one step |
| 8 | Same question with the plugin on and off | Answers are about the same length |
| 9 | A coding request, or a long pasted task that quotes "무슨 뜻이에요" | No marker; nothing recorded |
| 10 | After `/compact` | Rules are injected again via SessionStart (compact) |
| 11 | A marker quoted mid-reply or inline | Not counted |
| 12 | Several sessions finishing replies at the same moment | Every reply and term is recorded; no hook waits |
| 13 | User interrupts the re-explanation | Stop doesn't run; nothing recorded |

## 8. Later

- Windows: hooks run through Git Bash, so the README notes that Git for Windows is required. Add a PowerShell version if needed.
- Measure how often Claude adds the marker when it should, and how often it adds it when it shouldn't, on real sessions.
