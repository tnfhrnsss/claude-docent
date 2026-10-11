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
- No external runtimes (jq, python, node). Bash 3.2 and standard Unix tools only.

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

**Signals files**: `signals/<lang>.txt`, one language per file so the community can add languages by PR. Lines are one of four kinds: `strong`, `weak` (with a capture-group number), `strip` (suffixes such as particles to remove from a term), and `stop` (words never treated as terms). CONTRIBUTING.md has the full rules. The first release ships `en` and `ko`; `ja`, `zh`, `es`, `de`, and others can follow.

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
| **Strong** | Re-explain instruction + count +1 |
| **Weak** (captured X) | Treated as strong **only if X appears in Claude's last reply** |

Weak signals are separate so ordinary questions such as "what's the difference between X and Y?" don't count. Only re-asking about a word Claude just used counts as a wording problem. The last reply is read from the end of the `transcript_path` file given on stdin (`tail`, then `grep -F` on assistant lines).

**Input parsing**: without jq, `sed` extracts `"prompt":"..."` from the raw stdin JSON. Verified in a real session: non-ASCII text (e.g. Korean) arrives as raw UTF-8, not `\uXXXX` escapes.

### 5.2 Recording terms

- Extraction: the weak signal's X. With a strong signal, a short quoted phrase (`"..."` or `` `...` ``, up to 60 bytes) is also taken if Claude's last reply contains it. Example: `"drain" — what do you mean?`
- Re-asks with no clear target ("what do you mean?") only count; no term is recorded.
- Storage
  - Project: `~/.claude/docent/projects/<path-as-name>/avoid.txt` first, since the term may be specific to this project's domain. Nothing is written inside the user's repo, so nothing gets committed by accident.
  - Global: `~/.claude/docent/avoid.txt`. A term is promoted once it's been recorded in **two or more different projects**, tracked as `term<TAB>project-path` lines in `seen.txt`.
- Format: one term per line, `term<TAB>count<TAB>last-epoch`. Only the terms are injected, most frequent first, up to 30.

### 5.3 Levels

| Level | Meaning | Re-explain cap |
|---|---|---|
| `normal` (default) | Average level; core rules only | 5 lines |
| `plain` | One idea per sentence; abbreviations spelled out | 5 lines |
| `plainer` | Also: conclusion first, one concrete example | 6 lines |

- **Down**: 3 strong signals within the last 20 messages lower the level one step.
- **Up**: 7 days without a signal raises it one step, at SessionStart.
- State lives in `~/.claude/docent/state`: `level=`, `recent=` (0/1 history of the last 20 messages), `last_signal=` (epoch).
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

**Re-explain instruction (UserPromptSubmit, only on a re-ask)**
```
<docent>The user did not follow your last explanation{ of "X"}. Re-explain only that part in everyday words, within {N} lines. No new concepts, no preamble.</docent>
```

### 5.5 Configuration

| Key | Where | Default | Meaning |
|---|---|---|---|
| `enabled` | `~/.claude/docent/config` or `<project>/.claude/docent/config` (project wins) | `true` | Turn docent off |
| `level` | Same files | `auto` | `auto` adjusts per 5.3; `normal` / `plain` / `plainer` pins it |

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
│   └── lib.sh                 # config, state, and avoid-list helpers
├── profiles/                  # injected text (English)
│   ├── core.md
│   └── levels/{normal,plain,plainer}.md
├── signals/                   # per-language re-ask patterns (community contributions)
│   ├── en.txt
│   └── ko.txt
├── skills/
│   └── status/SKILL.md        # /docent:status [reset | forget <term>]
├── tests/
│   └── run.sh                 # runs the hooks against a temp data dir and a fake transcript
├── .gitattributes             # *.sh text eol=lf
├── CONTRIBUTING.md            # how to add a signals file
├── LICENSE                    # MIT
└── README.md
```

- The `status` skill sets `disable-model-invocation: true`, so it runs only when the user calls it and uses no context otherwise.
- State lives in `~/.claude/docent/` rather than `${CLAUDE_PLUGIN_DATA}` for two reasons: `--plugin-dir` development and a marketplace install share the same data, and the history survives a reinstall.

## 7. Development and testing

```bash
claude plugin validate .                         # manifest and path checks
claude --plugin-dir .                            # run without installing
bash tests/run.sh                                # hook tests
/plugin marketplace add ~/Documents/claude_plugins/claude-docent
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

## 8. Later

- Stack bridging (explaining in terms of the user's own stack, e.g. Spring or Python): add as an optional feature if needed.
- More signals languages (ja, zh, es, de, fr, pt …).
- Windows: hooks run through Git Bash, so the README notes that Git for Windows is required. Add a PowerShell version if needed.
