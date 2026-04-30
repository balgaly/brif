# Changelog

## Unreleased

### Features
- Add optional workdir display on line 1 of the statusline
  (`CFG_SHOW_WORKDIR`, `CFG_WORKDIR_STYLE`, `CFG_WORKDIR_MAX_LEN`). Four
  styles: `full`, `relative`, `basename`, `worktree` (default). The
  `worktree` style renders the cwd basename only when it differs from the
  repo name, disambiguating sibling git worktrees of the same repo. Long
  paths are left-truncated with `…` so the worktree-specific tail is
  preserved.

## v1.0.1 — 2026-04-13

### Security
- Fix command injection via `--resume` argument in `brif` launcher (SESSION_ID
  sanitized; passed to tmux via `set-environment` instead of inline shell string)
- Fix directory traversal in `brif-pane.sh` and `brif-pane.ps1`: SESSION_ID
  now validated against `^[a-zA-Z0-9._-]+$` before use in file paths
- Upgrade ip-api.com geolocation fetch from HTTP to HTTPS in `statusline.sh`
  and `statusline.ps1`
- Replace `printf '%b'` with `printf '%s'` in `statusline.sh` (ANSI constants
  converted to `$'\033'`) — prevents terminal-escape injection from
  user-controlled strings such as directory names and git branch names
- Add `chmod 700` on all brif session directories (`install.sh`, `brif`,
  `hooks/post-tool-use.sh`, `hooks/user-prompt.sh`) to protect `events.jsonl`
  (which logs full user prompt text) on multi-user systems
- Write initial `mission.json` atomically via `.tmp` + `mv` in `brif` launcher

## v1.0.0 — 2026-04-03

### Features
- Compact 2-line statusline: model, branch, context bar, cost, duration on line 1; tokens, lines changed, session ID on line 2
- Smart model name extraction (`global.anthropic.claude-opus-4-6-v1` → `Opus 4.6`)
- Hours-aware duration formatting (`84h33m` for long sessions)
- brif mission line: shows current goal + ASCII progress bar when `BRIF_SESSION_ID` is set
- PowerShell and Bash versions with encoding-safe ASCII progress bars on Windows
- tmux pane renderer (`brif-pane.sh`) with active/ambient modes
- Event hooks for PostToolUse and UserPromptSubmit

### Security
- awk variable injection hardening
- eval removed from JSON parsing in pane renderer
- Session ID validation against allowlist pattern
- Per-user cache directories (no shared /tmp)
- Weather fetching opt-in by default
