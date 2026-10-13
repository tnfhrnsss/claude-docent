#!/usr/bin/env bash
# Runs the docent hooks against an isolated data dir.
# Usage: bash tests/run.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CLAUDE_PLUGIN_ROOT="$ROOT"
export DOCENT_HOME="$TMP/data"
export CLAUDE_PROJECT_DIR="$TMP/proj-a"
mkdir -p "$CLAUDE_PROJECT_DIR"

pass=0; fail=0
SID=t

stop() {  # $1=last_assistant_message as a JSON string body ("\n" for newlines)
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"%s","background_tasks":[]}' \
    "$SID" "$CLAUDE_PROJECT_DIR" "$1" | bash "$ROOT/scripts/stop.sh"
}

submit() {  # $1=prompt
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"%s"}' \
    "$SID" "$CLAUDE_PROJECT_DIR" "$1" | bash "$ROOT/scripts/prompt-submit.sh"
}

start() {
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' \
    "$SID" "$CLAUDE_PROJECT_DIR" | bash "$ROOT/scripts/session-start.sh"
}

check() {  # $1=name $2=condition result (0 ok)
  if [ "$2" = 0 ]; then pass=$((pass + 1)); echo "ok   $1"
  else fail=$((fail + 1)); echo "FAIL $1"; fi
}

proj_avoid() { cat "$DOCENT_HOME/projects/$(echo "$CLAUDE_PROJECT_DIR" | sed 's#[/:\\ ]#-#g')/avoid.txt" 2>/dev/null; }
level() { sed -n 's/^level=//p' "$DOCENT_HOME/state" 2>/dev/null; }
last_event() { tail -n 1 "$DOCENT_HOME/events" 2>/dev/null | cut -f2; }
events() { wc -l < "$DOCENT_HOME/events" 2>/dev/null | tr -d ' '; }

out="$(start)"
check "core rules ask for the marker line" "$(echo "$out" | grep -qF '`(docent: X)`'; echo $?)"

# Stop: the marker on the last line records the re-ask and the term.
out="$(stop "Here is the plan.\n\nWe drain the queue.")"
check "ordinary reply: silent, counted as 0" "$([ -z "$out" ] && [ "$(last_event)" = 0 ]; echo $?)"

stop "Drain means: finish what is already in the queue, take nothing new.\n\n(docent: drain)"
check "marker with term: re-ask counted" "$([ "$(last_event)" = 1 ]; echo $?)"
check "marker with term: term recorded for project" "$(proj_avoid | grep -q '^drain	'; echo $?)"

stop "In short: it is the same data.\n(docent)"
check "marker without term: counted, nothing recorded" "$([ "$(last_event)" = 1 ] && [ "$(proj_avoid | wc -l | tr -d ' ')" = 1 ]; echo $?)"

stop "큐를 비운다는 뜻입니다.\n\n(docent: 드레인)\n"
check "korean term, trailing newline" "$(proj_avoid | grep -q '^드레인	'; echo $?)"

stop "It pins one version.\n(docent: Pin the SHA, lockfile)"
check "several terms, ASCII lowercased" "$(proj_avoid | grep -q '^pin the sha	' && proj_avoid | grep -q '^lockfile	'; echo $?)"

stop "다시 설명합니다.\n(docent: 드레인)\n\n그리고 하나 더 있습니다."
check "marker not on the last line → 0" "$([ "$(last_event)" = 0 ]; echo $?)"

stop "Add a line like \`(docent: drain)\` at the end."
check "marker quoted inline → 0" "$([ "$(last_event)" = 0 ]; echo $?)"

stop "x\n\`(docent: wrapped)\`"
check "marker line in backticks: counted" "$([ "$(last_event)" != 0 ] && proj_avoid | grep -q '^wrapped	'; echo $?)"
stop "x\n**(docent: bold)**."
check "marker line in bold with a period: counted" "$([ "$(last_event)" != 0 ] && proj_avoid | grep -q '^bold	'; echo $?)"
stop "x\n(docent: useEffect())"
check "term containing ) recorded whole" "$(proj_avoid | grep -q '^useeffect()	'; echo $?)"
stop "x\n(docent: \`ticked\`, \\\"quoted\\\")"
check "backticks and quotes stripped from terms" "$(proj_avoid | grep -q '^ticked	' && proj_avoid | grep -q '^quoted	'; echo $?)"

