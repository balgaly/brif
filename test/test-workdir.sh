#!/usr/bin/env bash
# Tests for CFG_SHOW_WORKDIR / CFG_WORKDIR_STYLE / CFG_WORKDIR_MAX_LEN.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export COLUMNS=120

# Build a temp script with git/weather disabled and specific workdir config.
# Also disable mission / cost / session noise so assertions are narrow.
make_script() {
  local style="${1:-worktree}" show="${2:-true}" maxlen="${3:-40}"
  local tmp
  tmp=$(mktemp)
  sed -e 's/CFG_SHOW_WEATHER=true/CFG_SHOW_WEATHER=false/' \
      -e 's/CFG_SHOW_GIT=true/CFG_SHOW_GIT=false/' \
      -e "s/CFG_SHOW_WORKDIR=true/CFG_SHOW_WORKDIR=$show/" \
      -e "s/CFG_WORKDIR_STYLE=\"worktree\"/CFG_WORKDIR_STYLE=\"$style\"/" \
      -e "s/CFG_WORKDIR_MAX_LEN=40/CFG_WORKDIR_MAX_LEN=$maxlen/" \
      "$REPO_DIR/statusline.sh" > "$tmp"
  echo "$tmp"
}

mk_json() {
  local dir="$1"
  cat <<JSON
{
  "model": {"display_name": "Opus", "id": "claude-opus-4-6"},
  "cwd": "$dir",
  "workspace": {"current_dir": "$dir", "project_dir": "$dir"},
  "context_window": {"used_percentage": 10, "context_window_size": 200000, "current_usage": {"input_tokens": 100, "output_tokens": 10, "cache_read_input_tokens": 0}},
  "cost": {"total_cost_usd": 0, "total_duration_ms": 1000, "total_lines_added": 0, "total_lines_removed": 0},
  "session_id": "abcd1234"
}
JSON
}

test_full_style() {
  local script output
  script=$(make_script full)
  output=$(bash "$script" < <(mk_json '/home/user/projects/my-app') 2>/dev/null)
  rm -f "$script"
  assert_contains "full style shows absolute path" "$output" "/home/user/projects/my-app"
}

test_relative_style() {
  # display_dir replaces $HOME with ~
  local script output d
  d="$HOME/myproj-x"
  script=$(make_script relative)
  output=$(bash "$script" < <(mk_json "$d") 2>/dev/null)
  rm -f "$script"
  assert_contains "relative style shows ~-prefixed path" "$output" "~/myproj-x"
}

test_basename_style() {
  local script output
  script=$(make_script basename)
  output=$(bash "$script" < <(mk_json '/home/user/projects/my-app') 2>/dev/null)
  rm -f "$script"
  assert_contains "basename style shows only cwd leaf" "$output" "my-app"
  assert_not_contains "basename style hides parent dirs" "$output" "projects"
}

test_worktree_hides_when_match() {
  # Git off → location_name = cwd basename → equals workdir basename →
  # worktree style renders nothing, so no separator glyph should appear.
  local script output
  script=$(make_script worktree)
  output=$(bash "$script" < <(mk_json '/home/user/projects/my-app') 2>/dev/null)
  rm -f "$script"
  assert_not_contains "worktree hides when basename matches location_name" "$output" "▸"
}

test_worktree_shows_in_subdir_of_repo() {
  # Real repo, cwd is a SUBDIRECTORY. Git is enabled so location_name comes
  # from the repo toplevel basename, while cwd basename is the subdir name.
  # The two differ — worktree style should surface the subdir.
  local base repo sub script output
  base=$(mktemp -d)
  repo="$base/my-repo"
  mkdir -p "$repo/src/api"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t >/dev/null
  git -C "$repo" config user.name t >/dev/null
  echo x > "$repo/x"
  git -C "$repo" add x >/dev/null
  git -C "$repo" commit -qm init
  sub="$repo/src/api"

  # Build a script with git ENABLED (so location_name is "my-repo")
  script=$(mktemp)
  sed -e 's/CFG_SHOW_WEATHER=true/CFG_SHOW_WEATHER=false/' \
      -e 's/CFG_SHOW_COST=true/CFG_SHOW_COST=false/' \
      "$REPO_DIR/statusline.sh" > "$script"
  output=$(bash "$script" < <(mk_json "$sub") 2>/dev/null)
  rm -f "$script"
  rm -rf "$base"

  assert_contains "worktree style surfaces subdir when basename differs" "$output" "▸"
  assert_contains "worktree style shows the subdir leaf" "$output" "api"
}

test_disabled_shows_nothing() {
  local script output
  script=$(make_script worktree false)
  output=$(bash "$script" < <(mk_json '/home/user/projects/differs-basename') 2>/dev/null)
  rm -f "$script"
  assert_not_contains "disabled flag emits no glyph" "$output" "▸"
}

test_long_path_left_truncated() {
  local script output longpath
  script=$(make_script full 'true' 20)
  longpath='/home/user/very/deeply/nested/directory/structure/myproj-leaf'
  output=$(bash "$script" < <(mk_json "$longpath") 2>/dev/null)
  rm -f "$script"
  assert_contains "long path starts with ellipsis" "$output" "…"
  assert_contains "long path preserves tail leaf" "$output" "myproj-leaf"
  assert_not_contains "long path drops head segments" "$output" "/home/user/very/deeply/nested"
}

test_full_style
test_relative_style
test_basename_style
test_worktree_hides_when_match
test_worktree_shows_in_subdir_of_repo
test_disabled_shows_nothing
test_long_path_left_truncated

print_summary
