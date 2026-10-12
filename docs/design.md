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
2. **Detect**: a hook notices when the user re-asks.
3. **Adapt**: re-explain plainly in that turn; if it keeps happening, lower the level; remember the confusing terms and avoid them later.

**Non-goals**
- No longer answers. docent **rewords; it doesn't add explanation**.
- No output style change. Rules are layered on top of whatever style the user uses.
- No effect on code, commit messages, or file contents. Conversation prose only.
- No language-, domain-, or stack-specific rules in the core.
- No required external runtimes (jq, python, node). Bash 3.2 and standard Unix tools only. jq is used when present, with a sed/awk fallback that is tested too.

## 3. Token budget

| Item | When | Cap |
|---|---|---|
| SessionStart injection (core rules + level + avoid list) | Session start, `/clear`, after compaction | ~600 tokens |
| UserPromptSubmit injection | **Only on a re-ask** | ~80 tokens |
| UserPromptSubmit injection | Every other message | **0** (prints nothing) |
| Output tokens | Normally | Unchanged (rewording only) |
| Output tokens | When re-explaining | Only the part in question, capped per level |

- Detection and recording run in bash. No LLM calls.
- Claude never writes the data files itself. Tool calls would cost output tokens and trigger permission prompts.

## 4. Flow

```
Session start ─▶ session-start.sh
                  ├ step the level back up after a quiet stretch (5.3)
                  └ print: core rules + level rules + avoid list (global + project, max 30)

User message ──▶ prompt-submit.sh
                  ├ not a re-ask → exit, print nothing
                  └ re-ask
                      ├ extract the term → record it if Claude's last reply used it
                      ├ count the re-ask → lower the level past the threshold
                      └ print: one-line re-explain instruction (+ new level rules if it changed)
```

## 5. Details

### 5.1 Detection: two layers

Because there are many languages, detection has two layers.

| Layer | Who | Languages | What it does | Cost |
|---|---|---|---|---|
| **1: Claude itself** | Claude (core rules) | All | Re-explains briefly and plainly when the user re-asks | One line in the core rules |
| **2: Hook** | `prompt-submit.sh` | Those with a signals file | Counts re-asks, records terms, adjusts the level (persistent) | 0 (bash) |

Layer 1 means the in-turn re-explanation works even without a signals file. Layer 2 handles learning and persistence, and grows as signals files are added.

**Signals files**: `signals/<lang>.txt`, one language per file so the community can add languages by PR. Lines are one of five kinds: `strong`, `weak` (with a capture-group number), `strip` (suffixes such as particles to remove from a term), `stop` (words never treated as terms), and `skip` (words of a task or bug report, such as "error" or "fix"; a prompt containing one is not a strong signal). Strong signals also need an earlier Claude reply and a prompt of at most 300 bytes. CONTRIBUTING.md has the full rules. The first release ships `en` and `ko`; `ja`, `zh`, `es`, `de`, and others can follow.

```
# signals/en.txt (excerpt)
strong	what do (you|u) mean
strong	i (don'?t|do not|didn'?t|did not) (get|understand|follow)
weak	2	what does (the |an? )?([a-z0-9_.-]+( [a-z0-9_.-]+){0,2}) mean
stop	it|this|that|next|the difference|the status
```

- Patterns from all signals files are checked together. The user's language is not detected.
- Matching is POSIX ERE under `LC_ALL=C`, against the prompt with ASCII letters lowercased.

| Signal | Handling |
|---|---|
| **Strong** | Re-explain instruction + count +1 (only in a short reply to Claude with no `skip` word) |
| **Weak** (captured X) | Treated as strong **only if X appears in Claude's last reply** |

Weak signals are separate so ordinary questions such as "what's the difference between X and Y?" don't count. Only re-asking about a word Claude just used counts as a wording problem. The last reply is read from the end of the `transcript_path` file given on stdin: the last 8 assistant **text** blocks within the last 400 lines. Commands, tool input, and tool output are ignored, so a term that only appeared in `npm run lint` doesn't count, and a long run of tool calls doesn't push the reply text out of view.

**Reading the transcript**: the transcript format is internal to Claude Code and may change, so parsing is loose. On each `"type":"assistant"` line, every `{"type":"text","text":"..."}` object is taken, wherever it sits in the content array, in either key order, with any whitespace between keys. With jq on `PATH`, jq reads `.message.content[]` text blocks instead; if jq is missing or finds nothing, the awk path runs. Strings inside tool calls have escaped quotes, so they can't look like a text block.

**Read failures**: if an assistant line that isn't just a tool call or thinking exists but no text was found, the format probably changed. The hook stays silent (it never blocks or prints an error) and writes `read_fail=<epoch>` to `state`, keeping the first failure time; the next successful read removes it. `/docent:status` shows `reply read: ok` or `reply read: failing since <date>`. While it fails, weak signals and strong signals can't fire, because both need the last reply.

**Input parsing**: without jq, `sed` extracts `"prompt":"..."` from the raw stdin JSON. Verified in a real session: non-ASCII text (e.g. Korean) arrives as raw UTF-8, not `\uXXXX` escapes.

### 5.2 Recording terms

- Extraction: the weak signal's X. With a strong signal, a short quoted phrase (`"..."` or `` `...` ``, up to 60 bytes) is also taken if Claude's last reply contains it. Example: `"drain" — what do you mean?`
- Re-asks with no clear target ("what do you mean?") only count; no term is recorded.
- Korean weak signals capture X in "X가 뭔가요/뭐예요/뭐지/뭐죠", "X는/은/이/가 무슨 뜻/말(이에요|인가요|이죠|이야 …)", and "X란?". The `strip` line removes the particle; if the stripped X is a `stop` word ("이게", "그래서", "결과가" → "결과"), no term is recorded and only the strong signal counts.
- Storage
  - Project: `~/.claude/docent/projects/<path-as-name>/avoid.txt` first, since the term may be specific to this project's domain. Nothing is written inside the user's repo, so nothing gets committed by accident.
  - Global: `~/.claude/docent/avoid.txt`. A term is promoted once it's been recorded in **two or more different projects**, tracked as `term<TAB>project-path` lines in `seen.txt`.