n="$(events)"
printf '{"session_id":"t","cwd":"%s","hook_event_name":"Stop"}' "$CLAUDE_PROJECT_DIR" | bash "$ROOT/scripts/stop.sh"; rc=$?
check "no last_assistant_message: exit 0, counted as 0" "$([ $rc = 0 ] && [ "$(last_event)" = 0 ] && [ "$(events)" = $((n + 1)) ]; echo $?)"

stop "x\n(docent: $(printf 'a%.0s' $(seq 1 70)))"
check "term over 60 bytes ignored" "$(! proj_avoid | grep -q '^aaaa'; echo $?)"

# Level: the third re-ask in the window lowers it; this session hears it once.
rm -f "$DOCENT_HOME/events" "$DOCENT_HOME/state"
start > /dev/null
out="$(submit "how do I add a route?")"
check "unchanged level: prompt-submit silent" "$([ -z "$out" ]; echo $?)"
stop "a\n(docent)"; stop "b\n(docent)"
check "two re-asks keep normal" "$([ "$(level)" = "" ] || [ "$(level)" = normal ]; echo $?)"
stop "c\n(docent: drain)"
check "third re-ask steps level down to plain" "$([ "$(level)" = plain ]; echo $?)"
out="$(submit "ok")"
check "level change injected on the next prompt" "$(echo "$out" | grep -q 'level changed.*Level: plain'; echo $?)"
out="$(submit "ok")"
check "level change injected only once" "$([ -z "$out" ]; echo $?)"
stop "d\n(docent)"; stop "e\n(docent)"
check "count restarts after a level change" "$([ "$(level)" = plain ]; echo $?)"

SID=other
out="$(submit "hello")"
check "session never started: remembered, not announced" "$([ -z "$out" ] && [ "$(cat "$DOCENT_HOME/sessions/other")" = plain ]; echo $?)"
SID='../x'
out="$(submit "hello")"
check "odd session id ignored" "$([ -z "$out" ] && [ ! -e "$DOCENT_HOME/x" ]; echo $?)"
SID=t

touch -t 202001010000 "$DOCENT_HOME/sessions/other"
start > /dev/null
check "old session files removed at session start" "$([ ! -e "$DOCENT_HOME/sessions/other" ] && [ -e "$DOCENT_HOME/sessions/t" ]; echo $?)"

out="$(start)"
check "session start injects level and avoid list" "$(echo "$out" | grep -q 'avoid: .*drain' && echo "$out" | grep -q 'level="plain"'; echo $?)"

# Promotion: the same term in a second project goes global.
export CLAUDE_PROJECT_DIR="$TMP/proj-b"; mkdir -p "$CLAUDE_PROJECT_DIR"
stop "x\n(docent: drain)"
check "term in 2 projects promoted to global" "$(grep -q '^drain	' "$DOCENT_HOME/avoid.txt"; echo $?)"

out="$(bash "$ROOT/scripts/status.sh")"
check "status counts other projects' terms" "$(echo "$out" | grep -q '^other projects: [0-9]* terms\{0,1\} in 1 project$'; echo $?)"

# familiar: set by command, injected at session start, cleared by empty value.
bash "$ROOT/scripts/status.sh" familiar react, typescript > /dev/null
out="$(start)"
check "familiar stacks injected at session start" "$(echo "$out" | grep -q '^familiar: react, typescript\. '; echo $?)"
check "status shows familiar" "$(bash "$ROOT/scripts/status.sh" | grep -q '^familiar: *react, typescript$'; echo $?)"
bash "$ROOT/scripts/status.sh" familiar > /dev/null
out="$(start)"
check "empty familiar clears it" "$(! echo "$out" | grep -q '^familiar:'; echo $?)"
check "no familiar → nothing injected" "$(! echo "$out" | grep -q 'familiar'; echo $?)"

printf 'level=auto  # keep me\n' > "$DOCENT_HOME/config"
bash "$ROOT/scripts/status.sh" familiar vue > /dev/null
check "familiar keeps other config lines" "$(grep -qx 'level=auto  # keep me' "$DOCENT_HOME/config" && grep -qx 'familiar=vue' "$DOCENT_HOME/config"; echo $?)"

mkdir -p "$CLAUDE_PROJECT_DIR/.claude/docent"
printf 'familiar=spring, java  # this project\n' > "$CLAUDE_PROJECT_DIR/.claude/docent/config"
out="$(start)"
check "project familiar overrides global" "$(echo "$out" | grep -q '^familiar: spring, java\. '; echo $?)"
rm "$CLAUDE_PROJECT_DIR/.claude/docent/config" "$DOCENT_HOME/config"

