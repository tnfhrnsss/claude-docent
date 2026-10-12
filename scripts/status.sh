#!/usr/bin/env bash
# /docent:status — show level and remembered terms; "reset" clears them,
# "familiar <stacks>" sets the stacks the user knows (empty clears).

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
  familiar)
    shift
    conf_set "$DATA/config" familiar "$(printf '%s' "$*" | tr -cd '[:print:]' | cut -c1-100)"
    if [ -n "$*" ]; then echo "docent: familiar set to \"$(familiar)\". Applies from the next session or /clear."
    else echo "docent: familiar cleared. Applies from the next session or /clear."; fi
    exit 0 ;;
esac

enabled && on=on || on=off
echo "docent: $on, level=$(current_level) ($(config_get level auto))"
f="$(familiar)"; echo "familiar:      ${f:-(not set)}"
echo "recent re-asks: $(recent_hits)/$WINDOW"
rf="$(state_get read_fail)"
case "$rf" in
  ''|*[!0-9]*) echo "reply read:    ok" ;;
  *) echo "reply read:    failing since $(date -r "$rf" '+%Y-%m-%d %H:%M' 2> /dev/null || date -d "@$rf" '+%Y-%m-%d %H:%M')" ;;
esac
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
