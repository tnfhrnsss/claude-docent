#!/usr/bin/env bash
# Shared helpers for docent hooks. Bash 3.2 compatible; no jq/python/node.
# Hooks fail open: whatever breaks, they exit 0, so Claude runs as if docent
# were not installed. Never use set -e or exit non-zero (exit 2 on
# UserPromptSubmit would block the user's prompt).

export LC_ALL=C

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DATA="${DOCENT_HOME:-$HOME/.claude/docent}"
STATE="$DATA/state"
GLOBAL_AVOID="$DATA/avoid.txt"
SEEN="$DATA/seen.txt"
EVENTS="$DATA/events"   # one line per prompt: epoch<TAB>0|1, or epoch<TAB>R on a level change

LEVELS="normal plain plainer"
WINDOW=20          # recent prompts considered for stepping down
STEP_DOWN_AT=3     # signals within WINDOW that lower the level
STEP_UP_DAYS=7     # quiet days before raising the level
AVOID_MAX=30       # terms injected per session
STRONG_MAX_BYTES=300  # longer prompts are tasks, not re-asks
REPLY_BLOCKS=8     # recent reply text blocks searched for a term

# Parallel sessions (e.g. Orca panes) write the same files at once. Hot paths
# only append one short line (>>), which can't lose another session's write;
# files are rewritten only on rare events (level change, compaction, status).

# --- key=value files ---------------------------------------------------------

