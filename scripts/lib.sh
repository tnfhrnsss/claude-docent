#!/usr/bin/env bash
# Shared helpers for docent hooks. Bash 3.2 compatible; no jq/python/node.

export LC_ALL=C

ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DATA="${DOCENT_HOME:-$HOME/.claude/docent}"
STATE="$DATA/state"
GLOBAL_AVOID="$DATA/avoid.txt"
SEEN="$DATA/seen.txt"

LEVELS="normal plain plainer"
WINDOW=20          # recent prompts considered for stepping down
STEP_DOWN_AT=3     # signals within WINDOW that lower the level
STEP_UP_DAYS=7     # quiet days before raising the level
AVOID_MAX=30       # terms injected per session

# --- key=value files ---------------------------------------------------------

conf_get() {  # $1=file $2=key
  [ -f "$1" ] || return 0
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\([^#[:space:]]*\).*/\1/p" "$1" | tail -n 1
}

state_get() { conf_get "$STATE" "$1"; }

state_set() {  # $1=key $2=value
  mkdir -p "$DATA"
  local tmp="$STATE.$$"
  { [ -f "$STATE" ] && grep -v "^$1=" "$STATE"; echo "$1=$2"; } > "$tmp"
  mv "$tmp" "$STATE"
}

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

# Lines: term<TAB>count<TAB>last_epoch
avoid_add() {  # $1=file $2=term
  mkdir -p "$(dirname "$1")"
  local now tmp="$1.$$"
  now="$(date +%s)"
  awk -F '\t' -v t="$2" -v now="$now" 'BEGIN{OFS="\t"}
    $1==t {$2=$2+1; $3=now; found=1} {print}
    END{if(!found) print t, 1, now}' "${1}" 2>/dev/null > "$tmp" \
    || printf '%s\t1\t%s\n' "$2" "$now" > "$tmp"
  mv "$tmp" "$1"
}

# Record a term for this project; promote it to global once seen in 2+ projects.
record_term() {  # $1=term
  local proj
  proj="$(project_dir)"
  avoid_add "$(project_data)/avoid.txt" "$1"
  mkdir -p "$DATA"
  grep -qxF "$1	$proj" "$SEEN" 2>/dev/null || printf '%s\t%s\n' "$1" "$proj" >> "$SEEN"
  if [ "$(awk -F '\t' -v t="$1" '$1==t' "$SEEN" | wc -l)" -ge 2 ]; then
    avoid_add "$GLOBAL_AVOID" "$1"
  fi
}

# Top terms across global + project lists, by count, comma-separated.
avoid_list() {
  cat "$GLOBAL_AVOID" "$(project_data)/avoid.txt" 2>/dev/null \
    | awk -F '\t' 'NF>=2 {c[$1]+=$2} END{for(t in c) print c[t] "\t" t}' \
    | sort -rn | head -n "$AVOID_MAX" | cut -f2 | paste -sd, - | sed 's/,/, /g'
}

# Last WINDOW-1 entries of the 0/1 history, so appending one keeps WINDOW.
recent_tail() { printf '%s' "$(state_get recent)" | tail -c $((WINDOW - 1)); }
