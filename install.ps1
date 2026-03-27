# ============================================================================
# brif Installer for Windows (PowerShell)
# ============================================================================
# Installs the statusline.ps1 script and configures Claude Code to use it.
#
# One-liner install:
#   irm https://raw.githubusercontent.com/balgaly/brif/main/install.ps1 | iex
#
# What this script does:
#   1. Downloads statusline.ps1 to ~/.claude/statusline.ps1
#   2. Adds the statusLine configuration to ~/.claude/settings.json
#   3. Preserves any existing settings in settings.json
# ============================================================================

$ErrorActionPreference = "Stop"

# --- Color helpers ---
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Info     { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }

# --- Configuration ---
$RepoBase     = "https://raw.githubusercontent.com/balgaly/brif/main"
$ClaudeDir    = Join-Path $HOME ".claude"
$BrifDir      = Join-Path $ClaudeDir "brif"
$BrifHooksDir = Join-Path $ClaudeDir "brif-hooks"
$ScriptDest   = Join-Path $ClaudeDir "statusline.ps1"
$SettingsFile = Join-Path $ClaudeDir "settings.json"
$ClaudeMd     = Join-Path $ClaudeDir "CLAUDE.md"

$StatusLineValue = @{
    type    = "command"
    command = "powershell -NoProfile -File ~/.claude/statusline.ps1"
}

# Brif files to download (source -> destination)
$BrifFiles = @(
    @{ Src = "brif.ps1";                  Dest = (Join-Path $ClaudeDir "brif-launcher.ps1") }
    @{ Src = "brif-pane.ps1";             Dest = (Join-Path $ClaudeDir "brif-pane.ps1") }
    @{ Src = "hooks/post-tool-use.ps1";   Dest = (Join-Path $BrifHooksDir "post-tool-use.ps1") }
    @{ Src = "hooks/user-prompt.ps1";     Dest = (Join-Path $BrifHooksDir "user-prompt.ps1") }
    @{ Src = "claude-md-snippet.md";      Dest = (Join-Path $ClaudeDir "brif-claude-md-snippet.md") }
)

# --- Main ---
Write-Info "brif installer for Windows"
Write-Info "=========================================="
Write-Host ""

# Step 1: Ensure ~/.claude/ directory exists
if (-not (Test-Path $ClaudeDir)) {
    New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    Write-Success "Created directory: $ClaudeDir"
} else {
    Write-Info "Directory already exists: $ClaudeDir"
}

# Step 2: Download statusline.ps1
$DownloadUrl = "$RepoBase/statusline.ps1"
Write-Info "Downloading statusline.ps1 from $DownloadUrl ..."

if (Test-Path $ScriptDest) {
    Write-Warn "Existing statusline.ps1 found at $ScriptDest -- it will be overwritten."
}

try {
    Invoke-RestMethod -Uri $DownloadUrl -OutFile $ScriptDest
    Write-Success "Downloaded statusline.ps1 to $ScriptDest"
} catch {
    Write-Error "Failed to download statusline.ps1: $_"
    exit 1
}

# Step 2b: Download brif files
Write-Info "Downloading brif files ..."
New-Item -ItemType Directory -Path $BrifDir -Force | Out-Null
New-Item -ItemType Directory -Path $BrifHooksDir -Force | Out-Null

foreach ($file in $BrifFiles) {
    $url = "$RepoBase/$($file.Src)"
    Write-Info "  $($file.Src) -> $($file.Dest)"
    try {
        Invoke-RestMethod -Uri $url -OutFile $file.Dest
    } catch {
        Write-Warn "Failed to download $($file.Src): $_"
    }
}
Write-Success "Downloaded brif files"

# Step 3: Read or create settings.json
if (Test-Path $SettingsFile) {
    Write-Info "Reading existing settings from $SettingsFile ..."
    try {
        $settingsRaw = Get-Content -Path $SettingsFile -Raw -ErrorAction Stop
        $settings = $settingsRaw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warn "Could not parse existing settings.json. Backing up and starting fresh."
        $backupPath = "$SettingsFile.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $SettingsFile -Destination $backupPath
        Write-Warn "Backup saved to $backupPath"
        $settings = New-Object PSObject
    }
} else {
    Write-Info "No settings.json found -- creating a new one."
    $settings = New-Object PSObject
}

