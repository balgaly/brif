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

test_banner_style
test_classic_style
test_custom_accent_color

print_summary
