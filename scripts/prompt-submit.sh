#!/usr/bin/env bash
# UserPromptSubmit: detect a re-ask ("what do you mean?"), record the confusing
# term, adjust the level, and tell Claude to re-explain. Prints nothing otherwise.

. "$(dirname "$0")/lib.sh"

INPUT="$(cat)"
HOOK_CWD="$(json_str "$INPUT" cwd)"

enabled || exit 0

PROMPT="$(json_str "$INPUT" prompt | tr 'A-Z' 'a-z')"
TRANSCRIPT="$(json_str "$INPUT" transcript_path)"
[ -n "$PROMPT" ] || exit 0

# Text of Claude's most recent replies, for checking that a term came from Claude.
# Keep only text blocks, so terms from commands and tool output don't count and
# tool calls don't crowd them out. One block per output line.
S='[[:space:]]*'
ASSISTANT="\"type\"$S:$S\"assistant\""

reply_text_jq() {
  jq -R -r 'fromjson? | objects | select(.type == "assistant") | .message.content?
    | arrays | .[] | objects | select(.type == "text") | .text | strings
    | gsub("\n"; " ")' 2> /dev/null
}

# Without jq: every {"type":"text","text":"..."} object on the line, in either
# key order. Strings inside tool calls have escaped quotes, so they never match.
reply_text_awk() {
  awk -v a="$ASSISTANT" -v s="$S" '
    $0 ~ a {
      str = "\"([^\"\\\\]|\\\\.)*\""
      ty = "\"type\"" s ":" s "\"text\""
      tx = "\"text\"" s ":" s
      re[1] = ty s "," s tx str; re[2] = tx str s "," s ty
      for (i = 1; i <= 2; i++) {
        line = $0
        while (match(line, re[i])) {
          m = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
          if (i == 1) { sub("^" ty s "," s tx "\"", "", m); sub("\"$", "", m) }
          else { sub("^" tx "\"", "", m); sub("\"" s "," s ty "$", "", m) }
          print m
        }
      }
    }'
}

LAST_REPLY=""
if [ -f "$TRANSCRIPT" ]; then
  RECENT="$(tail -n 400 "$TRANSCRIPT" 2> /dev/null)"
  command -v jq > /dev/null 2>&1 && LAST_REPLY="$(printf '%s\n' "$RECENT" | reply_text_jq)"
  [ -n "$LAST_REPLY" ] || LAST_REPLY="$(printf '%s\n' "$RECENT" | reply_text_awk 2> /dev/null)"
  LAST_REPLY="$(printf '%s' "$LAST_REPLY" | tail -n "$REPLY_BLOCKS")"

  # Claude replied (a line that is not just a tool call or thinking) but no text
  # was found: the transcript format probably changed. /docent:status shows it.
  replied="$(printf '%s\n' "$RECENT" | grep -E -- "$ASSISTANT" \
    | grep -vE -- "\"type\"$S:$S\"(tool_use|thinking|redacted_thinking)\"" | head -n 1)"
  if [ -n "$LAST_REPLY" ]; then
    [ -n "$(state_get read_fail)" ] && state_set read_fail "" 2> /dev/null
  elif [ -n "$replied" ] && [ -z "$(state_get read_fail)" ]; then
    state_set read_fail "$(date +%s)" 2> /dev/null
  fi
fi

in_reply() {  # $1=term
  [ -n "$1" ] && [ -n "$LAST_REPLY" ] && printf '%s' "$LAST_REPLY" | grep -qiF -- "$1"
}

# At least 2 characters: 2 bytes if ASCII, else 4 (any 2 multibyte chars).
long_enough() {
  case "$1" in *[!\ -~]*) [ ${#1} -ge 4 ];; *) [ ${#1} -ge 2 ];; esac
}

# Pick the variant of a captured term that Claude actually used.
resolve_term() {  # $1=raw term $2=strip regex $3=stop regex
  local raw stripped t
  raw="$(printf '%s' "$1" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  stripped="$raw"
  [ -n "$2" ] && stripped="$(printf '%s' "$raw" | sed -E "s/$2//")"
  # A stop word with a particle ("결과가") is still a stop word.
  [ -n "$3" ] && printf '%s' "$stripped" | grep -qxE -- "$3" && return
  for t in "$stripped" "$raw"; do
    long_enough "$t" || continue
    [ -n "$3" ] && printf '%s' "$t" | grep -qxE -- "$3" && continue
    in_reply "$t" && { echo "$t"; return; }
  done
}

# Strong signals count only as a short reply to an existing Claude answer, and
# not when the prompt reads like a task or a bug report ("skip" lines).
strong_ok=1
[ -n "$LAST_REPLY" ] || strong_ok=0
[ ${#PROMPT} -le "$STRONG_MAX_BYTES" ] || strong_ok=0
skip="$(cat "$ROOT"/signals/*.txt | awk -F '\t' '$1=="skip"{print $2}' | paste -sd'|' -)"
[ -n "$skip" ] && printf '%s' "$PROMPT" | grep -qE -- "$skip" && strong_ok=0

signal=0
term=""

for f in "$ROOT"/signals/*.txt; do
  strip="$(awk -F '\t' '$1=="strip"{print $2}' "$f" | paste -sd'|' -)"
  stop="$(awk -F '\t' '$1=="stop"{print $2}' "$f" | paste -sd'|' -)"
  [ -n "$stop" ] && stop="($stop)"

  while IFS="$(printf '\t')" read -r kind a b; do
    case "$kind" in
      strong)
        [ "$strong_ok" = 1 ] && printf '%s' "$PROMPT" | grep -qE -- "$a" && signal=1 ;;
      weak)
        [ -n "$term" ] && continue
        raw="$(printf '%s' "$PROMPT" | sed -E -n "s/^.*$b.*\$/\\$a/p")"
        [ -n "$raw" ] && term="$(resolve_term "$raw" "$strip" "$stop")"
        [ -n "$term" ] && signal=1 ;;
    esac
  done < <(grep -v '^#' "$f")
done

[ "$signal" = 1 ] || {
  auto_mode && event_add 0
  exit 0
}

# A quoted phrase alongside a strong signal: "drain" — what do you mean?
if [ -z "$term" ]; then
  quoted="$(printf '%s' "$PROMPT" | grep -oE '"[^"]{2,60}"|`[^`]{2,60}`' | head -n 1 | sed 's/^.//; s/.$//')"
  [ -n "$quoted" ] && in_reply "$quoted" && term="$quoted"
fi

[ -n "$term" ] && record_term "$term"

LEVEL="$(current_level)"
note=""
if auto_mode; then
  event_add 1
  if [ "$(recent_hits)" -ge "$STEP_DOWN_AT" ] && [ "$LEVEL" != plainer ]; then
    LEVEL="$(shift_level 1)"
    state_set level "$LEVEL"
    event_add R
    note=" $(cat "$ROOT/profiles/levels/$LEVEL.md")"
  fi
fi

about=""
[ -n "$term" ] && about=" of \"$term\""
echo "<docent>The user may not have followed your last explanation$about. If this message asks about it, re-explain only that part in everyday words, within $(reexplain_lines "$LEVEL") lines. No new concepts, no preamble. If it is a new request or a question about something else, ignore this note.$note</docent>"
