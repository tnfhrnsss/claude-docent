#!/usr/bin/env bash
# Shared helpers. Bash 3.2 compatible; no external runtime required.
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DATA="${DOCENT_HOME:-$HOME/.claude/docent}"

conf_get() {
  [ -f "$1" ] || return 0
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\([^#]*\).*/\1/p" "$1" | tail -n 1 | sed 's/[[:space:]]*$//'
}
project_dir() { echo "${CLAUDE_PROJECT_DIR:-${HOOK_CWD:-$PWD}}"; }
config_get() {
  local v
  v="$(conf_get "$(project_dir)/.claude/docent/config" "$1")"
  [ -n "$v" ] || v="$(conf_get "$DATA/config" "$1")"
  echo "${v:-$2}"
}
enabled() { [ "$(config_get enabled true)" != false ]; }

# A project profile takes precedence, including an intentionally empty file.
# Keep legacy familiar=config values working without assigning skill levels.
familiar() {
  local project
  project="$(project_dir)/.claude/docent"
  if [ -f "$project/familiar.txt" ]; then cat "$project/familiar.txt"
  elif [ -n "$(conf_get "$project/config" familiar)" ]; then conf_get "$project/config" familiar
  elif [ -f "$DATA/familiar.txt" ]; then cat "$DATA/familiar.txt"
  else conf_get "$DATA/config" familiar
  fi
}

json_str() {
  printf '%s' "$1" | tr '\n' ' ' \
    | sed -E -n 's/^.*"'"$2"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*$/\1/p' \
    | head -n 1 | sed 's/\\n/ /g; s/\\t/ /g; s/\\"/"/g; s/\\\\/\\/g'
}
