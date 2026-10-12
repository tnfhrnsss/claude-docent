# Contributing

## Add a language

Re-explaining already works in every language. A signals file adds tracking for one more language: counting re-asks, remembering confusing terms, and adjusting the level.

Create `signals/<lang>.txt` (ISO 639-1 code, e.g. `ja.txt`). Lines are tab-separated:

```
strong	<regex>                 # a clear "I didn't follow" — counts in a short reply to Claude
weak	<group>	<regex>         # "what is X?" — counts only if X appeared in Claude's last reply
strip	<regex>                 # suffix removed from X before matching (e.g. particles)
stop	<word|word|...>         # X values that are never terms ("this", "the difference")
skip	<regex>                 # words of a task or bug report ("error", "fix") — strong lines then don't count
```

Rules:
- Regexes are POSIX ERE, matched byte-wise (`LC_ALL=C`) against the prompt lowercased for ASCII only. Write patterns in lowercase.
- Don't put a quantifier (`?`, `+`, `*`, `{}`) right after a non-ASCII character; wrap it in a group: `(말)?`, not `말?`.
- `strong` lines count only when Claude has already replied, the prompt is at most 300 bytes, and no `skip` line (from any language) matches.
- Prefer phrases that only mean "I didn't follow". A word like "simply" alone also appears in normal requests.
- Add cases for your language to `tests/run.sh` and run `bash tests/run.sh`.

## Docs

`README.ko.md` is a Korean translation of `README.md`. When you change one, update the other.
