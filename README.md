# docent

English | [한국어](README.ko.md)

A Claude Code plugin that notices when you didn't follow an explanation — "what do you mean?", "explain it simply" — and adapts: it re-explains in plain words, remembers the terms that confused you, and keeps future answers plainer.

It doesn't make answers longer and doesn't touch code, commits, or files.

## Install

```
/plugin marketplace add tnfhrnsss/claude-docent
/plugin install docent@docent
```

Requires `bash`. On Windows, install [Git for Windows](https://git-scm.com/download/win).

### Update

Third-party marketplaces don't auto-update by default. Turn it on for `docent` in `/plugin` → Marketplaces, or update manually:

```
/plugin marketplace update docent
```

## Configure

Optional. Create `~/.claude/docent/config` (all projects) or `<project>/.claude/docent/config` (this project only; overrides global):

```
enabled=true     # false turns docent off
level=auto       # auto | normal | plain | plainer
familiar=react, typescript   # stacks you know well (optional)
```

| `level` | Behavior |
|---|---|
| `auto` (default) | Starts at `normal`, steps down when you re-ask often, steps back up after a quiet week |
| `normal` | Everyday wording, no jargon or unexplained labels |
| `plain` | Also: one idea per sentence, abbreviations spelled out |
| `plainer` | Also: conclusion first, one concrete example |

With `familiar` set, concepts from other stacks are explained by relating them to the ones you know, when a close equivalent exists. For example, a front-end developer asking about Spring dependency injection hears how it compares to React context. Leave it unset and nothing changes.

Changes apply from the next session or `/clear`.

## Commands

- `/docent:status` — show the current level and remembered terms
- `/docent:status familiar <stacks>` — set the stacks you know (e.g. `react, typescript`); with no stacks, clear it
- `/docent:status forget <term>` — stop avoiding a term
- `/docent:status reset` — clear the level and all remembered terms

## Data

Stored as plain text in `~/.claude/docent/` (nothing is written inside your projects). Delete that folder to reset.

## How it works

Claude itself judges, in any language, when you didn't follow. When it re-explains, it ends that reply with one short line naming the word that confused you:

```
(docent: drain)
```

docent reads that line when the reply finishes, remembers the word, and counts the re-ask. Claude adds the line only when re-explaining. If the word is wrong, remove it with `/docent:status forget <term>`.

## License

MIT
