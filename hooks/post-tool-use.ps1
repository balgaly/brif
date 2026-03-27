#!/usr/bin/env pwsh
# brif hook: PostToolUse — captures tool events to events.jsonl
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$sessionId = $env:BRIF_SESSION_ID
if (-not $sessionId) {
    $pid = [System.Diagnostics.Process]::GetCurrentProcess().Id
    $ppid = (Get-CimInstance Win32_Process -Filter "ProcessId = $pid").ParentProcessId
    $sessionId = "auto-$pid-$ppid"
}

$sessionDir = Join-Path $HOME ".claude\brif\$sessionId"
if (-not (Test-Path $sessionDir)) {
    New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null
}

$inputJson = $input | Out-String
if (-not $inputJson -or $inputJson.Trim() -eq '') { exit 0 }

try {
    $inputObj = $inputJson | ConvertFrom-Json
} catch {
    exit 0
}

$toolName = if ($inputObj.tool_name) { $inputObj.tool_name } else { "" }
$filePath = if ($inputObj.file_path) { $inputObj.file_path } else { "" }
$linesAdded = if ($inputObj.lines_added) { $inputObj.lines_added } else { $null }
$linesRemoved = if ($inputObj.lines_removed) { $inputObj.lines_removed } else { $null }

if (-not $toolName) { exit 0 }

$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$event = @{
    ts = $ts
    type = "tool"
    name = $toolName
    target = $filePath
}

if ($null -ne $linesAdded) { $event.lines_added = $linesAdded }
if ($null -ne $linesRemoved) { $event.lines_removed = $linesRemoved }

$eventJson = $event | ConvertTo-Json -Compress
$eventsFile = Join-Path $sessionDir "events.jsonl"
$eventJson | Out-File -Append -FilePath $eventsFile -Encoding utf8 -NoNewline
"`n" | Out-File -Append -FilePath $eventsFile -Encoding utf8 -NoNewline

# Log rotation
if (Test-Path $eventsFile) {
    $fileSize = (Get-Item $eventsFile).Length
    if ($fileSize -gt 512000) {
        $lines = Get-Content $eventsFile -Tail 1000
        $lines | Set-Content $eventsFile -Encoding utf8
    }
}