conf_get() {  # $1=file $2=key — value up to a # comment, may contain spaces
  [ -f "$1" ] || return 0
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\([^#]*\).*/\1/p" "$1" | tail -n 1 \
    | sed 's/[[:space:]]*$//'
}

conf_set() {  # $1=file $2=key $3=value (empty removes the key)
  mkdir -p "$(dirname "$1")"
  local tmp="$1.$$"
  { [ -f "$1" ] && grep -v "^[[:space:]]*$2[[:space:]]*=" "$1"; [ -n "$3" ] && echo "$2=$3"; } > "$tmp"
  mv "$tmp" "$1"
}

state_get() { conf_get "$STATE" "$1"; }

state_set() { conf_set "$STATE" "$1" "$2"; }  # $1=key $2=value

# --- project ----------------------------------------------------------------

project_dir() { echo "${CLAUDE_PROJECT_DIR:-${HOOK_CWD:-$PWD}}"; }

# Per-project data lives under $DATA, never inside the user's repo.
project_data() { echo "$DATA/projects/$(project_dir | sed 's#[/:\\ ]#-#g')"; }

config_get() {  # $1=key $2=default — project config overrides global
  local v
  v="$(conf_get "$(project_dir)/.claude/docent/config" "$1")"
  [ -n "$v" ] || v="$(conf_get "$DATA/config" "$1")"
  echo "${v:-$2}"
}

# Stacks the user knows well, e.g. "react, typescript". Printable text only.
familiar() { config_get familiar "" | tr -cd '[:print:]' | cut -c1-100; }

enabled() { [ "$(config_get enabled true)" != "false" ]; }

# --- level ------------------------------------------------------------------

valid_level() { case " $LEVELS " in *" $1 "*) return 0;; esac; return 1; }

# Fixed level from config, or the adaptive level from state.
current_level() {
  local l
  l="$(config_get level auto)"
  if [ "$l" = auto ] || ! valid_level "$l"; then
    l="$(state_get level)"
    valid_level "$l" || l=normal
  fi
  echo "$l"
}

auto_mode() { [ "$(config_get level auto)" = auto ]; }

shift_level() {  # $1=+1 (plainer) or -1 (back toward normal)
  local cur i=0 idx=0 l
  cur="$(current_level)"
  for l in $LEVELS; do [ "$l" = "$cur" ] && idx=$i; i=$((i + 1)); done
  idx=$((idx + $1))
  [ $idx -lt 0 ] && idx=0
  [ $idx -gt 2 ] && idx=2
  set -- $LEVELS
  shift $idx
  echo "$1"
}

reexplain_lines() { [ "$1" = plainer ] && echo 6 || echo 5; }

# --- JSON (flat string fields only) -----------------------------------------

json_str() {  # $1=json $2=key — returns the unescaped string value
  printf '%s' "$1" | tr '\n' ' ' \
    | sed -E -n 's/^.*"'"$2"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*$/\1/p' \
    | head -n 1 \
    | sed 's/\\n/ /g; s/\\t/ /g; s/\\"/"/g; s/\\\\/\\/g'
}

# --- avoid list -------------------------------------------------------------

# Lines: term<TAB>count<TAB>last_epoch. Appended; repeated terms are summed on read.
avoid_add() {  # $1=file $2=term
  mkdir -p "$(dirname "$1")"
  printf '%s\t1\t%s\n' "$2" "$(date +%s)" >> "$1"
}

# Merge repeated lines into one per term. Run at session start, not per prompt.
avoid_compact() {  # $1=file
  [ -f "$1" ] || return 0
  [ "$(wc -l < "$1")" -gt 200 ] || return 0
  awk -F '\t' 'BEGIN{OFS="\t"} NF>=2 {c[$1]+=$2; if($3>l[$1]) l[$1]=$3}
    END{for(t in c) print t, c[t], l[t]}' "$1" > "$1.$$" && mv "$1.$$" "$1"
}

# Record a term for this project; promote it to global once seen in 2+ projects.
record_term() {  # $1=term
  local proj
  proj="$(project_dir)"
  avoid_add "$(project_data)/avoid.txt" "$1"
  mkdir -p "$DATA"
  grep -qxF "$1	$proj" "$SEEN" 2>/dev/null || printf '%s\t%s\n' "$1" "$proj" >> "$SEEN"
  if [ "$(awk -F '\t' -v t="$1" '$1==t && !p[$2]++ {n++} END{print n+0}' "$SEEN")" -ge 2 ]; then
    avoid_add "$GLOBAL_AVOID" "$1"
  fi
}

# Top terms across global + project lists, by count, comma-separated.
avoid_list() {
  cat "$GLOBAL_AVOID" "$(project_data)/avoid.txt" 2>/dev/null \
    | awk -F '\t' 'NF>=2 {c[$1]+=$2} END{for(t in c) print c[t] "\t" t}' \
    | sort -rn | head -n "$AVOID_MAX" | cut -f2 | paste -sd, - | sed 's/,/, /g'
}

# --- events -----------------------------------------------------------------

event_add() { mkdir -p "$DATA"; printf '%s\t%s\n' "$(date +%s)" "$1" >> "$EVENTS"; }

# Re-asks among the last WINDOW prompts since the last level change.
recent_hits() {
  [ -f "$EVENTS" ] || { echo 0; return; }
  tail -n $((WINDOW * 2)) "$EVENTS" | awk -F '\t' -v w="$WINDOW" '
    $2=="R" {n=0; next} {a[n++]=$2}
    END{h=0; for(i=(n>w?n-w:0); i<n; i++) if(a[i]=="1") h++; print h}'
}

# Epoch of the last re-ask or level change (legacy state key as fallback).
last_activity() {
  local e
  e="$(awk -F '\t' '$2!="0" && $1~/^[0-9]+$/ {l=$1} END{print l}' "$EVENTS" 2>/dev/null)"
  [ -n "$e" ] || e="$(state_get last_signal)"
  case "$e" in ''|*[!0-9]*) ;; *) echo "$e";; esac  # digits only, or nothing
}

events_compact() {
  [ -f "$EVENTS" ] && [ "$(wc -l < "$EVENTS")" -gt 1000 ] || return 0
  # Keep the window plus the latest non-0 line so last_activity survives.
  { awk -F '\t' '$2!="0" {l=$0} END{if(l!="") print l}' "$EVENTS"; tail -n $((WINDOW * 2)) "$EVENTS"; } \
    > "$EVENTS.$$" && mv "$EVENTS.$$" "$EVENTS"
}
