---
name: status
description: Show docent's current level and remembered terms, set the stacks you know, forget a term, or reset everything.
argument-hint: "[familiar <stacks> | forget <term> | reset]"
disable-model-invocation: true
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh":*)
---

Run this and show its output to the user as-is, with no commentary:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh" $ARGUMENTS
```

If the argument is `reset`, confirm with the user before running it.
