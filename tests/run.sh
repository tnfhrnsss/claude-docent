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

proj_avoid() { cat "$DOCENT_HOME/projects/$(echo "$CLAUDE_PROJECT_DIR" | sed 's#[/:\\ ]#-#g')/avoid.txt" 2>/dev/null; }
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

# Promotion: the same term in a second project goes global.
export CLAUDE_PROJECT_DIR="$TMP/proj-b"; mkdir -p "$CLAUDE_PROJECT_DIR"
reply "We drain the queue."
submit "what does drain mean?" > /dev/null
check "term in 2 projects promoted to global" "$(grep -q '^drain	' "$DOCENT_HOME/avoid.txt"; echo $?)"

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
printf 'level=plain\nlast_signal=%s\n' "$(( $(date +%s) - 8 * 86400 ))" > "$DOCENT_HOME/state"
start > /dev/null
check "quiet week steps level back up" "$([ "$(level)" = normal ]; echo $?)"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
