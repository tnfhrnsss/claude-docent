#!/usr/bin/env bash
# /docent:status — show level and remembered terms; "reset" clears them.

. "$(dirname "$0")/lib.sh"

case "$1" in
  reset)
    rm -f "$STATE" "$EVENTS" "$GLOBAL_AVOID" "$SEEN" "$(project_data)/avoid.txt"
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
echo "recent re-asks: $(recent_hits)/$WINDOW"
echo "global terms:  $(cut -f1 "$GLOBAL_AVOID" 2>/dev/null | sort -u | paste -sd, - | sed 's/,/, /g')"
echo "project terms: $(cut -f1 "$(project_data)/avoid.txt" 2>/dev/null | sort -u | paste -sd, - | sed 's/,/, /g')"

# Other projects' terms are listed there; here, only how many there are.
others=""
for f in "$DATA"/projects/*/avoid.txt; do
  [ -s "$f" ] && [ "$f" != "$(project_data)/avoid.txt" ] && others="$others$f
"
done
if [ -n "$others" ]; then
  np="$(printf '%s' "$others" | grep -c .)"
  nt="$(printf '%s' "$others" | while read -r f; do cut -f1 "$f"; done | sort -u | grep -c .)"
  [ "$nt" = 1 ] && tw=term || tw=terms
  [ "$np" = 1 ] && pw=project || pw=projects
  echo "other projects: $nt $tw in $np $pw"
fi
