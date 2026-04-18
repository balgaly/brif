#!/usr/bin/env bash
# brif — Configurable statusline for Claude Code
# https://github.com/balgaly/brif
#
# Installation:
#   1. Copy this file to ~/.claude/statusline.sh
#   2. chmod +x ~/.claude/statusline.sh
#   3. Add to ~/.claude/settings.json:
#      { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }
#
# Requires: jq (https://jqlang.github.io/jq/)
# Configure the options below to customize your statusline.

# ===== CONFIGURATION =====
CFG_SHOW_GIT=true
CFG_SHOW_WEATHER=false
CFG_SHOW_TOKENS=true
CFG_SHOW_COST=true
CFG_SHOW_LINES=true
CFG_SHOW_SESSION=true
CFG_WEATHER_UNIT="C"        # "C" for Celsius, "F" for Fahrenheit
CFG_CACHE_GIT_SEC=5
CFG_CACHE_WEATHER_SEC=1800  # 30 minutes
CFG_PREFIX=" .  "
CFG_SEPARATOR="  |  "
CFG_BAR_WIDTH=15
CFG_ACCENT_COLOR=""        # Hex color for accent line. Empty = rainbow gradient.
CFG_STYLE="banner"         # "banner" (v2) or "classic" (v1 look)
# =========================

