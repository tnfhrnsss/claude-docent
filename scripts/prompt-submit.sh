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
# Each content block is its own transcript line; keep only text blocks, so terms
# from commands and tool output don't count and tool calls don't crowd them out.
LAST_REPLY=""
if [ -f "$TRANSCRIPT" ]; then
  LAST_REPLY="$(tail -n 400 "$TRANSCRIPT" | grep '"type":"assistant"' \
    | sed -E -n 's/^.*"content":\[\{"type":"text","text":"(([^"\\]|\\.)*)".*$/\1/p' \
    | tail -n "$REPLY_BLOCKS")"
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
