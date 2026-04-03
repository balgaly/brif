# Changelog

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
