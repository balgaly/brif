#!/usr/bin/env bash
# brif-pane.sh — top pane renderer for brif
set -euo pipefail

# --- Configuration ---
CFG_BRIF_COLOR=""
CFG_POLL_INTERVAL=2
CFG_ACTIVE_TIMEOUT=10

# --- ANSI codes ---
ESC=$'\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"

# --- File paths ---
SESSION_ID="${1:-}"
MISSION_FILE="${BRIF_MISSION_FILE:-$HOME/.claude/brif/$SESSION_ID/mission.json}"
METRICS_FILE="${BRIF_METRICS_FILE:-$HOME/.claude/brif/$SESSION_ID/metrics.json}"
EVENTS_FILE="${BRIF_EVENTS_FILE:-$HOME/.claude/brif/$SESSION_ID/events.jsonl}"
LAST_GOOD_MISSION=""
RENDER_MODE="${BRIF_RENDER_MODE:-ambient}"
TERM_WIDTH="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"

# --- Color helpers (pure bash, no subshells) ---

# Compute fg color: simplified luminance check (no awk)
compute_colors() {
  local hex="${1#\#}"
  CR=$((16#${hex:0:2}))
  CG=$((16#${hex:2:2}))
  CB=$((16#${hex:4:2}))
  # Simplified luminance: (2126*R + 7152*G + 722*B) / 10000
  local lum=$(( (2126 * CR + 7152 * CG + 722 * CB) / 10000 ))
  C_BG="${ESC}[48;2;${CR};${CG};${CB}m"
  if (( lum > 128 )); then
    C_FG="${ESC}[38;2;0;0;0m"
  else
    C_FG="${ESC}[38;2;255;255;255m"
  fi
  C_BORDER="${C_BG}${C_FG}▎${RESET}"
}

# --- Data readers ---

read_mission() {
  if [[ -f "$MISSION_FILE" ]]; then
    local content
    if content=$(cat "$MISSION_FILE" 2>/dev/null) && [[ -n "$content" ]]; then
      LAST_GOOD_MISSION="$content"
      echo "$content"
      return 0
    fi
  fi
  if [[ -n "$LAST_GOOD_MISSION" ]]; then
    echo "$LAST_GOOD_MISSION"
    return 0
  fi
  return 1
}

# Extract all mission fields in ONE jq call (avoids N+1 jq spawns)
parse_mission() {
  local json="$1"
  M_GOAL="$(echo "$json" | jq -r '.goal // "No goal set"' 2>/dev/null)"
  M_STATUS="$(echo "$json" | jq -r '.status // "active"' 2>/dev/null)"
  M_PENDING="$(echo "$json" | jq -r '.pending // ""' 2>/dev/null)"
  M_COLOR="$(echo "$json" | jq -r '.color // "#6366f1"' 2>/dev/null)"
  M_DONE_COUNT="$(echo "$json" | jq -r '.progress | length' 2>/dev/null)"
  M_REM_COUNT="$(echo "$json" | jq -r '.remaining | length' 2>/dev/null)"
  M_DONE_LIST="$(echo "$json" | jq -r '(.progress // []) | join(", ")' 2>/dev/null)"
  M_REM_LIST="$(echo "$json" | jq -r '(.remaining // []) | join(", ")' 2>/dev/null)"
}

# Extract all metrics fields in ONE jq call
parse_metrics() {
  if [[ -f "$METRICS_FILE" ]]; then
    MET_CTX="$(jq -r '.context_pct // 0' "$METRICS_FILE" 2>/dev/null)" || true
    MET_COST="$(jq -r '.cost_usd // 0' "$METRICS_FILE" 2>/dev/null)" || true
    MET_DUR="$(jq -r '.duration_ms // 0' "$METRICS_FILE" 2>/dev/null)" || true
    MET_PROJ="$(jq -r '.project_dir // ""' "$METRICS_FILE" 2>/dev/null)" || true
    MET_BRANCH="$(jq -r '.branch // ""' "$METRICS_FILE" 2>/dev/null)" || true
  fi
  # Defaults
  MET_CTX="${MET_CTX:-0}"
  MET_COST="${MET_COST:-0}"
  MET_DUR="${MET_DUR:-0}"
  MET_PROJ="${MET_PROJ:-}"
  MET_BRANCH="${MET_BRANCH:-}"
}

# --- Render functions ---

render_ambient() {
  local mission
  if ! mission=$(read_mission); then
    echo "BRIF waiting for session data..."
    echo ""
    return
  fi

  parse_mission "$mission"
  parse_metrics

  local color="${CFG_BRIF_COLOR:-$M_COLOR}"
  compute_colors "$color"

  local project_name
  project_name=$(basename "$MET_PROJ" 2>/dev/null || echo "")
  local dur_min=$(( MET_DUR / 60000 ))

  local total=$((M_DONE_COUNT + M_REM_COUNT))

  # Progress bar
  local bar_width=10 filled=0
  if (( total > 0 )); then filled=$(( M_DONE_COUNT * bar_width / total )); fi
  local empty=$((bar_width - filled))
  local bar="["
  for (( i=0; i<filled; i++ )); do bar+="="; done
  for (( i=0; i<empty; i++ )); do bar+="-"; done
  bar+="]"

  # Truncate goal
  local max_goal=$((TERM_WIDTH - 60))
  local goal="$M_GOAL"
  if (( ${#goal} > max_goal && max_goal > 10 )); then
    goal="${goal:0:$((max_goal-3))}..."
  fi

  # Line 1: badge + project/branch + metrics
  echo -n "${C_BORDER} ${C_BG}${C_FG}${BOLD} BRIF ${RESET} "
  echo -n "${project_name}/${MET_BRANCH} "
  echo -n "${DIM}ctx:${RESET}${MET_CTX}% "
  printf "${DIM}\$${RESET}%.2f " "$MET_COST"
  echo ""

  # Line 2: goal + progress + pending
  echo -n "${C_BORDER} Goal: ${goal} ${bar} ${M_DONE_COUNT}/${total} "
  if [[ "$M_STATUS" == "waiting_approval" && -n "$M_PENDING" ]]; then
    echo -n "${BOLD}APPROVE${RESET} ${M_PENDING}"
  fi
  echo ""
}

render_active() {
  local mission
  if ! mission=$(read_mission); then
    echo "BRIF waiting for session data..."
    echo ""
    return
  fi

  parse_mission "$mission"
  parse_metrics

  local color="${CFG_BRIF_COLOR:-$M_COLOR}"
  compute_colors "$color"

  local project_name
  project_name=$(basename "$MET_PROJ" 2>/dev/null || echo "")
  local dur_min=$(( MET_DUR / 60000 ))
  local total=$((M_DONE_COUNT + M_REM_COUNT))

  # Line 1: badge + project/branch + metrics
  echo -n "${C_BORDER} ${C_BG}${C_FG}${BOLD} BRIF ${RESET} "
  echo -n "${project_name}/${MET_BRANCH} "
  echo -n "${DIM}ctx:${RESET}${MET_CTX}% "
  printf "${DIM}\$${RESET}%.2f " "$MET_COST"
  echo ""

  # Line 2: separator
  echo -n "${C_BORDER} "
  for ((i=0; i<TERM_WIDTH-4; i++)); do echo -n "-"; done
  echo ""

  # Line 3: Goal
  echo "${C_BORDER} Goal: ${M_GOAL}"

  # Line 4: Done
  echo "${C_BORDER} Done: ${M_DONE_LIST:-nothing yet} (${M_DONE_COUNT}/${total})"

  # Line 5: Next
  echo "${C_BORDER} Next: ${M_REM_LIST:-all done!}"

  # Line 6: Waiting
  if [[ "$M_STATUS" == "waiting_approval" && -n "$M_PENDING" ]]; then
    echo "${C_BORDER} Waiting: ${BOLD}APPROVE${RESET} ${M_PENDING}"
  elif [[ "$M_STATUS" == "blocked" ]]; then
    echo "${C_BORDER} Blocked: ${M_PENDING:-unknown reason}"
  fi
}

# --- Main ---

if [[ "${1:-}" == "--render-once" ]]; then
  if [[ "$RENDER_MODE" == "active" ]]; then
    render_active
  else
    render_ambient
  fi
  exit 0
fi

# --- Test triggers mode ---
if [[ "${1:-}" == "--test-triggers" ]]; then
  mode="${BRIF_RENDER_MODE:-ambient}"
  elapsed="${BRIF_TEST_ELAPSED:-0}"

  # 1. Auto-collapse after timeout (unconditional)
  if [[ "$mode" == "active" && "$elapsed" -gt "$CFG_ACTIVE_TIMEOUT" ]]; then
    mode="ambient"
  fi

  # 2. Approval auto-expand (re-triggers after collapse)
  if [[ -f "$MISSION_FILE" ]]; then
    status=$(jq -r '.status // "active"' "$MISSION_FILE" 2>/dev/null || echo "active")
    if [[ "$status" == "waiting_approval" ]]; then
      mode="active"
    fi
  fi

  # 3. Inactivity return
  if [[ "${BRIF_TEST_DETECT_INACTIVITY:-}" == "true" && -f "$EVENTS_FILE" ]]; then
    mode="active"
  fi

  echo "trigger:$mode"
  exit 0
fi

# --- Poll loop ---
current_mode="active"
active_since=$(date +%s)
last_event_mtime=0

clear_pane() {
  printf "${ESC}[H${ESC}[J"
}

get_file_mtime() {
  local file="$1"
  if [[ ! -f "$file" ]]; then echo 0; return; fi
  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f '%m' "$file" 2>/dev/null || echo 0
  else
    stat -c '%Y' "$file" 2>/dev/null || echo 0
  fi
}

while true; do
  now=$(date +%s)

  # Check for inactivity return
  new_mtime=$(get_file_mtime "$EVENTS_FILE")
  if (( new_mtime > last_event_mtime && last_event_mtime > 0 )); then
    gap=$(( new_mtime - last_event_mtime ))
    if (( gap > 300 )); then
      current_mode="active"
      active_since=$now
    fi
  fi
  last_event_mtime=$new_mtime

  # Auto-collapse after timeout (unconditional)
  if [[ "$current_mode" == "active" ]]; then
    elapsed=$(( now - active_since ))
    if (( elapsed >= CFG_ACTIVE_TIMEOUT )); then
      current_mode="ambient"
    fi
  fi

  # Render
  clear_pane
  if [[ "$current_mode" == "active" ]]; then
    render_active
  else
    render_ambient
  fi

  # Approval auto-expand (re-triggers after collapse, uses M_STATUS from render)
  if [[ "${M_STATUS:-}" == "waiting_approval" && "$current_mode" != "active" ]]; then
    current_mode="active"
    active_since=$now
    # Re-render in active mode immediately
    clear_pane
    render_active
  fi

  # Read input (non-blocking) — Enter toggles active mode
  if read -t "$CFG_POLL_INTERVAL" -n 1 key 2>/dev/null; then
    if [[ "$key" == "" ]]; then
      if [[ "$current_mode" == "ambient" ]]; then
        current_mode="active"
      else
        current_mode="ambient"
      fi
      active_since=$now
    fi
  fi
done
