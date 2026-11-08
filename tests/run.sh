#!/usr/bin/env bash
# Integration tests with isolated data; no real user files are touched.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP"; rm -rf "$TMP"' EXIT
export CLAUDE_PLUGIN_ROOT="$ROOT" DOCENT_HOME="$TMP/data" CLAUDE_PROJECT_DIR="$TMP/project"
mkdir -p "$CLAUDE_PROJECT_DIR"
pass=0; fail=0
check() {
  if [ "$2" = 0 ]; then pass=$((pass + 1)); echo "ok   $1"
  else fail=$((fail + 1)); echo "FAIL $1"; fi
}
start() { printf '{"cwd":"%s"}' "$CLAUDE_PROJECT_DIR" | bash "$ROOT/scripts/session-start.sh"; }
status() { bash "$ROOT/scripts/status.sh" "$@"; }
out="$(start)"
check 'no profile emits nothing and creates no data' "$([ -z "$out" ] && [ ! -e "$DOCENT_HOME" ]; echo $?)"
profile='React로 실무 개발합니다. C#은 조금 써봤어요.
Python: $HOME `whoami` $(touch should-not-exist) "quotes" and '\''apostrophe'\'''
status familiar "$profile" > /dev/null
check 'natural language and shell characters preserved verbatim' "$([ "$(cat "$DOCENT_HOME/familiar.txt")" = "$profile" ] && [ ! -e should-not-exist ]; echo $?)"
out="$(start)"
check 'full multiline profile delivered to Claude' "$(printf '%s\n' "$out" | grep -qF '> React로 실무 개발합니다. C#은 조금 써봤어요.' && printf '%s\n' "$out" | grep -qF '> Python: $HOME'; echo $?)"
check 'status shows saved experience' "$(status | grep -qF 'C#은 조금'; echo $?)"
check 'rules include analogy limits' "$(printf '%s\n' "$out" | grep -qF 'important difference or limit'; echo $?)"
printf 'familiar=legacy, stack\nlevel=plainer\n' > "$DOCENT_HOME/config"
status familiar > /dev/null
check 'clear overrides legacy value' "$([ -z "$(start)" ]; echo $?)"
rm "$DOCENT_HOME/familiar.txt"
check 'legacy familiar supported' "$(start | grep -qF '> legacy, stack'; echo $?)"
printf 'old records\n' > "$DOCENT_HOME/events"
printf 'level=plainer\n' > "$DOCENT_HOME/state"
before="$(cat "$DOCENT_HOME/events" "$DOCENT_HOME/state")"
out="$(start)"
check 'old tracking data ignored and untouched' "$([ "$(cat "$DOCENT_HOME/events" "$DOCENT_HOME/state")" = "$before" ] && ! printf '%s\n' "$out" | grep -Eq 'avoid:|level=|\(docent'; echo $?)"
mkdir -p "$CLAUDE_PROJECT_DIR/.claude/docent"
printf 'familiar=spring, java # legacy project\n' > "$CLAUDE_PROJECT_DIR/.claude/docent/config"
status familiar 'React experience' > /dev/null
check 'project legacy overrides global text' "$(start | grep -qF '> spring, java'; echo $?)"
printf '프로젝트 경험: C#\n두 번째 줄\n' > "$CLAUDE_PROJECT_DIR/.claude/docent/familiar.txt"
check 'project text overrides project legacy' "$(start | grep -qF '> 프로젝트 경험: C#'; echo $?)"
out="$(status familiar 'new global')"
check 'global write warns of project override' "$(printf '%s\n' "$out" | grep -q 'takes precedence'; echo $?)"
: > "$CLAUDE_PROJECT_DIR/.claude/docent/familiar.txt"
check 'empty project profile blocks all fallback' "$([ -z "$(start)" ]; echo $?)"
rm "$CLAUDE_PROJECT_DIR/.claude/docent/familiar.txt"
printf 'enabled=false\n' > "$CLAUDE_PROJECT_DIR/.claude/docent/config"
check 'disabled emits no instructions' "$([ -z "$(start)" ]; echo $?)"
printf 'enabled=false\n' > "$DOCENT_HOME/config"
printf 'enabled=true\n' > "$CLAUDE_PROJECT_DIR/.claude/docent/config"
check 'project enabled overrides global disabled' "$(start | grep -qF '> new global'; echo $?)"
out="$(printf '{"cwd":"%s"}' "$CLAUDE_PROJECT_DIR" | CLAUDE_PROJECT_DIR= bash "$ROOT/scripts/session-start.sh")"
check 'hook cwd resolves project config' "$(printf '%s\n' "$out" | grep -qF '> new global'; echo $?)"
status forget old > /dev/null 2>&1
check 'removed command rejected' "$([ $? = 1 ]; echo $?)"
if [ "$(id -u)" != 0 ]; then
  chmod -R a-w "$DOCENT_HOME"
  out="$(start 2> "$TMP/errors")"; rc=$?
  check 'read-only data still delivers profile without errors' "$([ "$rc" = 0 ] && [ ! -s "$TMP/errors" ] && printf '%s\n' "$out" | grep -qF '> new global'; echo $?)"
  chmod -R u+w "$DOCENT_HOME"
fi
check 'no project data written by commands' "$([ ! -e "$CLAUDE_PROJECT_DIR/.claude/docent/events" ]; echo $?)"
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
