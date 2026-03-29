#!/usr/bin/env bash
# brif hook: PostToolUse — captures tool events to events.jsonl
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

input_json="$(cat)"

tool_name=$(echo "$input_json" | jq -r '.tool_name // empty' 2>/dev/null || true)
file_path=$(echo "$input_json" | jq -r '.file_path // empty' 2>/dev/null || true)
lines_added=$(echo "$input_json" | jq -r '.lines_added // empty' 2>/dev/null || true)
lines_removed=$(echo "$input_json" | jq -r '.lines_removed // empty' 2>/dev/null || true)

[[ -z "$tool_name" ]] && exit 0

ts=$(date -u +%FT%TZ)
event=$(jq -n --arg ts "$ts" --arg name "$tool_name" --arg target "$file_path" \
  '{ts: $ts, type: "tool", name: $name, target: $target}')

[[ -n "$lines_added" ]] && event=$(echo "$event" | jq --argjson la "$lines_added" '. + {lines_added: $la}')
[[ -n "$lines_removed" ]] && event=$(echo "$event" | jq --argjson lr "$lines_removed" '. + {lines_removed: $lr}')

echo "$event" | jq -c '.' >> "$session_dir/events.jsonl"

if [[ -f "$session_dir/events.jsonl" ]]; then
  file_size=$(wc -c < "$session_dir/events.jsonl" | tr -d ' ')
  if (( file_size > 512000 )); then
    tail -n 1000 "$session_dir/events.jsonl" > "$session_dir/events.jsonl.tmp"
    mv "$session_dir/events.jsonl.tmp" "$session_dir/events.jsonl"
  fi
fi