# ---------------------------------------------------------------------------
# ANSI color codes
# ---------------------------------------------------------------------------
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_CYAN=$'\033[36m'
C_MAGENTA=$'\033[35m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_DIM=$'\033[2m'

# ---------------------------------------------------------------------------
# Read JSON from stdin
# ---------------------------------------------------------------------------
JSON_DATA="$(cat)"

# Helper: extract a value from the JSON, with a fallback default
jval() {
  local path="$1"
  local fallback="${2:-}"
  local val
  val="$(printf '%s' "$JSON_DATA" | jq -r "$path // empty" 2>/dev/null)"
  if [[ -z "$val" || "$val" == "null" ]]; then
    printf '%s' "$fallback"
  else
    printf '%s' "$val"
  fi
}

# Helper: extract a numeric value from the JSON, with a fallback default
jnum() {
  local path="$1"
  local fallback="${2:-0}"
  local val
  val="$(printf '%s' "$JSON_DATA" | jq -r "$path // 0" 2>/dev/null)"
  if [[ -z "$val" || "$val" == "null" ]]; then
    printf '%s' "$fallback"
  else
    printf '%s' "$val"
  fi
}

# ---------------------------------------------------------------------------
# Utility: format token counts as K when >= 1000
# ---------------------------------------------------------------------------
fmt_tokens() {
  local n="$1"
  if [[ -z "$n" || "$n" == "null" ]]; then
    printf '0'
    return
  fi
  if (( n >= 1000 )); then
    # Integer division for one decimal place
    local whole=$(( n / 1000 ))
    local frac=$(( (n % 1000) / 100 ))
    if (( frac == 0 )); then
      printf '%dK' "$whole"
    else
      printf '%d.%dK' "$whole" "$frac"
    fi
  else
    printf '%d' "$n"
  fi
}

# ---------------------------------------------------------------------------
# Utility: format context window size (typically large numbers)
# ---------------------------------------------------------------------------
fmt_window() {
  local n="$1"
  if (( n >= 1000000 )); then
    local whole=$(( n / 1000000 ))
    local frac=$(( (n % 1000000) / 100000 ))
    if (( frac == 0 )); then
      printf '%dM' "$whole"
    else
      printf '%d.%dM' "$whole" "$frac"
    fi
  elif (( n >= 1000 )); then
    local whole=$(( n / 1000 ))
    local frac=$(( (n % 1000) / 100 ))
    if (( frac == 0 )); then
      printf '%dK' "$whole"
    else
      printf '%d.%dK' "$whole" "$frac"
    fi
  else
    printf '%d' "$n"
  fi
}

# ---------------------------------------------------------------------------
# Utility: format duration from milliseconds to "Xm Ys"
# ---------------------------------------------------------------------------
fmt_duration() {
  local ms="$1"
  if [[ -z "$ms" || "$ms" == "0" ]]; then
    printf '0s'
    return
  fi
  local total_sec=$(( ms / 1000 ))
  local mins=$(( total_sec / 60 ))
  local secs=$(( total_sec % 60 ))
  if (( mins > 0 )); then
    printf '%dm %ds' "$mins" "$secs"
  else
    printf '%ds' "$secs"
  fi
}

# ---------------------------------------------------------------------------
# Git info (cached per-directory)
# ---------------------------------------------------------------------------
# Cache is keyed by a hash of the working directory so switching projects
# invalidates the cache instead of returning stale repo/branch info.
GIT_CACHE_DIR="${TMPDIR:-/tmp}/brif-git-cache-$(id -u)"
mkdir -p "$GIT_CACHE_DIR" 2>/dev/null

get_git_info() {
  local work_dir="$1"
  [[ -z "$work_dir" ]] && return

  # Per-directory cache key (MD5 of absolute path)
  local dir_key
  if command -v md5sum >/dev/null 2>&1; then
    dir_key="$(printf '%s' "$work_dir" | md5sum | cut -c1-12)"
  elif command -v md5 >/dev/null 2>&1; then
    dir_key="$(printf '%s' "$work_dir" | md5 | cut -c1-12)"
  else
    # Fallback: sanitize path to filename-safe chars
    dir_key="$(printf '%s' "$work_dir" | tr -c 'a-zA-Z0-9' '_')"
  fi
  local cache_file="$GIT_CACHE_DIR/$dir_key"

  # Check cache freshness
  if [[ -f "$cache_file" ]]; then
    local cache_age=0
    if [[ "$(uname)" == "Darwin" ]]; then
      local cache_mtime
      cache_mtime="$(stat -f '%m' "$cache_file" 2>/dev/null || echo 0)"
      cache_age=$(( $(date +%s) - cache_mtime ))
    else
      local cache_mtime
      cache_mtime="$(stat -c '%Y' "$cache_file" 2>/dev/null || echo 0)"
      cache_age=$(( $(date +%s) - cache_mtime ))
    fi
    if (( cache_age < CFG_CACHE_GIT_SEC )); then
      cat "$cache_file"
      return
    fi
  fi

  # Gather git data. First: is this a git repo at all?
  # rev-parse --git-dir is the authoritative check — works in detached HEAD too.
  if ! git -C "$work_dir" rev-parse --git-dir >/dev/null 2>&1; then
    printf '' > "$cache_file"
    return
  fi

  local branch staged modified untracked
  local repo_root repo_name
  repo_root="$(git -C "$work_dir" rev-parse --show-toplevel 2>/dev/null)"
  repo_name="$(basename "$repo_root" 2>/dev/null)"
  branch="$(git -C "$work_dir" branch --show-current 2>/dev/null)"
  if [[ -z "$branch" ]]; then
    # Detached HEAD: fall back to short commit SHA
    branch="$(git -C "$work_dir" rev-parse --short HEAD 2>/dev/null)"
    [[ -n "$branch" ]] && branch="($branch)"
  fi

  staged="$(git -C "$work_dir" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')"
  modified="$(git -C "$work_dir" diff --numstat 2>/dev/null | wc -l | tr -d ' ')"
  untracked="$(git -C "$work_dir" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')"

  local result="${repo_name}|${branch}|${staged}|${modified}|${untracked}"
  printf '%s' "$result" > "$cache_file"
  printf '%s' "$result"
}

# ---------------------------------------------------------------------------
# Weather info (cached)
# ---------------------------------------------------------------------------
WEATHER_CACHE="${TMPDIR:-/tmp}/brif-weather-cache-$(id -u)"

get_weather_info() {
  # Check cache freshness
  if [[ -f "$WEATHER_CACHE" ]]; then
    local cache_age=0
    if [[ "$(uname)" == "Darwin" ]]; then
      local cache_mtime
      cache_mtime="$(stat -f '%m' "$WEATHER_CACHE" 2>/dev/null || echo 0)"
      cache_age=$(( $(date +%s) - cache_mtime ))
    else
      local cache_mtime
      cache_mtime="$(stat -c '%Y' "$WEATHER_CACHE" 2>/dev/null || echo 0)"
      cache_age=$(( $(date +%s) - cache_mtime ))
    fi
    if (( cache_age < CFG_CACHE_WEATHER_SEC )); then
      cat "$WEATHER_CACHE"
      return
    fi
  fi

  # Fetch country code from ip-api.com
  local country
  country="$(curl -s --max-time 3 'https://ip-api.com/json/?fields=countryCode' 2>/dev/null | jq -r '.countryCode // ""' 2>/dev/null)"
  [[ -z "$country" || "$country" == "null" ]] && country="??"

  # Fetch weather from wttr.in
  local wttr_url temp_raw
  if [[ "$CFG_WEATHER_UNIT" == "F" ]]; then
    wttr_url='https://wttr.in/?format=%c|%t&u'
  else
    wttr_url='https://wttr.in/?format=%c|%t&m'
  fi
  local weather_raw
  weather_raw="$(curl -s --max-time 5 "$wttr_url" 2>/dev/null)"

  local condition temp
  if [[ -n "$weather_raw" && "$weather_raw" != *"Unknown"* && "$weather_raw" == *"|"* ]]; then
    condition="$(printf '%s' "$weather_raw" | cut -d'|' -f1 | xargs)"
    temp="$(printf '%s' "$weather_raw" | cut -d'|' -f2 | xargs)"
  else
    condition=""
    temp="?"
  fi

  local result="${country}|${condition}|${temp}"
  printf '%s' "$result" > "$WEATHER_CACHE"
  printf '%s' "$result"
}

# ---------------------------------------------------------------------------
# Extract fields from JSON
# ---------------------------------------------------------------------------
model_name="$(jval '.model.display_name' '')"
model_id="$(jval '.model.id' '')"
display_model="${model_name:-$model_id}"

work_dir="$(jval '.workspace.current_dir' '')"
project_dir="$(jval '.workspace.project_dir' '')"
cwd="$(jval '.cwd' '')"
display_dir="${work_dir:-${project_dir:-$cwd}}"

# Shorten home directory to ~
if [[ -n "$display_dir" ]]; then
  display_dir="${display_dir/#$HOME/\~}"
fi

session_id="$(jval '.session_id' '')"
short_session=""
if [[ -n "$session_id" ]]; then
  short_session="${session_id:0:8}"
fi

agent_name="$(jval '.agent.name' '')"
worktree_name="$(jval '.worktree.name' '')"
vim_mode="$(jval '.vim.mode' '')"

used_pct="$(jnum '.context_window.used_percentage' '0')"
# Round to integer for display
used_pct_int="$(printf '%.0f' "$used_pct" 2>/dev/null || echo 0)"
window_size="$(jnum '.context_window.context_window_size' '0')"

input_tokens="$(jnum '.context_window.current_usage.input_tokens' '0')"
output_tokens="$(jnum '.context_window.current_usage.output_tokens' '0')"
cache_tokens="$(jnum '.context_window.current_usage.cache_read_input_tokens' '0')"

total_cost="$(jnum '.cost.total_cost_usd' '0')"
total_duration="$(jnum '.cost.total_duration_ms' '0')"
lines_added="$(jnum '.cost.total_lines_added' '0')"
lines_removed="$(jnum '.cost.total_lines_removed' '0')"

# ---------------------------------------------------------------------------
# ACCENT LINE (Banner B style)
# ---------------------------------------------------------------------------
if [[ "${CFG_STYLE:-banner}" == "banner" ]]; then
  term_width="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"

  if [[ -n "${CFG_ACCENT_COLOR:-}" ]]; then
    # Solid color accent
    hex="${CFG_ACCENT_COLOR#\#}"
    r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
    accent_line=""
    for (( i=0; i<term_width; i++ )); do
      accent_line+="━"
    done
    printf '\033[38;2;%d;%d;%dm%s\033[0m\n' "$r" "$g" "$b" "$accent_line"
  else
    # Gradient accent: indigo -> magenta -> cyan
    # Define color stops
    r1=99  g1=102 b1=241  # #6366f1 (indigo)
    r2=255 g2=68  b2=204  # #ff44cc (magenta)
    r3=0   g3=212 b3=255  # #00d4ff (cyan)

    accent_line=""
    half=$((term_width / 2))
    for (( i=0; i<term_width; i++ )); do
      if (( i < half )); then
        frac_r=$(( r1 + (r2 - r1) * i / half ))
        frac_g=$(( g1 + (g2 - g1) * i / half ))
        frac_b=$(( b1 + (b2 - b1) * i / half ))
      else
        j=$((i - half))
        half2=$((term_width - half))
        frac_r=$(( r2 + (r3 - r2) * j / half2 ))
        frac_g=$(( g2 + (g3 - g2) * j / half2 ))
        frac_b=$(( b2 + (b3 - b2) * j / half2 ))
      fi
      accent_line+=$'\033'"[38;2;${frac_r};${frac_g};${frac_b}m━"
    done
    printf '%s\n' "${accent_line}${C_RESET}"
  fi
fi

# ---------------------------------------------------------------------------
# Pre-fetch git info so line 1 can show repo name before model
# ---------------------------------------------------------------------------
git_dir="${work_dir:-${project_dir:-$cwd}}"
git_raw_line1=""
if [[ "$CFG_SHOW_GIT" == true ]]; then
  git_raw_line1="$(get_git_info "$git_dir")"
fi

# Location name: repo name if in git, else cwd basename.
# git_raw_line1 is a 5-field string; we only need field 1 (repo name) here.
# Branch, staged, modified, untracked are re-parsed for line 2 below.
location_name=""
if [[ -n "$git_raw_line1" ]]; then
  IFS='|' read -r _repo_tmp _rest <<< "$git_raw_line1"
  location_name="$_repo_tmp"
fi
if [[ -z "$location_name" && -n "$display_dir" ]]; then
  location_name="$(basename "$display_dir" 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# LINE 1: Folder/Repo | Model | Path | Session | Agent/Worktree
# ---------------------------------------------------------------------------
line1=""

# Folder or repo name prefix (dim bold)
if [[ -n "$location_name" ]]; then
  line1="${C_BOLD}${location_name}${C_RESET}"
fi

# Model name in cyan
if [[ -n "$display_model" ]]; then
  [[ -n "$line1" ]] && line1+="  "
  line1+="${C_CYAN}${C_BOLD}${display_model}${C_RESET}"
fi

# Path (skipped when location_name already covers it; keeps line 1 readable)
if [[ -z "$location_name" && -n "$display_dir" ]]; then
  [[ -n "$line1" ]] && line1+="  "
  line1+="${display_dir}"
fi

# Session
if [[ "$CFG_SHOW_SESSION" == true && -n "$short_session" ]]; then
  line1+="${CFG_SEPARATOR}#${short_session}"
fi

# Vim mode
if [[ -n "$vim_mode" ]]; then
  line1+="${CFG_SEPARATOR}${C_YELLOW}[${vim_mode}]${C_RESET}"
fi

# Agent
if [[ -n "$agent_name" ]]; then
  line1+="${CFG_SEPARATOR}${C_CYAN}[${agent_name}]${C_RESET}"
fi

# Worktree
if [[ -n "$worktree_name" ]]; then
  line1+=" ${C_MAGENTA}[${worktree_name}]${C_RESET}"
fi

printf '%s\n' "$line1"

# ---------------------------------------------------------------------------
# LINE 2: Git branch + stats | Lines added/removed
# ---------------------------------------------------------------------------
if [[ "$CFG_SHOW_GIT" == true ]]; then
  # Reuse pre-fetched git info from line 1
  git_raw="$git_raw_line1"

  if [[ -n "$git_raw" ]]; then
    IFS='|' read -r repo_name branch staged modified untracked <<< "$git_raw"

    # Repo name moved to line 1 prefix; line 2 shows only branch + change counts
    line2="${CFG_PREFIX}${C_MAGENTA}${C_BOLD}${branch}${C_RESET}"

    if (( staged > 0 )); then
      line2+="  ${C_GREEN}+${staged} staged${C_RESET}"
    fi
    if (( modified > 0 )); then
      line2+="  ${C_YELLOW}~${modified} modified${C_RESET}"
    fi
    if (( untracked > 0 )); then
      line2+="  ${C_RED}?${untracked} untracked${C_RESET}"
    fi

    # Lines added/removed from session cost data
    if [[ "$CFG_SHOW_LINES" == true ]]; then
      if (( lines_added > 0 || lines_removed > 0 )); then
        line2+="${CFG_SEPARATOR}"
        if (( lines_added > 0 )); then
          line2+="${C_GREEN}+${lines_added}${C_RESET}"
        fi
        if (( lines_removed > 0 )); then
          [[ $lines_added -gt 0 ]] && line2+=" "
          line2+="${C_RED}-${lines_removed}${C_RESET}"
        fi
      fi
    fi

    printf '%s\n' "$line2"
  fi
fi

# ---------------------------------------------------------------------------
# LINE 3: Context window progress bar | Token usage
# ---------------------------------------------------------------------------
if [[ "$CFG_SHOW_TOKENS" == true ]]; then
  # Build progress bar
  local_filled=$(( used_pct_int * CFG_BAR_WIDTH / 100 ))
  local_empty=$(( CFG_BAR_WIDTH - local_filled ))

  # Color based on usage threshold
  if (( used_pct_int >= 90 )); then
    bar_color="$C_RED"
  elif (( used_pct_int >= 70 )); then
    bar_color="$C_YELLOW"
  else
    bar_color="$C_GREEN"
  fi

  # Build bar string
  bar_filled=""
  for (( i = 0; i < local_filled; i++ )); do
    bar_filled+="="
  done
  bar_empty=""
  for (( i = 0; i < local_empty; i++ )); do
    bar_empty+="-"
  done

  window_fmt="$(fmt_window "$window_size")"
  input_fmt="$(fmt_tokens "$input_tokens")"
  output_fmt="$(fmt_tokens "$output_tokens")"
  cache_fmt="$(fmt_tokens "$cache_tokens")"

  line3="${CFG_PREFIX}${bar_color}[${bar_filled}${C_DIM}${bar_empty}${C_RESET}${bar_color}]${C_RESET}"
  line3+="  ${used_pct_int}%/${window_fmt}"
  line3+="${CFG_SEPARATOR}${input_fmt} in  ${output_fmt} out  ${cache_fmt} hit"

  printf '%s\n' "$line3"
fi

# ---------------------------------------------------------------------------
# LINE 4: Cost | Duration
# ---------------------------------------------------------------------------
if [[ "$CFG_SHOW_COST" == true ]]; then
  duration_fmt="$(fmt_duration "$total_duration")"

  # Calculate cost per minute
  cost_per_min="0"
  if (( total_duration > 0 )); then
    # Use awk for floating point math
    cost_per_min="$(awk -v c="$total_cost" -v d="$total_duration" 'BEGIN { printf "%.2f", (c / (d / 60000)) }' 2>/dev/null || echo "0")"
  fi

  # Format total cost
  cost_fmt="$(awk -v c="$total_cost" 'BEGIN { printf "%.2f", c }' 2>/dev/null || echo "0.00")"

  line4="${CFG_PREFIX}${C_GREEN}\$${cost_fmt}${C_RESET}"
  if [[ "$cost_per_min" != "0" && "$cost_per_min" != "inf" && "$cost_per_min" != "-nan" ]]; then
    line4+=" ${C_DIM}(${cost_per_min}/min)${C_RESET}"
  fi
  line4+="${CFG_SEPARATOR}${duration_fmt}"

  printf '%s\n' "$line4"
fi

# ---------------------------------------------------------------------------
# MISSION BLOCK: goal (with progress bar + status badge) + recent summary
# ---------------------------------------------------------------------------
mission_file=""
if [[ -n "${BRIF_SESSION_ID:-}" && "$BRIF_SESSION_ID" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  candidate="$HOME/.claude/brif/$BRIF_SESSION_ID/mission.json"
  [[ -f "$candidate" ]] && mission_file="$candidate"
fi
if [[ -z "$mission_file" ]]; then
  candidate="$HOME/.claude/brif/current/mission.json"
  if [[ -f "$candidate" ]]; then
    # Only use current/ if it belongs to this session
    session_id_file="$HOME/.claude/brif/current/.session_id"
    current_owner=""
    [[ -f "$session_id_file" ]] && current_owner="$(tr -d '[:space:]' < "$session_id_file")"
    my_session_id="$session_id"
    if [[ -z "$current_owner" || -z "$my_session_id" || "$current_owner" == "$my_session_id" ]]; then
      mission_file="$candidate"
    fi
  fi
fi

# Word-boundary truncation: cut at last space before $2 chars, append …
truncate_to_width() {
  local text="$1"
  local max="$2"
  local len=${#text}
  if (( max <= 1 || len <= max )); then
    printf '%s' "$text"
    return
  fi
  local cut=$(( max - 1 ))
  local head="${text:0:cut}"
  # Find last space in head
  local trimmed="${head% *}"
  if [[ "$trimmed" == "$head" || -z "$trimmed" ]]; then
    # No space found (or single long word) — hard cut
    printf '%s…' "$head"
  else
    printf '%s…' "$trimmed"
  fi
}

if [[ -n "$mission_file" ]]; then
  m_goal="$(jq -r '.goal // empty' "$mission_file" 2>/dev/null)"
  m_summary="$(jq -r '.summary // empty' "$mission_file" 2>/dev/null)"
  m_done="$(jq -r '.progress // [] | length' "$mission_file" 2>/dev/null || echo 0)"
  m_rem="$(jq -r '.remaining // [] | length' "$mission_file" 2>/dev/null || echo 0)"
  m_status="$(jq -r '.status // "active"' "$mission_file" 2>/dev/null)"
  m_pending="$(jq -r '.pending // empty' "$mission_file" 2>/dev/null)"
  m_total=$(( m_done + m_rem ))

  # Terminal width for truncation
  term_width="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"

  if [[ -n "$m_goal" ]]; then
    # 10-segment progress bar
    if (( m_total > 0 )); then
      m_filled=$(( m_done * 10 / m_total ))
    else
      m_filled=0
    fi
    m_empty=$(( 10 - m_filled ))
    m_bar=""
    for (( i = 0; i < m_filled; i++ )); do m_bar+="="; done
    for (( i = 0; i < m_empty;  i++ )); do m_bar+="-"; done

    # Status badge
    case "$m_status" in
      waiting_approval) status_badge="${C_YELLOW}APPROVE${C_RESET}" ;;
      blocked)          status_badge="${C_RED}BLOCKED${C_RESET}" ;;
      idle)             status_badge="IDLE" ;;
      *)                status_badge="" ;;
    esac

    # Truncate goal — reserve space for bar (~17) + badge (~9) + prefix (~3)
    goal_overhead=3
    (( m_total > 0 )) && goal_overhead=$(( goal_overhead + 17 ))
    [[ -n "$status_badge" ]] && goal_overhead=$(( goal_overhead + 9 ))
    goal_max=$(( term_width - goal_overhead ))
    (( goal_max < 10 )) && goal_max=10
    goal_display="$(truncate_to_width "$m_goal" "$goal_max")"

    line_goal=" | ${goal_display}"
    if (( m_total > 0 )); then
      line_goal+="  [${m_bar}] ${m_done}/${m_total}"
    fi
    [[ -n "$status_badge" ]] && line_goal+="  ${status_badge}"
    if [[ -n "$m_pending" && "$m_status" == "waiting_approval" ]]; then
      line_goal+="  ${C_DIM}${m_pending}${C_RESET}"
    fi
    printf '%b\n' "$line_goal"
  fi

  # Recent summary — suppress below 50 cols
  if [[ -n "$m_summary" && "$term_width" -ge 50 ]]; then
    # Overhead: " | " (3) + "recent  " (8) = 11
    recent_max=$(( term_width - 11 ))
    (( recent_max < 10 )) && recent_max=10
    recent_display="$(truncate_to_width "$m_summary" "$recent_max")"
    printf '%b\n' " | ${C_BOLD}recent${C_RESET}  ${recent_display}"
  fi
