#!/usr/bin/env bash
# Runs the docent hooks against an isolated data dir and a fake transcript.
# Usage: bash tests/run.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CLAUDE_PLUGIN_ROOT="$ROOT"
export DOCENT_HOME="$TMP/data"
export CLAUDE_PROJECT_DIR="$TMP/proj-a"
mkdir -p "$CLAUDE_PROJECT_DIR"

TRANSCRIPT="$TMP/transcript.jsonl"
pass=0; fail=0

reply() {  # write a fake last assistant reply
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" > "$TRANSCRIPT"
}

tool_use() {  # append a fake tool call and its (large) result
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"%s"}}]}}\n' "$1" >> "$TRANSCRIPT"
  printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s"}]}}\n' "$2" >> "$TRANSCRIPT"
}

submit() {  # $1=prompt
  printf '{"session_id":"t","transcript_path":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"%s"}' \
    "$TRANSCRIPT" "$CLAUDE_PROJECT_DIR" "$1" | bash "$ROOT/scripts/prompt-submit.sh"
}

start() {
  printf '{"session_id":"t","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' \
    "$CLAUDE_PROJECT_DIR" | bash "$ROOT/scripts/session-start.sh"
}

check() {  # $1=name $2=condition result (0 ok)
  if [ "$2" = 0 ]; then pass=$((pass + 1)); echo "ok   $1"
  else fail=$((fail + 1)); echo "FAIL $1"; fi
}

proj_avoid_path() { echo "$DOCENT_HOME/projects/$(echo "$CLAUDE_PROJECT_DIR" | sed 's#[/:\\ ]#-#g')/avoid.txt"; }
proj_avoid() { cat "$(proj_avoid_path)" 2>/dev/null; }
level() { sed -n 's/^level=//p' "$DOCENT_HOME/state" 2>/dev/null; }

out="$(submit "what do you mean?")"
check "no previous reply → silent" "$([ -z "$out" ]; echo $?)"

reply "We drain the queue, then pin the SHA before the release."

out="$(submit "how do I add a route?")"
check "plain question prints nothing" "$([ -z "$out" ]; echo $?)"

out="$(submit "what do you mean?")"
check "english strong signal re-explains" "$(echo "$out" | grep -q 'may not have followed'; echo $?)"

out="$(submit "What does drain mean?")"
check "weak signal with term from reply" "$(echo "$out" | grep -q 'of \"drain\"'; echo $?)"
check "term recorded for project" "$(proj_avoid | grep -q '^drain	'; echo $?)"

out="$(submit "what's a monad?")"
check "weak signal, term not in reply → silent" "$([ -z "$out" ]; echo $?)"

out="$(submit "what's the difference?")"
check "stop word → silent" "$([ -z "$out" ]; echo $?)"

submit "sorry, I'm lost" > /dev/null
check "third signal steps level down to plain" "$([ "$(level)" = plain ]; echo $?)"
submit "what do you mean?" > /dev/null; submit "i'm lost" > /dev/null
check "count restarts after a level change" "$([ "$(level)" = plain ]; echo $?)"

reply "이 단계에서 큐를 드레인하고 다음 회차로 넘어갑니다."
out="$(submit "드레인이 뭔가요")"
check "korean weak signal strips particle" "$(echo "$out" | grep -q 'of \"드레인\"'; echo $?)"

out="$(submit "이게 무슨말인가요")"
check "korean strong signal" "$(echo "$out" | grep -q 'may not have followed'; echo $?)"

out="$(submit "쉽게 구현하는 방법 있나요")"
check "korean 'easily' without 'explain' is not a signal" "$([ -z "$out" ]; echo $?)"

for p in "이 에러가 왜 나는지 이해가 안 돼요" "README에 초보자도 쉽게 설명하는 섹션 추가해줘" \
         "빌드가 도통 안 되네" "what do you mean by that commit message, rewrite it" \
         "I'm confused why this test fails"; do
  out="$(submit "$p")"
  check "task or bug report is not a re-ask: $p" "$([ -z "$out" ]; echo $?)"
done

