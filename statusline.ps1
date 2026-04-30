# brif — Configurable statusline for Claude Code
# https://github.com/balgaly/brif
#
# Installation:
#   1. Copy this file to ~/.claude/statusline.ps1
#   2. Add to ~/.claude/settings.json:
#      { "statusLine": { "type": "command", "command": "powershell -NoProfile -File ~/.claude/statusline.ps1" } }
#
# Configure the options below to customize your statusline.

# ===== CONFIGURATION =====
$CFG_SHOW_GIT          = $true
$CFG_SHOW_WEATHER      = $false
$CFG_SHOW_TOKENS       = $true
$CFG_SHOW_COST         = $true
$CFG_SHOW_LINES        = $true
$CFG_SHOW_SESSION      = $true
$CFG_SHOW_WORKDIR      = $true
$CFG_WEATHER_UNIT      = "C"        # "C" for Celsius, "F" for Fahrenheit
$CFG_CACHE_GIT_SEC     = 5
$CFG_CACHE_WEATHER_SEC = 1800       # 30 minutes
$CFG_PREFIX            = " .  "
$CFG_SEPARATOR         = "  |  "
$CFG_BAR_WIDTH         = 15
$CFG_ACCENT_COLOR      = ""          # Hex color for accent line. Empty = rainbow gradient.
$CFG_STYLE             = "banner"    # "banner" (v2) or "classic" (v1 look)
$CFG_WORKDIR_STYLE     = "worktree"  # "full", "relative", "basename", "worktree"
$CFG_WORKDIR_MAX_LEN   = 40          # Left-truncate workdir past this width
# =========================

# --- Encoding setup (required for emoji / Unicode output) ---
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- ANSI escape codes ---
$ESC     = [char]27
$CYAN    = "$ESC[36m"
$GREEN   = "$ESC[32m"
$YELLOW  = "$ESC[33m"
$RED     = "$ESC[31m"
$MAGENTA = "$ESC[35m"
$DIM     = "$ESC[2m"
$BOLD    = "$ESC[1m"
$RESET   = "$ESC[0m"

# --- Formatted separator and prefix using config ---
$PIPE   = "${DIM}|${RESET}"
$PREFIX = "${DIM}$($CFG_PREFIX.TrimEnd())${RESET}$(' ' * ($CFG_PREFIX.Length - $CFG_PREFIX.TrimEnd().Length))"
# Build the separator string: dim the pipe character in the middle
$sepTrimmed = $CFG_SEPARATOR.Trim()
$sepPadLeft  = $CFG_SEPARATOR.Length - $CFG_SEPARATOR.TrimStart().Length
$sepPadRight = $CFG_SEPARATOR.Length - $CFG_SEPARATOR.TrimEnd().Length
$SEP = (' ' * $sepPadLeft) + "${DIM}${sepTrimmed}${RESET}" + (' ' * $sepPadRight)

# --- Read JSON from stdin ---
$rawInput = $input | Out-String
$data = $rawInput | ConvertFrom-Json

# --- Extract fields with safe fallbacks ---
# Model name: prefer display_name, fall back to extracting from model ID
$rawModel = ""
if ($data.model.display_name) {
    $rawModel = $data.model.display_name
} elseif ($data.model.id) {
    $rawModel = $data.model.id
} elseif ($data.model -is [string]) {
    $rawModel = $data.model
} else {
    $rawModel = "Unknown"
}
# Shorten long model IDs: "global.anthropic.claude-opus-4-6-v1" → "Opus 4.6"
$model = $rawModel
if ($model -match 'claude[- ]?(opus|sonnet|haiku)[- ]?(\d+)[- .]?(\d+)?') {
    $mName = (Get-Culture).TextInfo.ToTitleCase($Matches[1])
    $mVer  = if ($Matches[3]) { "$($Matches[2]).$($Matches[3])" } else { $Matches[2] }
    $model = "$mName $mVer"
}
$modelId = if ($data.model.id) { $data.model.id } elseif ($data.model -is [string]) { $data.model } else { "" }
$cwd        = if ($data.workspace.current_dir) { $data.workspace.current_dir } elseif ($data.cwd) { $data.cwd } else { "" }
$projectDir = if ($data.workspace.project_dir) { $data.workspace.project_dir } else { "" }
$dirname    = if ($cwd) { Split-Path $cwd -Leaf } else { "~" }

