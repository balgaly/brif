#!/usr/bin/env pwsh
# brif.ps1 — launcher for Claude Code with mission context top pane (Windows / psmux)
#
# Usage (positional, back-compat):
#   .\brif.ps1 [claude-code-args...]
#   .\brif.ps1 --resume <session-id> [claude-code-args...]
#
# Usage (launch contract — used by the tmax `ws` launcher):
#   .\brif.ps1 -Path <abs-project-path> -SessionName <safe-name> [-ClaudeArgs <args...>]
#     -Path        absolute project directory; psmux session starts here (-c start-dir)
#     -SessionName deterministic psmux session name computed by ws (e.g.
#                  tmax_<leaf>_<8hex>). If a session with this name already
#                  exists, attach to it; otherwise start a new one.
#     -ClaudeArgs  args forwarded verbatim to `claude`
#
# Requires: psmux (winget install marlocarlo.psmux), Claude Code CLI
# Mirrors the Unix `brif` bash launcher for native Windows PowerShell + psmux.
# Run from PowerShell — psmux must be on PATH.

param(
    [string]$Path,
    [string]$SessionName,
    [string[]]$ClaudeArgs,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

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

# --- Mode detection: launch contract vs legacy positional ---
# Contract mode is active when -SessionName is supplied (by the ws launcher).
$ContractMode = [bool]$SessionName

# --- Build claude args + session identity per mode ---
$claudeArgs = @()

if ($ContractMode) {
    # ws passes a deterministic psmux session name; mission session ID derives from it.
    # Sanitize SessionName for psmux target safety (psmux/tmux session names cannot
    # contain ':' or '.'; keep to a conservative safe set).
    $TMUX_SESSION = ($SessionName -replace '[^a-zA-Z0-9._\-]', '_')

    # Mission session-dir ID: reuse the psmux name (already unique per path via ws hash),
    # capped/sanitized to the brif dir-key charset.
    $SESSION_ID = ($SessionName -replace '[^a-zA-Z0-9._\-]', '_')

    # ClaudeArgs (named) take precedence; fall back to any remaining positional args.
    if ($ClaudeArgs)    { $claudeArgs += $ClaudeArgs }
    if ($RemainingArgs) { $claudeArgs += $RemainingArgs }
} else {
    # --- Legacy positional mode ---
    # Default mission ID: brif-<8 hex chars> derived from current time hash
    $timestamp  = [DateTimeOffset]::Now.ToUnixTimeMilliseconds().ToString()
    $hashBytes  = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                      [System.Text.Encoding]::UTF8.GetBytes($timestamp))
    $SESSION_ID = "brif-" + (($hashBytes | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 8)

    # Honor --resume <id>: sanitize to [a-zA-Z0-9._-], max 8 chars
    $posArgs = @($RemainingArgs)
    $i = 0
    while ($i -lt $posArgs.Count) {
        if ($posArgs[$i] -eq "--resume" -and ($i + 1) -lt $posArgs.Count) {
            $rawId      = $posArgs[$i + 1]
            $cleanId    = ($rawId -replace '[^a-zA-Z0-9._\-]', '')
            $cleanId    = $cleanId.Substring(0, [Math]::Min(8, $cleanId.Length))
            $SESSION_ID = "brif-$cleanId"
            $i += 2
        } else {
            $claudeArgs += $posArgs[$i]
            $i++
        }
    }

    # psmux session name (unique per PID) — legacy behavior
    $TMUX_SESSION = "brif-$PID"
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

# --- Attach-vs-start: if the psmux session already exists, just attach ---
# Identity is the session NAME (computed deterministically by ws from the path),
# checked via has-session exit code — never by parsing `psmux ls` text.
& psmux has-session -t $TMUX_SESSION 2>$null
if ($LASTEXITCODE -eq 0) {
    & psmux attach-session -t $TMUX_SESSION
    exit $LASTEXITCODE
}

# --- Terminal size ---
$cols  = $Host.UI.RawUI.WindowSize.Width
$lines = $Host.UI.RawUI.WindowSize.Height

# --- Launch psmux ---

# 1. Create detached session (start in -Path when supplied via the launch contract)
if ($ContractMode -and $Path) {
    & psmux new-session -d -s $TMUX_SESSION -x $cols -y $lines -c $Path
} else {
    & psmux new-session -d -s $TMUX_SESSION -x $cols -y $lines
}

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
