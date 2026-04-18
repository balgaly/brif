#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export COLUMNS=80

# Create temp copy with weather/git disabled and specified style/accent
make_script() {
  local style="${1:-banner}" accent="${2:-}"
  local tmp
  tmp=$(mktemp)
  sed -e 's/CFG_SHOW_WEATHER=true/CFG_SHOW_WEATHER=false/' \
      -e 's/CFG_SHOW_GIT=true/CFG_SHOW_GIT=false/' \
      -e "s/CFG_STYLE=\"banner\"/CFG_STYLE=\"$style\"/" \
      -e "s/CFG_ACCENT_COLOR=\"\"/CFG_ACCENT_COLOR=\"$accent\"/" \
      "$REPO_DIR/statusline.sh" > "$tmp"
  echo "$tmp"
}

test_banner_style() {
  local script output
  script=$(make_script banner)
  output=$(bash "$script" < "$SCRIPT_DIR/mock-data/statusline.json" 2>/dev/null)
  rm -f "$script"
  assert_contains "shows model" "$output" "Opus"
  assert_contains "has progress bar" "$output" "["
}

test_classic_style() {
  local script output
  script=$(make_script classic)
  output=$(bash "$script" < "$SCRIPT_DIR/mock-data/statusline.json" 2>/dev/null)
  rm -f "$script"
  assert_contains "shows model in classic" "$output" "Opus"
}

test_custom_accent_color() {
  local script output
  script=$(make_script banner "#ff4444")
  output=$(bash "$script" < "$SCRIPT_DIR/mock-data/statusline.json" 2>/dev/null)
  rm -f "$script"
  assert_contains "renders with custom color" "$output" "Opus"
}

test_mission_lines_render() {
  # Mission block: goal + recent should render when mission.json has summary
  local script output sid tmphome
  sid="brif-test-mission-$$"
  tmphome=$(mktemp -d)
  mkdir -p "$tmphome/.claude/brif/$sid"
  cp "$SCRIPT_DIR/mock-data/mission.json" "$tmphome/.claude/brif/$sid/mission.json"

  script=$(make_script banner)
  output=$(HOME="$tmphome" BRIF_SESSION_ID="$sid" COLUMNS=120 \
    bash "$script" < "$SCRIPT_DIR/mock-data/statusline.json" 2>/dev/null)
  rm -f "$script"
  rm -rf "$tmphome"

  assert_contains "renders goal line" "$output" "Replace session-based auth"
  assert_contains "renders recent label" "$output" "recent"
  assert_contains "renders summary text" "$output" "Refactored auth.ts"
}

test_mission_no_summary_field() {
  # If summary is absent, only the goal line should render (not recent)
  local script output sid tmphome missionfile
  sid="brif-test-nosummary-$$"
  tmphome=$(mktemp -d)
  mkdir -p "$tmphome/.claude/brif/$sid"
  missionfile="$tmphome/.claude/brif/$sid/mission.json"
  # Mission file without summary field
  cat > "$missionfile" <<'JSON'
{"version":1,"goal":"Only a goal, no summary","progress":["x"],"remaining":["y"],"status":"active"}
JSON

  script=$(make_script banner)
  output=$(HOME="$tmphome" BRIF_SESSION_ID="$sid" COLUMNS=120 \
    bash "$script" < "$SCRIPT_DIR/mock-data/statusline.json" 2>/dev/null)
  rm -f "$script"
  rm -rf "$tmphome"

  assert_contains "renders goal when summary missing" "$output" "Only a goal, no summary"
  # recent label should NOT appear without summary
  assert_not_contains "skips recent when summary absent" "$output" "recent  "
}

test_mission_recent_suppressed_narrow() {
  # At <50 cols, recent line should be suppressed; goal still renders
  local script output sid tmphome
  sid="brif-test-narrow-$$"
  tmphome=$(mktemp -d)
  mkdir -p "$tmphome/.claude/brif/$sid"
  cp "$SCRIPT_DIR/mock-data/mission.json" "$tmphome/.claude/brif/$sid/mission.json"

  script=$(make_script banner)
  output=$(HOME="$tmphome" BRIF_SESSION_ID="$sid" COLUMNS=45 \
    bash "$script" < "$SCRIPT_DIR/mock-data/statusline.json" 2>/dev/null)
  rm -f "$script"
  rm -rf "$tmphome"

  assert_not_contains "suppresses recent at 45 cols" "$output" "Refactored"
}

test_mission_truncates_long_text() {
  # At 60 cols the summary should be truncated with an ellipsis
  local script output sid tmphome
  sid="brif-test-trunc-$$"
  tmphome=$(mktemp -d)
  mkdir -p "$tmphome/.claude/brif/$sid"
  cp "$SCRIPT_DIR/mock-data/mission.json" "$tmphome/.claude/brif/$sid/mission.json"

  script=$(make_script banner)
  output=$(HOME="$tmphome" BRIF_SESSION_ID="$sid" COLUMNS=60 \
    bash "$script" < "$SCRIPT_DIR/mock-data/statusline.json" 2>/dev/null)
  rm -f "$script"
  rm -rf "$tmphome"

  assert_contains "truncates with ellipsis at 60 cols" "$output" "…"
}

test_banner_style
test_classic_style
test_custom_accent_color
test_mission_lines_render
test_mission_no_summary_field
test_mission_recent_suppressed_narrow
test_mission_truncates_long_text

print_summary
