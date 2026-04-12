#!/usr/bin/env pwsh
# brif-pane.ps1 — top pane renderer for brif (Windows Terminal)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

param(
    [string]$SessionId,
    [switch]$RenderOnce,
    [switch]$TestTriggers
)

# --- Configuration ---
$CFG_BRIF_COLOR = ""
$CFG_POLL_INTERVAL = 2
$CFG_ACTIVE_TIMEOUT = 10

# --- ANSI codes ---
$ESC = [char]27
$RESET = "${ESC}[0m"
$BOLD = "${ESC}[1m"
$DIM = "${ESC}[2m"

# --- File paths ---
if (-not $SessionId) { $SessionId = $args[0] }
if ($SessionId -and $SessionId -notmatch '^[a-zA-Z0-9._-]+$') {
    Write-Error "brif-pane: invalid session ID"
    exit 1
}
$MISSION_FILE = if ($env:BRIF_MISSION_FILE) { $env:BRIF_MISSION_FILE } else { Join-Path $HOME ".claude\brif\$SessionId\mission.json" }
$METRICS_FILE = if ($env:BRIF_METRICS_FILE) { $env:BRIF_METRICS_FILE } else { Join-Path $HOME ".claude\brif\$SessionId\metrics.json" }
$EVENTS_FILE = if ($env:BRIF_EVENTS_FILE) { $env:BRIF_EVENTS_FILE } else { Join-Path $HOME ".claude\brif\$SessionId\events.jsonl" }
$LAST_GOOD_MISSION = ""
$RENDER_MODE = if ($env:BRIF_RENDER_MODE) { $env:BRIF_RENDER_MODE } else { "ambient" }
$TERM_WIDTH = $Host.UI.RawUI.WindowSize.Width

# --- Color helpers ---
$script:CR = 0
$script:CG = 0
$script:CB = 0
$script:C_BG = ""
$script:C_FG = ""
$script:C_BORDER = ""

function Compute-Colors {
    param([string]$hex)

    $hex = $hex.TrimStart('#')
    $script:CR = [Convert]::ToInt32($hex.Substring(0, 2), 16)
    $script:CG = [Convert]::ToInt32($hex.Substring(2, 2), 16)
    $script:CB = [Convert]::ToInt32($hex.Substring(4, 2), 16)

    # Simplified luminance: (2126*R + 7152*G + 722*B) / 10000
    $lum = (2126 * $script:CR + 7152 * $script:CG + 722 * $script:CB) / 10000

    $script:C_BG = "${ESC}[48;2;${script:CR};${script:CG};${script:CB}m"
    if ($lum -gt 128) {
        $script:C_FG = "${ESC}[38;2;0;0;0m"
    } else {
        $script:C_FG = "${ESC}[38;2;255;255;255m"
    }
    $script:C_BORDER = "${script:C_BG}${script:C_FG}▎${RESET}"
}

# --- Data readers ---
function Read-Mission {
    if (Test-Path $MISSION_FILE) {
        try {
            $content = Get-Content $MISSION_FILE -Raw -ErrorAction Stop
            if ($content) {
                $script:LAST_GOOD_MISSION = $content
                return $content
            }
        } catch {}
    }
    if ($script:LAST_GOOD_MISSION) {
        return $script:LAST_GOOD_MISSION
    }
    return $null
}

$script:M_GOAL = ""
$script:M_STATUS = "active"
$script:M_PENDING = ""
$script:M_COLOR = "#6366f1"
$script:M_DONE_COUNT = 0
$script:M_REM_COUNT = 0
$script:M_DONE_LIST = ""
$script:M_REM_LIST = ""

function Parse-Mission {
    param([string]$json)

    try {
        $obj = $json | ConvertFrom-Json
        $script:M_GOAL = if ($obj.goal) { $obj.goal } else { "No goal set" }
        $script:M_STATUS = if ($obj.status) { $obj.status } else { "active" }
        $script:M_PENDING = if ($obj.pending) { $obj.pending } else { "" }
        $script:M_COLOR = if ($obj.color) { $obj.color } else { "#6366f1" }
        $script:M_DONE_COUNT = if ($obj.progress) { $obj.progress.Count } else { 0 }
        $script:M_REM_COUNT = if ($obj.remaining) { $obj.remaining.Count } else { 0 }
        $script:M_DONE_LIST = if ($obj.progress) { $obj.progress -join ", " } else { "" }
        $script:M_REM_LIST = if ($obj.remaining) { $obj.remaining -join ", " } else { "" }
    } catch {}
}