# Fixed level and disable via config.
printf 'level=normal\n' > "$CLAUDE_PROJECT_DIR/.claude/docent/config"
out="$(start)"
check "config level overrides adaptive level" "$(echo "$out" | grep -q 'level="normal"'; echo $?)"
n="$(events)"
stop "x\n(docent: fixedterm)"
check "fixed level: term recorded, no event" "$(proj_avoid | grep -q '^fixedterm	' && [ "$(events)" = "$n" ]; echo $?)"

printf 'enabled=false\n' > "$CLAUDE_PROJECT_DIR/.claude/docent/config"
out="$(start; submit "hello"; stop "x\n(docent: offterm)")"
check "enabled=false prints and records nothing" "$([ -z "$out" ] && ! proj_avoid | grep -q '^offterm'; echo $?)"

# Step back up after a quiet week.
rm "$CLAUDE_PROJECT_DIR/.claude/docent/config"
printf 'level=plain\n' > "$DOCENT_HOME/state"
printf '%s\t1\n' "$(( $(date +%s) - 8 * 86400 ))" > "$DOCENT_HOME/events"
start > /dev/null
check "quiet week steps level back up" "$([ "$(level)" = normal ]; echo $?)"

# Legacy state (last_signal, no events file) still steps up.
rm -f "$DOCENT_HOME/events"
printf 'level=plain\nlast_signal=%s\n' "$(( $(date +%s) - 8 * 86400 ))" > "$DOCENT_HOME/state"
start > /dev/null
check "legacy last_signal still steps level up" "$([ "$(level)" = normal ]; echo $?)"

# Parallel sessions must not lose each other's records.
rm -f "$DOCENT_HOME/events"
for i in $(seq 1 15); do stop "reply $i" & done; wait
check "15 parallel replies all recorded" "$([ "$(events)" = 15 ]; echo $?)"

before="$(proj_avoid | awk -F '\t' '$1=="drain"{c+=$2} END{print c+0}')"
for i in $(seq 1 10); do stop "x\n(docent: drain)" & done; wait
after="$(proj_avoid | awk -F '\t' '$1=="drain"{c+=$2} END{print c+0}')"
check "10 parallel term records all kept" "$([ $((after - before)) = 10 ]; echo $?)"

# Compaction merges repeated lines without losing counts.
for i in $(seq 1 250); do printf 'lint\t1\t1\n'; done >> "$DOCENT_HOME/avoid.txt"
start > /dev/null
check "avoid list compacted, count kept" "$(grep -q '^lint	250	' "$DOCENT_HOME/avoid.txt" && [ "$(wc -l < "$DOCENT_HOME/avoid.txt" | tr -d ' ')" -le 3 ]; echo $?)"

# Hooks fail open: broken data never surfaces as an error or a non-zero exit.
printf 'level=plain\n' > "$DOCENT_HOME/state"
printf '17000x\t1\nnot a line\n' > "$DOCENT_HOME/events"
out="$(start 2> "$TMP/err")"; rc=$?
check "corrupt events: start exits 0 and still prints rules" "$([ $rc = 0 ] && echo "$out" | grep -q '<docent level=\"plain\">'; echo $?)"
check "corrupt events: no error output" "$([ ! -s "$TMP/err" ]; echo $?)"

printf 'level=plain\nlast_signal=garbage\n' > "$DOCENT_HOME/state"
rm -f "$DOCENT_HOME/events"
start > /dev/null 2> "$TMP/err"
check "corrupt last_signal: no error, level kept" "$([ ! -s "$TMP/err" ] && [ "$(level)" = plain ]; echo $?)"

if [ "$(id -u)" != 0 ]; then  # root ignores file permissions
  chmod -R a-w "$DOCENT_HOME"
  stop "x\n(docent: drain)" 2> "$TMP/err"; rc=$?
  check "read-only data dir: stop exits 0, no error output" "$([ $rc = 0 ] && [ ! -s "$TMP/err" ]; echo $?)"
  out="$(submit "hello" 2> "$TMP/err")"; rc=$?
  check "read-only data dir: submit exits 0, no error output" "$([ $rc = 0 ] && [ ! -s "$TMP/err" ]; echo $?)"
  out="$(start 2> /dev/null)"; rc=$?
  check "read-only data dir: start exits 0 and still prints rules" "$([ $rc = 0 ] && echo "$out" | grep -q '<docent level='; echo $?)"
  chmod -R u+w "$DOCENT_HOME"
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
