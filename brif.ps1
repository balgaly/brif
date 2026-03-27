#!/usr/bin/env pwsh
# brif.ps1 — launcher for Claude Code with mission context (Windows Terminal)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

param([Parameter(ValueFromRemainingArguments)][string[]]$ClaudeArgs)

# --- Check dependencies ---
if (-not (Get-Command wt -ErrorAction SilentlyContinue)) {
    Write-Host "brif requires Windows Terminal. Install from Microsoft Store or:"
    Write-Host "  winget install Microsoft.WindowsTerminal"
    exit 1
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "brif requires Claude Code. See: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
}

# --- Resolve paths ---
$BRIF_DIR = Join-Path $HOME ".claude\brif"
$PANE_SCRIPT = Join-Path $HOME ".claude\brif-pane.ps1"

if (-not (Test-Path $PANE_SCRIPT)) {
    $PANE_SCRIPT = Join-Path $PSScriptRoot "brif-pane.ps1"
}

if (-not (Test-Path $PANE_SCRIPT)) {
    Write-Host "brif-pane.ps1 not found. Run the installer first."
    exit 1
}

# --- Session ID ---
$SESSION_ID = "brif-$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"

# Check if resuming
for ($i = 0; $i -lt $ClaudeArgs.Count; $i++) {
    if ($ClaudeArgs[$i] -eq "--resume" -and $i + 1 -lt $ClaudeArgs.Count) {
        $resumeArg = $ClaudeArgs[$i + 1]
        $SESSION_ID = "brif-" + $resumeArg.Substring(0, [Math]::Min(8, $resumeArg.Length))
    }
}

# --- Create session directory ---
$SESSION_DIR = Join-Path $BRIF_DIR $SESSION_ID
New-Item -ItemType Directory -Path $SESSION_DIR -Force | Out-Null

# --- Create/update current junction ---
$CURRENT_LINK = Join-Path $BRIF_DIR "current"
if (Test-Path $CURRENT_LINK) {
    Remove-Item $CURRENT_LINK -Force -Recurse
}
New-Item -ItemType Junction -Path $CURRENT_LINK -Target $SESSION_DIR | Out-Null

# --- Generate color if needed ---
$MISSION_FILE = Join-Path $SESSION_DIR "mission.json"
if (-not (Test-Path $MISSION_FILE)) {
    $r = Get-Random -Maximum 256
    $g = Get-Random -Maximum 256
    $b = Get-Random -Maximum 256
    $color = "#{0:x2}{1:x2}{2:x2}" -f $r, $g, $b
    $mission = @{
        version = 1
        goal = ""
        progress = @()
        remaining = @()
        status = "active"
        pending = ""
        color = $color
    }
    $mission | ConvertTo-Json | Set-Content $MISSION_FILE -Encoding utf8
}

# --- Export session ID for hooks ---
$env:BRIF_SESSION_ID = $SESSION_ID

# --- Launch Windows Terminal with split panes ---
# Quote arguments properly for Windows Terminal
$claudeArgsStr = ($ClaudeArgs | ForEach-Object { "`"$_`"" }) -join " "

# Build wt command:
# - New tab in current window (-w _)
# - Split pane vertically with 8% for top pane
# - Top pane runs brif-pane.ps1
# - Move focus down, then run claude in bottom pane
$wtCmd = "wt.exe -w _ sp -V --size 0.08 pwsh.exe -NoProfile -File `"$PANE_SCRIPT`" `"$SESSION_ID`" `; mf down `; pwsh.exe -NoProfile -Command `"`$env:BRIF_SESSION_ID='$SESSION_ID'; claude $claudeArgsStr`""

# Execute via cmd to handle complex quoting
Start-Process -NoNewWindow -FilePath "cmd.exe" -ArgumentList "/c", $wtCmd
