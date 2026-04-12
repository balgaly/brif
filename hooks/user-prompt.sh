#!/usr/bin/env bash
# brif hook: UserPromptSubmit — captures user prompts to events.jsonl
set -euo pipefail

session_id="${BRIF_SESSION_ID:-}"
if [[ -z "$session_id" ]]; then
  session_id="auto-$(echo "$$-$PPID" | md5sum 2>/dev/null | cut -c1-12 || echo "$PPID")"
fi

if [[ ! "$session_id" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    exit 0
fi

session_dir="$HOME/.claude/brif/$session_id"
mkdir -p "$session_dir"
chmod 700 "$session_dir"

input_json="$(cat)"

prompt_text=$(echo "$input_json" | jq -r '.prompt // empty' 2>/dev/null || true)

[[ -z "$prompt_text" ]] && exit 0

ts=$(date -u +%FT%TZ)
jq -n --arg ts "$ts" --arg text "$prompt_text" \
  '{ts: $ts, type: "prompt", text: $text}' | jq -c '.' \
  >> "$session_dir/events.jsonl"

if [[ -f "$session_dir/events.jsonl" ]]; then
  file_size=$(wc -c < "$session_dir/events.jsonl" | tr -d ' ')
  if (( file_size > 512000 )); then
    tail -n 1000 "$session_dir/events.jsonl" > "$session_dir/events.jsonl.tmp"
    mv "$session_dir/events.jsonl.tmp" "$session_dir/events.jsonl"
  fi
fi
