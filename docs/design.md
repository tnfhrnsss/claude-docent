# docent design

## Purpose

Explain new technical concepts using the user's own experience as the starting point. Natural-language experience is retained verbatim, without numeric or named proficiency grades.

## Flow

1. `/docent:status familiar <description>` atomically replaces the global `familiar.txt`. No description creates an empty override rather than falling back to old configuration.
2. SessionStart reads the effective profile and emits `profiles/core.md` followed by quoted profile data. No profile or `enabled=false` emits nothing. The hook only reads files and exits successfully even on read errors.
3. Claude chooses useful correspondences, identifies important differences, and focuses on new material. Current user instructions take precedence; profile text is background data, not instructions.

The status skill passes descriptions as safely quoted literal arguments. It does not assign proficiency labels. Additive requests require reading the current profile before combining descriptions.

## Precedence

Project `familiar.txt` (including empty), project config `familiar`, global `familiar.txt` (including empty), global config `familiar`. Project paths use CLAUDE_PROJECT_DIR, hook cwd, then working directory. Config settings use project values ahead of global values.

Natural-language profiles are UTF-8 text files, preserving newlines and characters such as #. Legacy key=value configuration retains its existing # comment behavior. Command writes use mktemp and rename in the data directory. Concurrent replacements are last-writer-wins.

## Boundaries and migration

Only explanations are affected, not generated code, commits, or file contents. No forced analogies or assumed beginner status. No Stop or UserPromptSubmit hooks, tracked re-questions, avoided terms, adaptive levels, or automatic proficiency inference. Historical data is neither read nor deleted. Existing familiar configuration remains usable. Profile updates take effect at the next session start or /clear.

## Validation

Run `bash tests/run.sh`. Tests use isolated data and project directories to verify persistence, Unicode and literal shell characters, override precedence, disabled and missing profiles, legacy compatibility, and read-only hook operation. These checks validate instruction delivery; live model explanation quality requires a Claude Code trial.