out="$(submit "좀 더 쉽게 설명해 주세요")"
check "korean 'explain simply' request re-explains" "$(echo "$out" | grep -q 'may not have followed'; echo $?)"

out="$(submit "$(printf 'x%.0s' $(seq 1 320)) what do you mean?")"
check "long prompt is not a re-ask" "$([ -z "$out" ]; echo $?)"

out="$(submit "\\\"다음 회차\\\" 이게 무슨 뜻이죠")"
check "quoted phrase recorded" "$(proj_avoid | grep -q '^다음 회차	'; echo $?)"

out="$(start)"
check "session start injects level and avoid list" "$(echo "$out" | grep -q 'avoid: .*drain' && echo "$out" | grep -q 'level="plainer"\|level="plain"'; echo $?)"

# Only Claude's reply text counts, not its commands or tool output.
reply "Lint passed."
tool_use "npm run eslint" "eslint: 0 problems"
out="$(submit "what is eslint?")"
check "term only in a command → silent" "$([ -z "$out" ]; echo $?)"

reply "The hook debounces saves."
for i in $(seq 1 60); do tool_use "ls" "file$i"; done
out="$(submit "what does debounce mean?")"
check "reply text found past many tool calls" "$(echo "$out" | grep -q 'debounce'; echo $?)"

# Promotion: the same term in a second project goes global.
export CLAUDE_PROJECT_DIR="$TMP/proj-b"; mkdir -p "$CLAUDE_PROJECT_DIR"
reply "We drain the queue."
submit "what does drain mean?" > /dev/null
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
mkdir -p "$CLAUDE_PROJECT_DIR/.claude/docent"
printf 'level=normal\n' > "$CLAUDE_PROJECT_DIR/.claude/docent/config"
out="$(start)"
check "config level overrides adaptive level" "$(echo "$out" | grep -q 'level="normal"'; echo $?)"

printf 'enabled=false\n' > "$CLAUDE_PROJECT_DIR/.claude/docent/config"
out="$(start; submit "what do you mean?")"
check "enabled=false prints nothing" "$([ -z "$out" ]; echo $?)"

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
for i in $(seq 1 15); do submit "how do I add a route?" > /dev/null & done; wait
check "15 parallel prompts all recorded" "$([ "$(wc -l < "$DOCENT_HOME/events" | tr -d ' ')" = 15 ]; echo $?)"

reply "We drain the queue."
before="$(proj_avoid | awk -F '\t' '$1=="drain"{c+=$2} END{print c+0}')"
for i in $(seq 1 10); do submit "what does drain mean?" > /dev/null & done; wait
after="$(proj_avoid | awk -F '\t' '$1=="drain"{c+=$2} END{print c+0}')"
check "10 parallel term records all kept" "$([ $((after - before)) = 10 ]; echo $?)"

# Compaction merges repeated lines without losing counts.
for i in $(seq 1 250); do printf 'lint\t1\t1\n'; done >> "$DOCENT_HOME/avoid.txt"
start > /dev/null
check "avoid list compacted, count kept" "$(grep -q '^lint	250	' "$DOCENT_HOME/avoid.txt" && [ "$(wc -l < "$DOCENT_HOME/avoid.txt" | tr -d ' ')" -le 3 ]; echo $?)"

# Korean term questions: each form records the term.
for p in "드레인은 무슨 뜻이에요?" "드레인이 무슨 말이에요" "드레인이 무슨 뜻인가요" "드레인 무슨 뜻이야" \
         "드레인이란?" "드레인이란" "드레인이 뭐지" "드레인이 뭐죠?"; do
  reply "이 단계에서 큐를 드레인하고 다음 회차로 넘어갑니다. 그래서 결과가 같습니다."
  rm -f "$(proj_avoid_path)"
  out="$(submit "$p")"
  check "korean term question records term: $p" "$(echo "$out" | grep -q 'of \"드레인\"' && proj_avoid | grep -q '^드레인	'; echo $?)"
done
for p in "이게 무슨 말인가요" "그래서 무슨 뜻이에요?" "결과가 무슨 말이에요"; do
  out="$(submit "$p")"
  check "korean question without a target counts, no term: $p" "$(echo "$out" | grep -q 'may not have followed' && ! echo "$out" | grep -q ' of \"'; echo $?)"
