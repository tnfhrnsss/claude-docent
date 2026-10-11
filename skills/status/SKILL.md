---
name: status
description: Show docent's current level and remembered terms, forget a term, or reset everything.
argument-hint: "[reset | forget <term>]"
disable-model-invocation: true
---

Run this and show its output to the user as-is, with no commentary:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/status.sh" $ARGUMENTS
```

If the argument is `reset`, confirm with the user before running it.