$script:MET_CTX = 0
$script:MET_COST = 0.0
$script:MET_DUR = 0
$script:MET_PROJ = ""
$script:MET_BRANCH = ""

function Parse-Metrics {
    if (Test-Path $METRICS_FILE) {
        try {
            $obj = Get-Content $METRICS_FILE -Raw | ConvertFrom-Json
            $script:MET_CTX = if ($obj.context_pct) { $obj.context_pct } else { 0 }
            $script:MET_COST = if ($obj.cost_usd) { $obj.cost_usd } else { 0.0 }
            $script:MET_DUR = if ($obj.duration_ms) { $obj.duration_ms } else { 0 }
            $script:MET_PROJ = if ($obj.project_dir) { $obj.project_dir } else { "" }
            $script:MET_BRANCH = if ($obj.branch) { $obj.branch } else { "" }
        } catch {}
    }
}

# --- Render functions ---
function Render-Ambient {
    $mission = Read-Mission
    if (-not $mission) {
        Write-Host "BRIF waiting for session data..."
        Write-Host ""
        return
    }

    Parse-Mission $mission
    Parse-Metrics

    $color = if ($CFG_BRIF_COLOR) { $CFG_BRIF_COLOR } else { $script:M_COLOR }
    Compute-Colors $color

    $projectName = if ($script:MET_PROJ) { Split-Path $script:MET_PROJ -Leaf } else { "" }
    $durMin = [int]($script:MET_DUR / 60000)

    $total = $script:M_DONE_COUNT + $script:M_REM_COUNT

    # Progress bar
    $barWidth = 10
    $filled = if ($total -gt 0) { [int]($script:M_DONE_COUNT * $barWidth / $total) } else { 0 }
    $empty = $barWidth - $filled
    $bar = "[" + ("=" * $filled) + ("-" * $empty) + "]"

    # Truncate goal
    $maxGoal = $TERM_WIDTH - 60
    $goal = $script:M_GOAL
    if ($goal.Length -gt $maxGoal -and $maxGoal -gt 10) {
        $goal = $goal.Substring(0, $maxGoal - 3) + "..."
    }

    # Line 1: badge + project/branch + metrics
    Write-Host -NoNewline "${script:C_BORDER} ${script:C_BG}${script:C_FG}${BOLD} BRIF ${RESET} "
    Write-Host -NoNewline "${projectName}/${script:MET_BRANCH} "
    Write-Host -NoNewline "${DIM}ctx:${RESET}${script:MET_CTX}% "
    Write-Host -NoNewline ("{0}`$`{1:F2} " -f $DIM, $script:MET_COST)
    Write-Host ""

    # Line 2: goal + progress + pending
    Write-Host -NoNewline "${script:C_BORDER} Goal: ${goal} ${bar} ${script:M_DONE_COUNT}/${total} "
    if ($script:M_STATUS -eq "waiting_approval" -and $script:M_PENDING) {
        Write-Host -NoNewline "${BOLD}APPROVE${RESET} ${script:M_PENDING}"
    }
    Write-Host ""
}

function Render-Active {
    $mission = Read-Mission
    if (-not $mission) {
        Write-Host "BRIF waiting for session data..."
        Write-Host ""
        return
    }

    Parse-Mission $mission
    Parse-Metrics

    $color = if ($CFG_BRIF_COLOR) { $CFG_BRIF_COLOR } else { $script:M_COLOR }
    Compute-Colors $color

    $projectName = if ($script:MET_PROJ) { Split-Path $script:MET_PROJ -Leaf } else { "" }
    $durMin = [int]($script:MET_DUR / 60000)
    $total = $script:M_DONE_COUNT + $script:M_REM_COUNT

    # Line 1: badge + project/branch + metrics
    Write-Host -NoNewline "${script:C_BORDER} ${script:C_BG}${script:C_FG}${BOLD} BRIF ${RESET} "
    Write-Host -NoNewline "${projectName}/${script:MET_BRANCH} "
    Write-Host -NoNewline "${DIM}ctx:${RESET}${script:MET_CTX}% "
    Write-Host -NoNewline ("{0}`$`{1:F2} " -f $DIM, $script:MET_COST)
    Write-Host ""

    # Line 2: separator
    Write-Host -NoNewline "${script:C_BORDER} "
    Write-Host ("-" * ($TERM_WIDTH - 4))

    # Line 3: Goal
    Write-Host "${script:C_BORDER} Goal: ${script:M_GOAL}"

    # Line 4: Done
    $doneText = if ($script:M_DONE_LIST) { $script:M_DONE_LIST } else { "nothing yet" }
    Write-Host "${script:C_BORDER} Done: ${doneText} (${script:M_DONE_COUNT}/${total})"

    # Line 5: Next
    $remText = if ($script:M_REM_LIST) { $script:M_REM_LIST } else { "all done!" }
    Write-Host "${script:C_BORDER} Next: ${remText}"

    # Line 6: Waiting
    if ($script:M_STATUS -eq "waiting_approval" -and $script:M_PENDING) {
        Write-Host "${script:C_BORDER} Waiting: ${BOLD}APPROVE${RESET} ${script:M_PENDING}"
    } elseif ($script:M_STATUS -eq "blocked") {
        $blockReason = if ($script:M_PENDING) { $script:M_PENDING } else { "unknown reason" }
        Write-Host "${script:C_BORDER} Blocked: ${blockReason}"
    }
}

