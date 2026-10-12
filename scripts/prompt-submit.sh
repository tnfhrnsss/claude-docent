#!/usr/bin/env bash
# UserPromptSubmit: if the level changed since this session's rules were
# injected (the Stop hook lowers it), inject the new level rules once.
# Prints nothing otherwise.

. "$(dirname "$0")/lib.sh"
exec 2> /dev/null

INPUT="$(cat)"
HOOK_CWD="$(json_str "$INPUT" cwd)"

enabled || exit 0

f="$(session_file "$(json_str "$INPUT" session_id)")" || exit 0
LEVEL="$(current_level)"
[ "$(cat "$f")" = "$LEVEL" ] && exit 0

# A session docent never saw start (e.g. installed mid-session): just remember.
if [ -f "$f" ]; then
  echo "<docent>The explanation level changed. From now on: $(cat "$ROOT/profiles/levels/$LEVEL.md")</docent>"
fi
mkdir -p "$SESSIONS" && echo "$LEVEL" > "$f"
exit 0
