---
name: status
description: Show the user's technical experience profile, or save their experience in their own words for future explanations.
argument-hint: "[familiar <your technical experience>]"
disable-model-invocation: true
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh":*)
---

Use `scripts/status.sh` in the plugin root to execute this command.
- No arguments: show the current profile.
- `familiar <description>`: save the complete description verbatim. Natural language, Korean, and a simple list such as `react, typescript` are all valid. Do not ask for grades or turn experience into basic/intermediate/advanced labels.
- `familiar` with no description: clear the global profile.

Pass the description as a single safely shell-quoted argument. Never interpolate raw user text into shell code; preserve quotes, dollar signs, backticks, and newlines literally. For shell single-quoted arguments, escape each embedded single quote with the standard close-quote, escaped-quote, reopen-quote sequence.
Example:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh" familiar 'React로 프론트엔드 일을 하고 있고, Python은 조금 써봤어요.'
```
Show the script's result in the user's language. Profile updates replace the global description; do not silently drop existing experience when the user asks to add to it. Read the current profile first when needed and combine only the requested changes. Project overrides must be respected.
