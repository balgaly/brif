#!/usr/bin/env pwsh
# brif hook: UserPromptSubmit — captures user prompts to events.jsonl
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$sessionId = $env:BRIF_SESSION_ID

# Try to get the actual Claude session ID from hook input JSON
$inputJson = $input | Out-String
$inputObj  = $null
if ($inputJson -and $inputJson.Trim() -ne '') {
    try { $inputObj = $inputJson | ConvertFrom-Json } catch {}
}
$claudeSessionId = if ($inputObj -and $inputObj.session_id) { $inputObj.session_id } else { $null }

if (-not $sessionId) {
    if ($claudeSessionId -and $claudeSessionId -match '^[a-zA-Z0-9._-]+$') {
        $sessionId = $claudeSessionId
    } else {
        $pid  = [System.Diagnostics.Process]::GetCurrentProcess().Id
        $ppid = (Get-CimInstance Win32_Process -Filter "ProcessId = $pid").ParentProcessId
        $sessionId = "auto-$pid-$ppid"
    }
}

if ($sessionId -notmatch '^[a-zA-Z0-9._-]+$') { exit }

$sessionDir = Join-Path $HOME ".claude\brif\$sessionId"
if (-not (Test-Path $sessionDir)) {
    New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
}

# Ensure 'current' dir exists and stamp it with this session's ID
# so the statusline knows which session owns current/mission.json
$currentDir = Join-Path $HOME ".claude\brif\current"
if (-not (Test-Path $currentDir)) {
    New-Item -ItemType Directory -Path $currentDir -Force | Out-Null
}
$sessionId | Out-File -FilePath (Join-Path $currentDir ".session_id") -Encoding utf8 -NoNewline -Force

if (-not $inputObj) { exit 0 }

$promptText = if ($inputObj.prompt) { $inputObj.prompt } else { "" }

if (-not $promptText) { exit 0 }

$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$event = @{
    ts = $ts
    type = "prompt"
    text = $promptText
} | ConvertTo-Json -Compress

$eventsFile = Join-Path $sessionDir "events.jsonl"
$event | Out-File -Append -FilePath $eventsFile -Encoding utf8 -NoNewline
"`n" | Out-File -Append -FilePath $eventsFile -Encoding utf8 -NoNewline

# Log rotation
if (Test-Path $eventsFile) {
    $fileSize = (Get-Item $eventsFile).Length
    if ($fileSize -gt 512000) {
        $lines = Get-Content $eventsFile -Tail 1000
        $lines | Set-Content $eventsFile -Encoding utf8
    }
}
