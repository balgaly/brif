#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# --- PostToolUse hook tests ---

test_post_tool_use_appends_event() {
  local fake_home="$TMPDIR_TEST/home1"
  mkdir -p "$fake_home/.claude/brif/session1"

  echo '{"tool_name":"Edit","file_path":"src/auth.ts"}' | \
    BRIF_SESSION_ID="session1" HOME="$fake_home" \
    bash "$REPO_DIR/hooks/post-tool-use.sh"

  local output
  output=$(cat "$fake_home/.claude/brif/session1/events.jsonl")
  assert_contains "event has type tool" "$output" '"type":"tool"'
  assert_contains "event has tool name" "$output" '"name":"Edit"'
  assert_contains "event has target" "$output" '"target":"src/auth.ts"'
}

test_post_tool_use_special_chars() {
  local fake_home="$TMPDIR_TEST/home2"
  mkdir -p "$fake_home/.claude/brif/session2"

  echo '{"tool_name":"Read","file_path":"src/file with spaces.ts"}' | \
    BRIF_SESSION_ID="session2" HOME="$fake_home" \
    bash "$REPO_DIR/hooks/post-tool-use.sh"

  local valid
  valid=$(jq '.' "$fake_home/.claude/brif/session2/events.jsonl" 2>/dev/null && echo "yes" || echo "no")
  assert_contains "produces valid JSON" "$valid" "yes"
}

test_post_tool_use_no_session_id() {
  local fake_home="$TMPDIR_TEST/home3"
  mkdir -p "$fake_home/.claude/brif"
  (echo '{"tool_name":"Read","file_path":"test.ts"}' | \
    HOME="$fake_home" \
    bash "$REPO_DIR/hooks/post-tool-use.sh" 2>/dev/null)
  local ec=$?
  assert_exit_code "no crash without session id" "$ec" "0"
}

test_post_tool_use_appends_event
test_post_tool_use_special_chars
test_post_tool_use_no_session_id

# --- UserPromptSubmit hook tests ---

test_user_prompt_appends_event() {
  local fake_home="$TMPDIR_TEST/home4"
  mkdir -p "$fake_home/.claude/brif/session4"

  echo '{"prompt":"refactor auth to use JWT"}' | \
    BRIF_SESSION_ID="session4" HOME="$fake_home" \
    bash "$REPO_DIR/hooks/user-prompt.sh"

  local output
  output=$(cat "$fake_home/.claude/brif/session4/events.jsonl")
  assert_contains "event has type prompt" "$output" '"type":"prompt"'
  assert_contains "event has text" "$output" '"text":"refactor auth to use JWT"'
}

test_user_prompt_appends_event

print_summary
