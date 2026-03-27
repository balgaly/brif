#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test: render_ambient produces 2-line output with metrics
test_render_ambient() {
  local output
  output=$(BRIF_RENDER_MODE=ambient \
    BRIF_MISSION_FILE="$SCRIPT_DIR/mock-data/mission.json" \
    BRIF_METRICS_FILE="$SCRIPT_DIR/mock-data/metrics.json" \
    BRIF_EVENTS_FILE="$SCRIPT_DIR/mock-data/events.jsonl" \
    COLUMNS=100 \
    bash "$REPO_DIR/brif-pane.sh" --render-once 2>/dev/null)

  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')

  assert_contains "shows BRIF badge" "$output" "BRIF"
  assert_contains "shows project" "$output" "api-server"
  assert_contains "shows branch" "$output" "main"
  assert_contains "shows context %" "$output" "55%"
  assert_contains "shows cost" "$output" "1.85"
  assert_contains "shows progress" "$output" "3/5"
  assert_contains "shows pending" "$output" "npm test"
  assert_exit_code "ambient is 2 lines" "$line_count" "2"
}

# Test: render_active produces expanded output with metrics
test_render_active() {
  local output
  output=$(BRIF_RENDER_MODE=active \
    BRIF_MISSION_FILE="$SCRIPT_DIR/mock-data/mission.json" \
    BRIF_METRICS_FILE="$SCRIPT_DIR/mock-data/metrics.json" \
    BRIF_EVENTS_FILE="$SCRIPT_DIR/mock-data/events.jsonl" \
    COLUMNS=100 \
    bash "$REPO_DIR/brif-pane.sh" --render-once 2>/dev/null)

  assert_contains "shows BRIF badge" "$output" "BRIF"
  assert_contains "shows context %" "$output" "55%"
  assert_contains "shows goal line" "$output" "Goal:"
  assert_contains "shows done line" "$output" "Done:"
  assert_contains "shows next line" "$output" "Next:"
  assert_contains "shows waiting" "$output" "Waiting:"
}

# Test: handles missing mission.json gracefully
test_render_no_mission() {
  local output
  output=$(BRIF_RENDER_MODE=ambient \
    BRIF_MISSION_FILE="/tmp/nonexistent-mission.json" \
    BRIF_METRICS_FILE="/tmp/nonexistent-metrics.json" \
    BRIF_EVENTS_FILE="/tmp/nonexistent-events.jsonl" \
    COLUMNS=100 \
    bash "$REPO_DIR/brif-pane.sh" --render-once 2>/dev/null)

  assert_contains "shows BRIF badge" "$output" "BRIF"
  assert_contains "shows waiting message" "$output" "waiting for session"
}

# Test: color auto-contrast — renders without crash
test_color_contrast() {
  local output
  output=$(BRIF_RENDER_MODE=ambient \
    BRIF_MISSION_FILE="$SCRIPT_DIR/mock-data/mission.json" \
    BRIF_METRICS_FILE="$SCRIPT_DIR/mock-data/metrics.json" \
    BRIF_EVENTS_FILE="$SCRIPT_DIR/mock-data/events.jsonl" \
    COLUMNS=100 \
    bash "$REPO_DIR/brif-pane.sh" --render-once 2>/dev/null)

  assert_exit_code "renders without crash" "$?" "0"
}

test_render_ambient
test_render_active
test_render_no_mission
test_color_contrast

# --- Poll loop trigger tests ---

TMPDIR_TRIGGER=$(mktemp -d)

# Test: approval auto-expand
test_approval_auto_expand() {
  local output
  output=$(BRIF_RENDER_MODE=ambient \
    BRIF_MISSION_FILE="$SCRIPT_DIR/mock-data/mission.json" \
    BRIF_METRICS_FILE="$SCRIPT_DIR/mock-data/metrics.json" \
    BRIF_EVENTS_FILE="/dev/null" \
    COLUMNS=100 \
    bash "$REPO_DIR/brif-pane.sh" --test-triggers 2>/dev/null)

  assert_contains "auto-expands for approval" "$output" "trigger:active"
}

# Test: auto-collapse after timeout (with active status)
test_auto_collapse() {
  local active_mission="$TMPDIR_TRIGGER/active-mission.json"
  jq '.status = "active" | .pending = ""' "$SCRIPT_DIR/mock-data/mission.json" > "$active_mission"

  local output
  output=$(BRIF_RENDER_MODE=active \
    BRIF_MISSION_FILE="$active_mission" \
    BRIF_METRICS_FILE="$SCRIPT_DIR/mock-data/metrics.json" \
    BRIF_EVENTS_FILE="/dev/null" \
    BRIF_TEST_ELAPSED=15 \
    COLUMNS=100 \
    bash "$REPO_DIR/brif-pane.sh" --test-triggers 2>/dev/null)

  assert_contains "collapses after timeout" "$output" "trigger:ambient"
}

# Test: inactivity detection triggers active
test_inactivity_detection() {
  local output
  output=$(BRIF_RENDER_MODE=ambient \
    BRIF_MISSION_FILE="$SCRIPT_DIR/mock-data/mission.json" \
    BRIF_METRICS_FILE="$SCRIPT_DIR/mock-data/metrics.json" \
    BRIF_EVENTS_FILE="$SCRIPT_DIR/mock-data/events.jsonl" \
    BRIF_TEST_DETECT_INACTIVITY=true \
    COLUMNS=100 \
    bash "$REPO_DIR/brif-pane.sh" --test-triggers 2>/dev/null)

  assert_contains "detects inactivity gap" "$output" "trigger:active"
}

test_approval_auto_expand
test_auto_collapse
test_inactivity_detection

rm -rf "$TMPDIR_TRIGGER"

print_summary