# --- Main ---

if ($RenderOnce) {
    if ($RENDER_MODE -eq "active") {
        Render-Active
    } else {
        Render-Ambient
    }
    exit 0
}

# --- Test triggers mode ---
if ($TestTriggers) {
    $mode = if ($env:BRIF_RENDER_MODE) { $env:BRIF_RENDER_MODE } else { "ambient" }
    $elapsed = if ($env:BRIF_TEST_ELAPSED) { [int]$env:BRIF_TEST_ELAPSED } else { 0 }

    # 1. Auto-collapse after timeout
    if ($mode -eq "active" -and $elapsed -gt $CFG_ACTIVE_TIMEOUT) {
        $mode = "ambient"
    }

    # 2. Approval auto-expand
    if (Test-Path $MISSION_FILE) {
        try {
            $obj = Get-Content $MISSION_FILE -Raw | ConvertFrom-Json
            $status = if ($obj.status) { $obj.status } else { "active" }
            if ($status -eq "waiting_approval") {
                $mode = "active"
            }
        } catch {}
    }

    # 3. Inactivity return
    if ($env:BRIF_TEST_DETECT_INACTIVITY -eq "true" -and (Test-Path $EVENTS_FILE)) {
        $mode = "active"
    }

    Write-Host "trigger:$mode"
    exit 0
}

# --- Poll loop ---
$currentMode = "active"
$activeSince = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$lastEventMtime = 0

function Clear-Pane {
    Write-Host "${ESC}[H${ESC}[J" -NoNewline
}

function Get-FileMtime {
    param([string]$file)
    if (-not (Test-Path $file)) { return 0 }
    try {
        $dto = [DateTimeOffset](Get-Item $file).LastWriteTimeUtc
        return $dto.ToUnixTimeSeconds()
    } catch {
        return 0
    }
}

while ($true) {
    $now = [DateTimeOffset]::Now.ToUnixTimeSeconds()

    # Check for inactivity return
    $newMtime = Get-FileMtime $EVENTS_FILE
    if ($newMtime -gt $lastEventMtime -and $lastEventMtime -gt 0) {
        $gap = $newMtime - $lastEventMtime
        if ($gap -gt 300) {
            $currentMode = "active"
            $activeSince = $now
        }
    }
    $lastEventMtime = $newMtime

    # Auto-collapse after timeout
    if ($currentMode -eq "active") {
        $elapsed = $now - $activeSince
        if ($elapsed -ge $CFG_ACTIVE_TIMEOUT) {
            $currentMode = "ambient"
        }
    }

    # Approval auto-expand
    if (Test-Path $MISSION_FILE) {
        try {
            $obj = Get-Content $MISSION_FILE -Raw | ConvertFrom-Json
            $status = if ($obj.status) { $obj.status } else { "active" }
            if ($status -eq "waiting_approval") {
                $currentMode = "active"
                $activeSince = $now
            }
        } catch {}
    }

    # Render
    Clear-Pane
    if ($currentMode -eq "active") {
        Render-Active
    } else {
        Render-Ambient
    }

    # Check for Enter key (toggle mode)
    $timeout = [DateTime]::Now.AddSeconds($CFG_POLL_INTERVAL)
    while ([DateTime]::Now -lt $timeout) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Enter) {
                if ($currentMode -eq "ambient") {
                    $currentMode = "active"
                } else {
                    $currentMode = "ambient"
                }
                $activeSince = $now
                break
            }
        }
        Start-Sleep -Milliseconds 100
    }
}
