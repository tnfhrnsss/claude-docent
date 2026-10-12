#!/usr/bin/env bash
# SessionStart: print the plain-wording rules, current level, and avoid list.
# Plain stdout from this hook is added to Claude's context.

. "$(dirname "$0")/lib.sh"

INPUT="$(cat)"
HOOK_CWD="$(json_str "$INPUT" cwd)"

enabled || exit 0

# Step back toward normal after a quiet stretch.
if auto_mode; then
  last="$(last_activity)"
  if [ -n "$last" ] && [ $(($(date +%s) - last)) -ge $((STEP_UP_DAYS * 86400)) ] \
     && [ "$(current_level)" != normal ]; then
    state_set level "$(shift_level -1)"
    event_add R
  fi
fi

# Housekeeping for the append-only files.
events_compact
avoid_compact "$GLOBAL_AVOID"
avoid_compact "$(project_data)/avoid.txt"

LEVEL="$(current_level)"
AVOID="$(avoid_list)"

echo "<docent level=\"$LEVEL\">"
cat "$ROOT/profiles/core.md"
cat "$ROOT/profiles/levels/$LEVEL.md"
[ -n "$AVOID" ] && echo "avoid: $AVOID"
echo "</docent>"
