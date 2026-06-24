#!/usr/bin/env pwsh
# brif.ps1 — launcher for Claude Code with mission context top pane (Windows / psmux)
# Usage: .\brif.ps1 [claude-code-args...]
#        .\brif.ps1 --resume <session-id> [claude-code-args...]
#
# Requires: psmux (winget install marlocarlo.psmux), Claude Code CLI
# Mirrors the Unix `brif` bash launcher for native Windows PowerShell + psmux.
# Run from PowerShell — psmux must be on PATH.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

# --- Check dependencies ---
if (-not (Get-Command psmux -ErrorAction SilentlyContinue)) {
    Write-Host "brif.ps1 requires psmux. Install it with:"
    Write-Host "  winget install marlocarlo.psmux"
    Write-Host "Then restart your terminal."
    exit 1
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "brif.ps1 requires Claude Code. See: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
}

# --- Resolve paths ---
$BRIF_DIR    = Join-Path $HOME ".claude\brif"
$PANE_SCRIPT = Join-Path $HOME ".claude\brif-pane.ps1"

if (-not (Test-Path $PANE_SCRIPT)) {
    $PANE_SCRIPT = Join-Path $PSScriptRoot "brif-pane.ps1"
}

if (-not (Test-Path $PANE_SCRIPT)) {
    Write-Host "brif-pane.ps1 not found. Run the installer first."
    exit 1
}

# --- Session ID ---
# Default: brif-<8 hex chars> derived from current time hash
$timestamp  = [DateTimeOffset]::Now.ToUnixTimeMilliseconds().ToString()
$hashBytes  = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                  [System.Text.Encoding]::UTF8.GetBytes($timestamp))
$SESSION_ID = "brif-" + (($hashBytes | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 8)

# Honor --resume <id>: sanitize to [a-zA-Z0-9._-], max 8 chars
$claudeArgs = @()
$i = 0
while ($i -lt $args.Count) {
    if ($args[$i] -eq "--resume" -and ($i + 1) -lt $args.Count) {
        $rawId      = $args[$i + 1]
        $cleanId    = ($rawId -replace '[^a-zA-Z0-9._\-]', '')
        $cleanId    = $cleanId.Substring(0, [Math]::Min(8, $cleanId.Length))
        $SESSION_ID = "brif-$cleanId"
        $i += 2
    } else {
        $claudeArgs += $args[$i]
        $i++
    }
}

# --- Create session directory ---
$SESSION_DIR = Join-Path $BRIF_DIR $SESSION_ID
New-Item -ItemType Directory -Path $SESSION_DIR -Force | Out-Null

# --- Create/update "current" junction ---
# Junction does not require Developer Mode (unlike SymbolicLink on Windows).
$CURRENT_LINK = Join-Path $BRIF_DIR "current"
if (Test-Path $CURRENT_LINK) { Remove-Item $CURRENT_LINK -Force -Recurse }
try {
    New-Item -ItemType Junction -Path $CURRENT_LINK -Target $SESSION_DIR -ErrorAction Stop | Out-Null
} catch {
    # Non-fatal: current link is a convenience alias only
}

# --- Seed mission.json if absent ---
$MISSION_FILE = Join-Path $SESSION_DIR "mission.json"
if (-not (Test-Path $MISSION_FILE)) {
    $r     = Get-Random -Maximum 256
    $g     = Get-Random -Maximum 256
    $b     = Get-Random -Maximum 256
    $color = "#{0:x2}{1:x2}{2:x2}" -f $r, $g, $b
    $seed  = @{
        version   = 1
        goal      = ""
        progress  = @()
        remaining = @()
        status    = "active"
        pending   = ""
        color     = $color
    } | ConvertTo-Json -Compress
    $tmpFile = Join-Path $SESSION_DIR "mission.json.tmp"
    $seed | Out-File -FilePath $tmpFile -Encoding utf8 -NoNewline
    Move-Item $tmpFile $MISSION_FILE -Force
}

# --- Export session ID for hooks ---
$env:BRIF_SESSION_ID = $SESSION_ID

# --- Build psmux session name (unique per PID) ---
$TMUX_SESSION = "brif-$PID"

# --- Terminal size ---
$cols  = $Host.UI.RawUI.WindowSize.Width
$lines = $Host.UI.RawUI.WindowSize.Height

# --- Launch psmux ---

# 1. Create detached session
& psmux new-session -d -s $TMUX_SESSION -x $cols -y $lines

# 2. Pass SESSION_ID via environment (injection-safe — no shell-quoting risk)
& psmux set-environment -t $TMUX_SESSION BRIF_SESSION_ID $SESSION_ID

# 3. Top pane (7 lines tall): brif-pane.ps1 renderer
#    -b = insert before (above), -v = vertical split, -l 7 = 7-line height
$paneCmd = "pwsh -NoProfile -File `"$PANE_SCRIPT`" `"$SESSION_ID`""
& psmux split-window -t $TMUX_SESSION -v -l 7 -b $paneCmd

# 4. Bottom pane (.1): Claude Code
#    Build command string — single-quote each arg for PowerShell safety
$claudeCmd = if ($claudeArgs.Count -gt 0) {
    "claude " + (($claudeArgs | ForEach-Object { "'$($_ -replace "'", "''"  )'" }) -join " ")
} else {
    "claude"
}
& psmux send-keys -t "${TMUX_SESSION}.1" $claudeCmd Enter

# 5. Set destroy-unattached (best-effort — option may not be supported by all psmux versions)
& psmux set-option -t $TMUX_SESSION destroy-unattached on 2>$null

# 6. Attach — when Claude exits, bottom pane closes; session auto-destroys
& psmux attach-session -t $TMUX_SESSION