- Format: `term<TAB>count<TAB>last-epoch` lines. A term may appear on several lines (each record is appended); counts are summed on read and merged at session start once a file passes 200 lines. Only the terms are injected, most frequent first, up to 30.

### 5.3 Levels

| Level | Meaning | Re-explain cap |
|---|---|---|
| `normal` (default) | Average level; core rules only | 5 lines |
| `plain` | One idea per sentence; abbreviations spelled out | 5 lines |
| `plainer` | Also: conclusion first, one concrete example | 6 lines |

- **Down**: 3 strong signals within the last 20 messages lower the level one step.
- **Up**: 7 days without a signal raises it one step, at SessionStart.
- State lives in `~/.claude/docent/state` (`level=`, and `read_fail=` while replies can't be read) and `~/.claude/docent/events` (one `epoch<TAB>0|1` line per message, `epoch<TAB>R` on a level change). The window is the last 20 messages after the latest `R`; the quiet stretch is measured from the latest `1` or `R`.
- Parallel sessions (e.g. several panes in one app) write these files at the same time. Per-message writes only append one short line (`>>`), so no session loses another's record and no hook ever waits on a lock. Avoid lists are appended too (`term<TAB>1<TAB>epoch`) and summed on read. Files are rewritten only on a level change, when reply reading starts or stops failing, at session start when they grow large (compaction), and by `/docent:status`.
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
- If the user signals they didn't follow (in any language), re-explain only that part, briefly, in everyday words.
- Terms listed under "avoid" confused this user before; say what they mean instead.
Reply in the user's language.
```

**familiar (SessionStart, only when `familiar` is set)** — about 40 tokens
```
familiar: {stacks}. The user knows these well. When explaining a concept from another stack, relate it to a close equivalent in these if one exists; skip the comparison if none fits.
```
The user writes the stacks themselves; docent never guesses them from projects, since a wrong guess gives misleading comparisons.

**Re-explain instruction (UserPromptSubmit, only on a re-ask)**
```
<docent>The user may not have followed your last explanation{ of "X"}. If this message asks about it, re-explain only that part in everyday words, within {N} lines. No new concepts, no preamble. If it is a new request or a question about something else, ignore this note.</docent>
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
│   └── hooks.json             # registers SessionStart and UserPromptSubmit
├── scripts/
│   ├── session-start.sh
│   ├── prompt-submit.sh
│   ├── status.sh              # backs /docent:status
│   └── lib.sh                 # config, state, events, and avoid-list helpers
├── profiles/                  # injected text (English)
│   ├── core.md
│   └── levels/{normal,plain,plainer}.md
├── signals/                   # per-language re-ask patterns (community contributions)
│   ├── en.txt
│   └── ko.txt
├── skills/
│   └── status/SKILL.md        # /docent:status [familiar <stacks> | forget <term> | reset]
├── tests/
│   └── run.sh                 # runs the hooks against a temp data dir and a fake transcript
├── .gitattributes             # *.sh text eol=lf
├── CONTRIBUTING.md            # how to add a signals file
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
| 1 | An ordinary question | prompt-submit prints nothing |
| 2 | "what do you mean?" / "이게 무슨말인가요" | Re-explain instruction, count +1, no term recorded |
| 3 | Last reply used "drain"; user asks "what does drain mean?" | "drain" recorded in the project avoid.txt |
| 4 | "what's a monad?" when the last reply didn't use it | Nothing printed |
| 4-1 | A re-ask in a language without a signals file (e.g. Japanese "どういう意味？") | Hook prints nothing; Claude re-explains briefly via the core rules |
| 5 | 3 strong signals within 20 messages | Level goes from normal to plain |
| 6 | Same term recorded in two projects | Promoted to the global avoid.txt |
| 7 | New session after 7 quiet days | Level goes up one step |
| 8 | Same question with the plugin on and off | Answers are about the same length |
| 9 | A coding request | No effect on code or files |
| 10 | After `/compact` | Rules are injected again via SessionStart (compact) |
| 11 | A task or bug report with a signal phrase ("이 에러가 왜 나는지 이해가 안 돼요", "I'm confused why this test fails") | Nothing printed |
| 12 | A term that appeared only in a command Claude ran, not in its reply | Nothing recorded |
| 13 | Several sessions submitting at the same moment | Every message and term is recorded; no hook waits |
| 14 | A transcript whose assistant lines have no readable text block | Nothing printed; `read_fail` set; `/docent:status` shows `failing since`; cleared on the next readable reply |
| 15 | Text block with spaces between keys, not first in the array, or keys reversed | Read the same way with and without jq |
| 16 | "드레인은 무슨 뜻이에요?", "드레인이란?", "드레인이 뭐지" | "드레인" recorded; "이게 무슨 말인가요" counts with no term |

## 8. Later

- More signals languages (ja, zh, es, de, fr, pt …).
- Windows: hooks run through Git Bash, so the README notes that Git for Windows is required. Add a PowerShell version if needed.
- Stop hook: its input has `last_assistant_message`, which the hooks docs recommend over the transcript (written asynchronously). Saving it per session would avoid depending on the transcript format. Not done yet: by the time the user types the next prompt the transcript is almost always written, the transcript path is still needed when the user interrupts (Stop doesn't run), and what the field holds for a reply with several text blocks isn't documented. Revisit if `reply read: failing` shows up.