$pct        = if ($null -ne $data.context_window.used_percentage) { [int]$data.context_window.used_percentage } else { 0 }
$remaining  = if ($null -ne $data.context_window.remaining_percentage) { [int]$data.context_window.remaining_percentage } else { 100 }
$ctxSize    = if ($data.context_window.context_window_size) { $data.context_window.context_window_size } else { 200000 }

$cost       = if ($null -ne $data.cost.total_cost_usd) { $data.cost.total_cost_usd } else { 0 }
$durationMs = if ($null -ne $data.cost.total_duration_ms) { $data.cost.total_duration_ms } else { 0 }
$apiMs      = if ($null -ne $data.cost.total_api_duration_ms) { $data.cost.total_api_duration_ms } else { 0 }
$linesAdded   = if ($null -ne $data.cost.total_lines_added) { $data.cost.total_lines_added } else { 0 }
$linesRemoved = if ($null -ne $data.cost.total_lines_removed) { $data.cost.total_lines_removed } else { 0 }

$version    = if ($data.version) { $data.version } else { "" }
$style      = if ($data.output_style.name) { $data.output_style.name } else { "" }
$vimMode    = if ($data.vim.mode) { $data.vim.mode } else { "" }
$agentName  = if ($data.agent.name) { $data.agent.name } else { "" }
$worktree   = if ($data.worktree.name) { $data.worktree.name } else { "" }
$sessionId  = if ($data.session_id) { $data.session_id.Substring(0, [Math]::Min(8, $data.session_id.Length)) } else { "" }

# --- Git info (cached to temp file) ---
$gitRepo      = ""
$gitBranch    = ""
$gitStaged    = 0
$gitModified  = 0
$gitUntracked = 0

if ($CFG_SHOW_GIT) {
    # Resolve session cwd — the directory Claude Code is working in, not $PWD
    $gitWorkDir = if ($cwd) { $cwd } elseif ($projectDir) { $projectDir } else { $null }

    # Per-directory cache key (MD5 of absolute path) — switching projects invalidates cache
    $cacheDir = "$env:TEMP\brif-git-cache"
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
    $pathForHash = if ($gitWorkDir) { $gitWorkDir } else { "unknown" }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($pathForHash))
    $dirKey = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').Substring(0, 12).ToLower()
    $cacheFile   = Join-Path $cacheDir $dirKey
    $cacheMaxAge = $CFG_CACHE_GIT_SEC

    $cacheStale = $true
    if (Test-Path $cacheFile) {
        $age = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
        if ($age.TotalSeconds -le $cacheMaxAge) { $cacheStale = $false }
    }

    if ($cacheStale) {
        try {
            # Run git against the session cwd, not the process cwd
            if ($gitWorkDir -and (Test-Path $gitWorkDir)) {
                $null = git -C "$gitWorkDir" rev-parse --git-dir 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $repoRoot  = git -C "$gitWorkDir" rev-parse --show-toplevel 2>$null
                    $repoName  = if ($repoRoot) { Split-Path $repoRoot -Leaf } else { "" }
                    $branch    = git -C "$gitWorkDir" branch --show-current 2>$null
                    $staged    = (git -C "$gitWorkDir" diff --cached --numstat 2>$null | Measure-Object -Line).Lines
                    $modified  = (git -C "$gitWorkDir" diff --numstat 2>$null | Measure-Object -Line).Lines
                    $untracked = (git -C "$gitWorkDir" ls-files --others --exclude-standard 2>$null | Measure-Object -Line).Lines
                    "$repoName|$branch|$staged|$modified|$untracked" | Out-File -FilePath $cacheFile -NoNewline
                } else {
                    "||||" | Out-File -FilePath $cacheFile -NoNewline
                }
            } else {
                "||||" | Out-File -FilePath $cacheFile -NoNewline
            }
        } catch {
            "||||" | Out-File -FilePath $cacheFile -NoNewline
        }
    }

    $cached = (Get-Content $cacheFile -Raw).Split('|')
    if ($cached.Count -ge 5) {
        $gitRepo      = $cached[0]
        $gitBranch    = $cached[1]
        $gitStaged    = [int]($cached[2])
        $gitModified  = [int]($cached[3])
        $gitUntracked = [int]($cached[4])
    }
}