done

# Reading the reply: loose JSON, with and without jq.
mkdir -p "$TMP/nojq"
IFS=: read -ra dirs <<< "$PATH"
for d in "${dirs[@]}"; do
  for f in "$d"/*; do
    n="${f##*/}"
    [ "$n" = jq ] || [ -e "$TMP/nojq/$n" ] || ln -s "$f" "$TMP/nojq/$n" 2> /dev/null
  done
done

parse_cases() {  # $1=label
  printf '{"type": "assistant", "message": {"content": [{"type": "thinking", "thinking": "x"}, {"type": "text", "text": "We drain it."}]}}\n' > "$TRANSCRIPT"
  out="$(submit "what does drain mean?")"
  check "$1: spaced keys, text not first" "$(echo "$out" | grep -q 'of \"drain\"'; echo $?)"

  printf '{"type":"assistant","message":{"content":[{"text":"Then pin the SHA.","type":"text"}]}}\n' > "$TRANSCRIPT"
  out="$(submit "what does pin mean?")"
  check "$1: reversed key order" "$(echo "$out" | grep -q 'of \"pin\"'; echo $?)"

  reply "Lint passed."
  tool_use "npm run eslint" "eslint: 0 problems"
  printf '{"type":"user","message":{"content":[{"type":"tool_result","content":[{"type":"text","text":"eslint ok"}]}]}}\n' >> "$TRANSCRIPT"
  out="$(submit "what is eslint?")"
  check "$1: term only in a command or tool output → silent" "$([ -z "$out" ]; echo $?)"
}
if command -v jq > /dev/null; then parse_cases "with jq"; else echo "skip with jq: jq not installed"; fi
PATH="$TMP/nojq" parse_cases "without jq"
check "test PATH really hides jq" "$(! PATH="$TMP/nojq" command -v jq > /dev/null; echo $?)"

# A reply that can't be read is recorded quietly and shown in status.
read_fail() { sed -n 's/^read_fail=//p' "$DOCENT_HOME/state" 2>/dev/null; }
printf '{"type":"assistant","message":{"content":[{"kind":"words","value":"We drain it."}]}}\n' > "$TRANSCRIPT"
out="$(submit "how do I add a route?" 2> "$TMP/err")"; rc=$?
check "unreadable reply: silent, exit 0" "$([ $rc = 0 ] && [ -z "$out" ] && [ ! -s "$TMP/err" ]; echo $?)"
check "unreadable reply: read_fail recorded" "$(read_fail | grep -qE '^[0-9]+$'; echo $?)"
first="$(read_fail)"
submit "how do I add a route?" > /dev/null
check "read_fail keeps the first failure time" "$([ "$(read_fail)" = "$first" ]; echo $?)"
check "status shows reply read failing" "$(bash "$ROOT/scripts/status.sh" | grep -qE '^reply read: +failing since [0-9]{4}-[0-9]{2}-[0-9]{2} '; echo $?)"
reply "We drain the queue."
submit "how do I add a route?" > /dev/null
check "readable reply clears read_fail" "$([ -z "$(read_fail)" ]; echo $?)"
check "status shows reply read ok" "$(bash "$ROOT/scripts/status.sh" | grep -qE '^reply read: +ok$'; echo $?)"
: > "$TRANSCRIPT"; tool_use "ls" "a.txt"
submit "how do I add a route?" > /dev/null
check "tool-call-only reply is not a read failure" "$([ -z "$(read_fail)" ]; echo $?)"
reply "We drain the queue."

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
  out="$(submit "what do you mean?" 2> /dev/null)"; rc=$?
  check "read-only data dir: submit exits 0 and still re-explains" "$([ $rc = 0 ] && echo "$out" | grep -q 'may not have followed'; echo $?)"
  out="$(start 2> /dev/null)"; rc=$?
  check "read-only data dir: start exits 0 and still prints rules" "$([ $rc = 0 ] && echo "$out" | grep -q '<docent level='; echo $?)"
  chmod -R u+w "$DOCENT_HOME"
fi

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
