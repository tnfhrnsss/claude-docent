#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
case "${1:-}" in
  familiar)
    shift
    # Empty explicitly overrides legacy familiar values, without deleting data.
    mkdir -p "$DATA" || exit 1
    tmp="$(mktemp "$DATA/familiar.XXXXXX")" || exit 1
    if ! printf '%s\n' "$*" > "$tmp" || ! mv "$tmp" "$DATA/familiar.txt"; then
      rm -f "$tmp"
      echo "docent: could not save experience profile." >&2
      exit 1
    fi
    if [ -n "$*" ]; then echo "docent: experience profile saved."
    else echo "docent: experience profile cleared."; fi
    echo "Applies from the next session or /clear."
    if [ -f "$(project_dir)/.claude/docent/familiar.txt" ] || [ -n "$(conf_get "$(project_dir)/.claude/docent/config" familiar)" ]; then
      echo "This project has its own profile, which takes precedence."
    fi
    ;;
  '')
    enabled && echo "docent: on" || echo "docent: off"
    profile="$(familiar)"
    printf 'Technical experience:\n%s\n' "${profile:-(not set)}"
    ;;
  *)
    echo 'Usage: /docent:status [familiar <your technical experience>]'
    exit 1 ;;
esac