# --- Weather + location (cached, configurable interval) ---
$weatherInfo = ""

if ($CFG_SHOW_WEATHER) {
    $weatherCache  = "$env:TEMP\brif-weather-cache"
    $weatherMaxAge = $CFG_CACHE_WEATHER_SEC

    $weatherStale = $true
    if (Test-Path $weatherCache) {
        $wAge = (Get-Date) - (Get-Item $weatherCache).LastWriteTime
        if ($wAge.TotalSeconds -le $weatherMaxAge) { $weatherStale = $false }
    }

    if ($weatherStale) {
        try {
            # wttr.in: &m = metric (Celsius), &u = USCS (Fahrenheit)
            $unitParam = if ($CFG_WEATHER_UNIT -eq "F") { "&u" } else { "&m" }
            $wResp = Invoke-RestMethod -Uri "https://wttr.in/?format=%c|%t${unitParam}" -TimeoutSec 3 -ErrorAction Stop
            $gResp = Invoke-RestMethod -Uri "https://ip-api.com/json/?fields=countryCode,city" -TimeoutSec 3 -ErrorAction Stop
            $cc   = if ($gResp.countryCode) { $gResp.countryCode } else { "" }
            $city = if ($gResp.city) { $gResp.city } else { "" }
            $wResp = $wResp.Trim()
            "${wResp}|${cc}|${city}" | Out-File -FilePath $weatherCache -NoNewline -Encoding utf8
        } catch {
            if (-not (Test-Path $weatherCache)) {
                "" | Out-File -FilePath $weatherCache -NoNewline -Encoding utf8
            }
        }
    }

    if (Test-Path $weatherCache) {
        $weatherRaw = (Get-Content $weatherCache -Raw -Encoding utf8).Trim()
        if ($weatherRaw) {
            $wParts = $weatherRaw.Split('|')
            if ($wParts.Count -ge 4) {
                $wIcon = $wParts[0].Trim()
                $wTemp = $wParts[1].Trim()
                $cc    = $wParts[2].Trim()
                $city  = $wParts[3].Trim()

                # Country code as bold text badge (flag emojis don't render on Windows Terminal)
                $ccUp = $cc.ToUpper()
                $flag = if ($ccUp) { "${BOLD}${ccUp}${RESET}" } else { "" }

                # Day/night icon using ConvertFromUtf32 for reliable emoji rendering
                $hour = (Get-Date).Hour
                $sun  = [char]::ConvertFromUtf32(0x2600)   # sun
                $moon = [char]::ConvertFromUtf32(0x1F319)  # crescent moon
                $timeIcon = if ($hour -ge 6 -and $hour -lt 20) { $sun } else { $moon }

                # Strip degree symbol — corrupts through Git Bash pipe encoding
                $wTemp = $wTemp -replace '\u00B0', '' -replace '\u00C2', ''
                $weatherInfo = "${flag} ${timeIcon} ${wTemp}"
            }
        }
    }
}

# --- Helper: format token counts ---
function FmtK($n) {
    if ($n -ge 1000) { "{0:N1}K" -f ($n / 1000) } else { "$n" }
}

# --- Helper: word-boundary truncation. Cuts at last space before $max, appends … ---
function Truncate-ToWidth([string]$text, [int]$max) {
    if ([string]::IsNullOrEmpty($text) -or $max -le 1) { return $text }
    if ($text.Length -le $max) { return $text }
    $cut = $max - 1
    $idx = $text.LastIndexOf(' ', [Math]::Min($cut, $text.Length - 1))
    if ($idx -lt 1) { return $text.Substring(0, $cut) + [char]0x2026 }
    return $text.Substring(0, $idx).TrimEnd() + [char]0x2026
}

# --- Build output lines ---
$outputLines = @()

$projDir = if ($projectDir) { $projectDir } elseif ($cwd) { $cwd } else { "~" }

# Progress bar
if ($pct -ge 90)     { $barColor = $RED }
elseif ($pct -ge 70) { $barColor = $YELLOW }
else                  { $barColor = $GREEN }

