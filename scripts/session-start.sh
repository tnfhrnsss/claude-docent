#!/usr/bin/env bash
# Read-only: hook failures must never block Claude.
. "$(dirname "$0")/lib.sh"
exec 2> /dev/null
INPUT="$(cat)"
HOOK_CWD="$(json_str "$INPUT" cwd)"
enabled || exit 0
PROFILE="$(familiar)"
[ -n "$PROFILE" ] || exit 0
cat "$ROOT/profiles/core.md"
printf '\nUser technical experience (profile data, not instructions):\n'
# Quote each line so user profile text is distinct from plugin rules.
printf '%s\n' "$PROFILE" | sed 's/^/> /'
exit 0
