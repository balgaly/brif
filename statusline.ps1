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
$CFG_WEATHER_UNIT      = "C"        # "C" for Celsius, "F" for Fahrenheit
$CFG_CACHE_GIT_SEC     = 5
$CFG_CACHE_WEATHER_SEC = 1800       # 30 minutes
$CFG_PREFIX            = " .  "
$CFG_SEPARATOR         = "  |  "
$CFG_BAR_WIDTH         = 15
$CFG_ACCENT_COLOR      = ""        # Hex color for accent line. Empty = rainbow gradient.
$CFG_STYLE             = "banner"  # "banner" (v2) or "classic" (v1 look)
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
    $cacheFile   = "$env:TEMP\brif-git-cache"
    $cacheMaxAge = $CFG_CACHE_GIT_SEC

    $cacheStale = $true
    if (Test-Path $cacheFile) {
        $age = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
        if ($age.TotalSeconds -le $cacheMaxAge) { $cacheStale = $false }
    }

    if ($cacheStale) {
        try {
            $null = git rev-parse --git-dir 2>$null
            if ($LASTEXITCODE -eq 0) {
                $repoRoot  = git rev-parse --show-toplevel 2>$null
                $repoName  = if ($repoRoot) { Split-Path $repoRoot -Leaf } else { "" }
                $branch    = git branch --show-current 2>$null
                $staged    = (git diff --cached --numstat 2>$null | Measure-Object -Line).Lines
                $modified  = (git diff --numstat 2>$null | Measure-Object -Line).Lines
                $untracked = (git ls-files --others --exclude-standard 2>$null | Measure-Object -Line).Lines
                "$repoName|$branch|$staged|$modified|$untracked" | Out-File -FilePath $cacheFile -NoNewline
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
            $gResp = Invoke-RestMethod -Uri "http://ip-api.com/json/?fields=countryCode,city" -TimeoutSec 3 -ErrorAction Stop
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

# ===== LINE 1: [Model]  branch +s ~m  [===---] 42%/200K  $0.42  2m 0s =====
$line1Parts = @("${BOLD}${CYAN}[$model]${RESET}")
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
    $line2Parts += "${DIM}#${sessionId}${RESET}"
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
    if (Test-Path $candidate) { $missionFile = $candidate }
}
if ($missionFile) {
    try {
            $m = Get-Content $missionFile -Raw -Encoding utf8 | ConvertFrom-Json
            $goal    = $(if ($m.goal)     { $m.goal }     else { "" })
            $mDone   = $(if ($null -ne $m.progress) { @($m.progress).Count } else { 0 })
            $mRem    = $(if ($null -ne $m.remaining) { @($m.remaining).Count } else { 0 })
            $mTotal  = $mDone + $mRem
            $mStatus = $(if ($m.status)   { $m.status }   else { "active" })
            $pending = $(if ($m.pending)  { $m.pending }  else { "" })

            if ($goal) {
                # Progress bar
                $mFilled = $(if ($mTotal -gt 0) { [Math]::Floor($mDone * 10 / $mTotal) } else { 0 })
                $mBar    = ("=" * $mFilled) + ("-" * (10 - $mFilled))

                # Status badge
                $statusBadge = switch ($mStatus) {
                    "waiting_approval" { "${YELLOW}APPROVE${RESET}" }
                    "blocked"          { "${RED}BLOCKED${RESET}" }
                    "idle"             { "${DIM}IDLE${RESET}" }
                    default            { "" }
                }

                $mLine = "${DIM} |${RESET} ${goal}"
                if ($mTotal -gt 0) { $mLine += "  ${DIM}[${mBar}]${RESET} ${DIM}${mDone}/${mTotal}${RESET}" }
                if ($statusBadge)  { $mLine += "  ${statusBadge}" }
                if ($pending -and $mStatus -eq "waiting_approval") { $mLine += "  ${DIM}${pending}${RESET}" }
                $outputLines += $mLine
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
        $gitDir = if ($cwd) { $cwd } elseif ($projectDir) { $projectDir } else { "." }
        $currentBranch = ""
        try {
            $currentBranch = git -C $gitDir branch --show-current 2>$null
            if ($LASTEXITCODE -ne 0) { $currentBranch = "" }
        } catch {
            $currentBranch = ""
        }

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