$filled = [Math]::Floor($pct * $CFG_BAR_WIDTH / 100)
$empty  = $CFG_BAR_WIDTH - $filled
$bar    = ("=" * $filled) + ("-" * $empty)
$ctxLabel = if ($ctxSize -ge 1000000) { "1M" } else { "$([Math]::Floor($ctxSize / 1000))K" }

# Cost + duration
$costStr = ""
if ($CFG_SHOW_COST) {
    $costFmt  = '$' + ("{0:N2}" -f $cost)
    $totalSec = [Math]::Floor($durationMs / 1000)
    $hours    = [Math]::Floor($totalSec / 3600)
    $mins     = [Math]::Floor(($totalSec % 3600) / 60)
    $durStr   = if ($hours -gt 0) { "${hours}h${mins}m" } else { "${mins}m" }
    $costStr  = "${YELLOW}${costFmt}${RESET} ${DIM}${durStr}${RESET}"
}

# Git
$gitStr = ""
if ($CFG_SHOW_GIT -and $gitBranch) {
    $gitStr = "${MAGENTA}$gitBranch${RESET}"
    $indicators = @()
    if ($gitStaged -gt 0)    { $indicators += "${GREEN}+$gitStaged${RESET}" }
    if ($gitModified -gt 0)  { $indicators += "${YELLOW}~$gitModified${RESET}" }
    if ($gitUntracked -gt 0) { $indicators += "${RED}?$gitUntracked${RESET}" }
    if ($indicators.Count -gt 0) { $gitStr += " " + ($indicators -join " ") }
}

# ===== LINE 1: folder/repo  [Model]  branch +s ~m  [===---] 42%/200K  $0.42  2m 0s =====
# Folder or repo name prefix (repo name wins when inside a git dir, falls back to cwd basename)
$locationName = ""
if ($gitRepo) {
    $locationName = $gitRepo
} elseif ($cwd) {
    $locationName = Split-Path $cwd -Leaf
}

# Workdir suffix: optional path fragment rendered after location_name.
# Disambiguates multiple git worktrees of the same repo (which share repo_name).
$workdirSuffix = ""
if ($CFG_SHOW_WORKDIR -and $cwd) {
    $rawDir  = $cwd
    $wdBase  = Split-Path $rawDir -Leaf

    # ~-relative form — match bash behavior, normalize to forward slashes so
    # the $HOME prefix match is insensitive to slash direction.
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $rawFwd  = $rawDir  -replace '\\', '/'
    $homeFwd = if ($homeDir) { $homeDir -replace '\\', '/' } else { '' }
    $relDir  = $rawFwd
    if ($homeFwd -and $rawFwd.StartsWith($homeFwd, [StringComparison]::OrdinalIgnoreCase)) {
        $relDir = '~' + $rawFwd.Substring($homeFwd.Length)
    }

    switch ($CFG_WORKDIR_STYLE) {
        "full"     { $workdirSuffix = ($rawDir -replace '\\', '/') }
        "relative" { $workdirSuffix = $relDir }
        "basename" { $workdirSuffix = $wdBase }
        default {
            # "worktree": show basename only when it differs from the location name
            if ($locationName -and $wdBase -and $wdBase -ne $locationName) {
                $workdirSuffix = $wdBase
            }
        }
    }

    # Left-truncate (preserve worktree-specific tail) if longer than max
    if ($workdirSuffix -and $workdirSuffix.Length -gt $CFG_WORKDIR_MAX_LEN) {
        $keep = [Math]::Max(1, $CFG_WORKDIR_MAX_LEN - 1)
        $workdirSuffix = [char]0x2026 + $workdirSuffix.Substring($workdirSuffix.Length - $keep)
    }
}

$line1Parts = @()
if ($locationName) {
    $loc = "${BOLD}${locationName}${RESET}"
    if ($workdirSuffix) {
        $loc += "${DIM} $([char]0x25B8) ${workdirSuffix}${RESET}"
    }
    $line1Parts += $loc
} elseif ($workdirSuffix) {
    $line1Parts += "${DIM}${workdirSuffix}${RESET}"
}
$line1Parts += "${BOLD}${CYAN}[$model]${RESET}"
if ($gitStr) { $line1Parts += $gitStr }
$line1Parts += "${barColor}[${bar}]${RESET} ${barColor}${pct}%${RESET}/${ctxLabel}"
if ($costStr) { $line1Parts += $costStr }