# Step 4: Add/update the statusLine entry (merge, do not overwrite)
$statusLineObj = [PSCustomObject]$StatusLineValue

if ($null -ne $settings.statusLine) {
    Write-Warn "Existing statusLine configuration found -- updating it."
} else {
    Write-Info "Adding statusLine configuration ..."
}

# If the settings object already has a statusLine property, update it; otherwise add it
if ($settings.PSObject.Properties.Match("statusLine").Count -gt 0) {
    $settings.statusLine = $statusLineObj
} else {
    $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $statusLineObj
}

# Step 5: Write settings.json back (pretty-printed) — after adding hooks
# Add hooks configuration
Write-Info "Configuring brif hooks ..."

if (-not $settings.PSObject.Properties.Match("hooks").Count) {
    $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{})
}

$postToolCmd = "powershell -NoProfile -File ~/.claude/brif-hooks/post-tool-use.ps1"
$promptCmd   = "powershell -NoProfile -File ~/.claude/brif-hooks/user-prompt.ps1"

# PostToolUse hooks
if (-not $settings.hooks.PSObject.Properties.Match("PostToolUse").Count) {
    $settings.hooks | Add-Member -NotePropertyName "PostToolUse" -NotePropertyValue @()
}
$existing = @($settings.hooks.PostToolUse | Where-Object { $_.command -eq $postToolCmd })
if ($existing.Count -eq 0) {
    $settings.hooks.PostToolUse = @($settings.hooks.PostToolUse) + @([PSCustomObject]@{ type = "command"; command = $postToolCmd })
}

# UserPromptSubmit hooks
if (-not $settings.hooks.PSObject.Properties.Match("UserPromptSubmit").Count) {
    $settings.hooks | Add-Member -NotePropertyName "UserPromptSubmit" -NotePropertyValue @()
}
$existing = @($settings.hooks.UserPromptSubmit | Where-Object { $_.command -eq $promptCmd })
if ($existing.Count -eq 0) {
    $settings.hooks.UserPromptSubmit = @($settings.hooks.UserPromptSubmit) + @([PSCustomObject]@{ type = "command"; command = $promptCmd })
}

# Add brif write permission
if (-not $settings.PSObject.Properties.Match("permissions").Count) {
    $settings | Add-Member -NotePropertyName "permissions" -NotePropertyValue ([PSCustomObject]@{})
}
if (-not $settings.permissions.PSObject.Properties.Match("allow").Count) {
    $settings.permissions | Add-Member -NotePropertyName "allow" -NotePropertyValue @()
}
$brifPerm = "Write(~/.claude/brif/**)"
if ($brifPerm -notin @($settings.permissions.allow)) {
    $settings.permissions.allow = @($settings.permissions.allow) + @($brifPerm)
}

$settingsJson = $settings | ConvertTo-Json -Depth 10
Set-Content -Path $SettingsFile -Value $settingsJson -Encoding UTF8
Write-Success "Updated $SettingsFile with statusLine, hooks, and permissions"

# Step 6: Append brif instructions to CLAUDE.md
$SnippetFile = Join-Path $ClaudeDir "brif-claude-md-snippet.md"
if (Test-Path $SnippetFile) {
    $hasSnippet = $false
    if (Test-Path $ClaudeMd) {
        $hasSnippet = (Get-Content -Path $ClaudeMd -Raw -ErrorAction SilentlyContinue) -match "brif - Mission Context"
    }
    if ($hasSnippet) {
        Write-Info "CLAUDE.md already contains brif instructions -- skipping."
    } else {
        Write-Info "Appending brif instructions to CLAUDE.md ..."
        $snippet = Get-Content -Path $SnippetFile -Raw
        Add-Content -Path $ClaudeMd -Value "`n$snippet"
        Write-Success "Updated $ClaudeMd"
    }
    Remove-Item -Path $SnippetFile -Force
}

# Step 7: Success message
Write-Host ""
Write-Success "============================================"
Write-Success "  brif installed successfully!"
Write-Success "============================================"
Write-Host ""
Write-Info "The status line will appear next time you start Claude Code."
Write-Info "To customize, edit: $ScriptDest"
Write-Info "Settings stored in: $SettingsFile"
Write-Host ""
Write-Info "brif (mission dashboard) installed. Launch with:"
Write-Info "  powershell -File ~/.claude/brif-launcher.ps1"
Write-Host ""
