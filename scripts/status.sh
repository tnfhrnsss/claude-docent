#!/usr/bin/env bash
# /docent:status — show level and remembered terms; "reset" clears them.

. "$(dirname "$0")/lib.sh"

case "$1" in
  reset)
    rm -f "$STATE" "$GLOBAL_AVOID" "$SEEN" "$(project_data)/avoid.txt"
    echo "docent: level and remembered terms reset."
    exit 0 ;;
  forget)
    shift; t="$*"
    for f in "$GLOBAL_AVOID" "$(project_data)/avoid.txt"; do
      [ -f "$f" ] && awk -F '\t' -v t="$t" '$1!=t' "$f" > "$f.$$" && mv "$f.$$" "$f"
    done
    [ -f "$SEEN" ] && awk -F '\t' -v t="$t" '$1!=t' "$SEEN" > "$SEEN.$$" && mv "$SEEN.$$" "$SEEN"
    echo "docent: forgot \"$t\"."
    exit 0 ;;
esac

enabled && on=on || on=off
echo "docent: $on, level=$(current_level) ($(config_get level auto))"
echo "recent re-asks: $(state_get recent | tr -cd 1 | wc -c | tr -d ' ')/$WINDOW"
echo "global terms:  $(cut -f1 "$GLOBAL_AVOID" 2>/dev/null | paste -sd, - | sed 's/,/, /g')"
echo "project terms: $(cut -f1 "$(project_data)/avoid.txt" 2>/dev/null | paste -sd, - | sed 's/,/, /g')"