# Right-side badges
$badges = @()
if ($agentName) { $badges += "${MAGENTA}[$agentName]${RESET}" }
if ($worktree)  { $badges += "${CYAN}[wt:$worktree]${RESET}" }
$line1 = ($line1Parts -join "  ")
if ($badges.Count -gt 0) { $line1 += "  " + ($badges -join " ") }
$outputLines += $line1

# ===== LINE 2: tokens  |  +added -removed  |  weather  |  #session =====
$line2Parts = @()

if ($CFG_SHOW_TOKENS) {
    $curInput  = if ($null -ne $data.context_window.current_usage.input_tokens) { $data.context_window.current_usage.input_tokens } else { 0 }
    $curOutput = if ($null -ne $data.context_window.current_usage.output_tokens) { $data.context_window.current_usage.output_tokens } else { 0 }
    $curCache  = if ($null -ne $data.context_window.current_usage.cache_read_input_tokens) { $data.context_window.current_usage.cache_read_input_tokens } else { 0 }
    $tokParts = @("${CYAN}$(FmtK $curInput) in${RESET}", "${MAGENTA}$(FmtK $curOutput) out${RESET}")
    if ($curCache -gt 0) { $tokParts += "${GREEN}$(FmtK $curCache) hit${RESET}" }
    $line2Parts += ($tokParts -join "  ")
}

if ($CFG_SHOW_LINES) {
    $line2Parts += "${GREEN}+${linesAdded}${RESET} ${RED}-${linesRemoved}${RESET}"
}

if ($CFG_SHOW_WEATHER -and $weatherInfo) {
    $line2Parts += $weatherInfo
}

if ($CFG_SHOW_SESSION -and $sessionId) {
    $line2Parts += "#${sessionId}"
}

if ($line2Parts.Count -gt 0) {
    $outputLines += "${DIM} .${RESET}  " + ($line2Parts -join $SEP)
}