fi

# ---------------------------------------------------------------------------
# LINE 5: Weather (country + condition + temp)
# ---------------------------------------------------------------------------
if [[ "$CFG_SHOW_WEATHER" == true ]]; then
  weather_raw="$(get_weather_info)"

  if [[ -n "$weather_raw" ]]; then
    IFS='|' read -r w_country w_condition w_temp <<< "$weather_raw"

    # Day/night icon based on hour
    current_hour="$(date +%H)"
    current_hour="${current_hour#0}"  # strip leading zero
    if (( current_hour >= 6 && current_hour <= 20 )); then
      dn_icon="☀"
    else
      dn_icon="🌙"
    fi

    line5="${CFG_PREFIX}${C_BOLD}${w_country}${C_RESET} ${dn_icon}"
    if [[ -n "$w_temp" && "$w_temp" != "?" ]]; then
      line5+=" ${w_temp}"
    fi

    printf '%s\n' "$line5"
  fi
fi

# ---------------------------------------------------------------------------
# METRICS SIDECAR: Write brif metrics.json if session is active
# ---------------------------------------------------------------------------
if [[ -n "${BRIF_SESSION_ID:-}" ]]; then
  if [[ ! "$BRIF_SESSION_ID" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    exit 0
  fi
  metrics_dir="$HOME/.claude/brif/$BRIF_SESSION_ID"
  if [[ -d "$metrics_dir" ]]; then
    # Reuse branch from git_raw_line1 (pre-fetched for line 1) — avoids a fork
    current_branch=""
    if [[ -n "$git_raw_line1" ]]; then
      IFS='|' read -r _ current_branch _ _ _ <<< "$git_raw_line1"
    fi
    jq -n --argjson ctx "$used_pct_int" \
           --argjson cost "$total_cost" \
           --argjson dur "$total_duration" \
           --arg proj "$display_dir" \
           --arg br "$current_branch" \
      '{context_pct: $ctx, cost_usd: $cost, duration_ms: $dur, project_dir: $proj, branch: $br}' \
      > "$metrics_dir/metrics.json.tmp" && mv "$metrics_dir/metrics.json.tmp" "$metrics_dir/metrics.json"
  fi
fi
