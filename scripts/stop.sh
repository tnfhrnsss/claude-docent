#!/usr/bin/env bash
# Stop: when Claude re-explained because the user didn't follow, its reply ends
# with a "(docent: term)" or "(docent)" line (core rules). Record the term,
# count the re-ask, and lower the level past the threshold. Prints nothing.

. "$(dirname "$0")/lib.sh"
exec 2> /dev/null

INPUT="$(cat)"
HOOK_CWD="$(json_str "$INPUT" cwd)"

enabled || exit 0

# The marker must be the last line of last_assistant_message, so a marker
# quoted mid-reply doesn't count. The JSON is matched raw: newlines are "\n".
found="$(printf '%s' "$INPUT" | tr '\n' ' ' | sed -E -n \
  's/^.*\\n\(docent(: ([^)"\\]{1,200}))?\)(\\n|[[:space:]])*"[[:space:]]*[,}].*$/=\2/p' | head -n 1)"

if [ -z "$found" ]; then
  auto_mode && event_add 0
  exit 0
fi

# "(docent: a, b)" names up to 3 terms.
printf '%s\n' "${found#=}" | tr ',' '\n' | head -n 3 | while read -r t; do
  t="$(printf '%s' "$t" | tr -d '[:cntrl:]' | tr 'A-Z' 'a-z' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [ -n "$t" ] && [ ${#t} -le 60 ] && record_term "$t"
done

if auto_mode; then
  event_add 1
  if [ "$(recent_hits)" -ge "$STEP_DOWN_AT" ] && [ "$(current_level)" != plainer ]; then
    state_set level "$(shift_level 1)"
    event_add R
  fi
fi
exit 0