# ===== LINE 3: brif mission line =====
# Prefer BRIF_SESSION_ID-specific dir; fall back to 'current' for plain 'claude' sessions
$missionFile = $null
if ($env:BRIF_SESSION_ID -and $env:BRIF_SESSION_ID -match '^[a-zA-Z0-9._-]+$') {
    $candidate = "$env:USERPROFILE\.claude\brif\$($env:BRIF_SESSION_ID)\mission.json"
    if (Test-Path $candidate) { $missionFile = $candidate }
}
if (-not $missionFile) {
    $candidate = "$env:USERPROFILE\.claude\brif\current\mission.json"
    if (Test-Path $candidate) {
        # Only use current/ if it belongs to this session
        $sessionIdFile = "$env:USERPROFILE\.claude\brif\current\.session_id"
        $currentOwner  = if (Test-Path $sessionIdFile) { (Get-Content $sessionIdFile -Raw).Trim() } else { "" }
        $mySessionId   = if ($data.session_id) { $data.session_id } else { "" }
        if (-not $currentOwner -or -not $mySessionId -or $currentOwner -eq $mySessionId) {
            $missionFile = $candidate
        }
    }
}
if ($missionFile) {
    try {
            $m = Get-Content $missionFile -Raw -Encoding utf8 | ConvertFrom-Json
            $goal    = $(if ($m.goal)     { $m.goal }     else { "" })
            $summary = $(if ($m.summary)  { $m.summary }  else { "" })
            $mDone   = $(if ($null -ne $m.progress) { @($m.progress).Count } else { 0 })
            $mRem    = $(if ($null -ne $m.remaining) { @($m.remaining).Count } else { 0 })
            $mTotal  = $mDone + $mRem
            $mStatus = $(if ($m.status)   { $m.status }   else { "active" })
            $pending = $(if ($m.pending)  { $m.pending }  else { "" })

            # Terminal width for truncation (fallback 80 if unavailable)
            $termWidth = 80
            try {
                $w = $Host.UI.RawUI.WindowSize.Width
                if ($w -and $w -gt 0) { $termWidth = $w }
            } catch {}

            if ($goal) {
                # Progress bar
                $mFilled = $(if ($mTotal -gt 0) { [Math]::Floor($mDone * 10 / $mTotal) } else { 0 })
                $mBar    = ("=" * $mFilled) + ("-" * (10 - $mFilled))

                # Status badge
                $statusBadge = switch ($mStatus) {
                    "waiting_approval" { "${YELLOW}APPROVE${RESET}" }
                    "blocked"          { "${RED}BLOCKED${RESET}" }
                    "idle"             { "IDLE" }
                    default            { "" }
                }

                # Visible overhead on the goal line: " | " (3) + "  [==========] 10/10" (~20)
                # + badge (~8). Leave ~35 chars of headroom for the goal text itself.
                $goalOverhead = 3
                if ($mTotal -gt 0) { $goalOverhead += 17 }
                if ($statusBadge)  { $goalOverhead += 9 }
                $goalMax = [Math]::Max(10, $termWidth - $goalOverhead)
                $goalDisplay = Truncate-ToWidth $goal $goalMax

                $mLine = " | ${goalDisplay}"
                if ($mTotal -gt 0) { $mLine += "  [${mBar}] ${mDone}/${mTotal}" }
                if ($statusBadge)  { $mLine += "  ${statusBadge}" }
                if ($pending -and $mStatus -eq "waiting_approval") { $mLine += "  ${DIM}${pending}${RESET}" }
                $outputLines += $mLine
            }

            # Recent activity sentence — suppressed below 50 cols (too narrow)
            if ($summary -and $termWidth -ge 50) {
                # Overhead: " | " (3) + "recent  " (8) = 11
                $recentMax = [Math]::Max(10, $termWidth - 11)
                $recentDisplay = Truncate-ToWidth $summary $recentMax
                $outputLines += " | ${BOLD}recent${RESET}  ${recentDisplay}"
            }
    } catch { <# silently skip on bad json #> }
}

# --- Final output ---
foreach ($line in $outputLines) {
    Write-Host $line
}

# --- Accent line (disabled by default — set CFG_STYLE="banner" and increase padding to enable) ---
# Uncomment below if your terminal has enough status area height for the gradient line.
# if ($CFG_STYLE -eq "banner") {
#     $width = $Host.UI.RawUI.WindowSize.Width
#     $gradient = ""
#     $half = [math]::Floor($width / 2)
#     for ($i = 0; $i -lt $width; $i++) {
#         if ($i -lt $half) {
#             $r = [math]::Round(99 + (255 - 99) * $i / $half)
#             $g = [math]::Round(102 + (68 - 102) * $i / $half)
#             $b = [math]::Round(241 + (204 - 241) * $i / $half)
#         } else {
#             $j = $i - $half
#             $half2 = $width - $half
#             $r = [math]::Round(255 + (0 - 255) * $j / $half2)
#             $g = [math]::Round(68 + (212 - 68) * $j / $half2)
#             $b = [math]::Round(204 + (255 - 204) * $j / $half2)
#         }
#         $gradient += "$([char]27)[38;2;${r};${g};${b}m$([char]::ConvertFromUtf32(0x2501))"
#     }
#     Write-Host "${gradient}$([char]27)[0m"
# }

# --- Metrics sidecar: Write brif metrics.json if session is active ---
if ($env:BRIF_SESSION_ID) {
    if ($env:BRIF_SESSION_ID -notmatch '^[a-zA-Z0-9._-]+$') { exit }
    $metricsDir = "$env:USERPROFILE\.claude\brif\$($env:BRIF_SESSION_ID)"
    if (Test-Path $metricsDir) {
        # Reuse $gitBranch populated during line 1 git fetch — avoids a second fork
        $currentBranch = if ($gitBranch) { $gitBranch } else { "" }

        $metrics = @{
            context_pct = $pct
            cost_usd = $cost
            duration_ms = $durationMs
            project_dir = $projDir
            branch = $currentBranch
        } | ConvertTo-Json -Compress

        $tmpFile = "$metricsDir\metrics.json.tmp"
        $finalFile = "$metricsDir\metrics.json"
        $metrics | Out-File -FilePath $tmpFile -NoNewline -Encoding utf8
        Move-Item -Path $tmpFile -Destination $finalFile -Force
    }
}
