# brif — development project

## Mission Context

When working on tasks in this project, maintain a mission context file for the brif dashboard.

After the user's first request, and after each meaningful milestone (feature complete, file created, test passed, blocker encountered), update:

```
~/.claude/brif/current/mission.json
```

Schema:
```json
{
  "version": 1,
  "goal": "One-sentence objective for this session",
  "summary": "One sentence (≤15 words) describing what was done in the last ~10 interactions",
  "progress": ["Completed item 1", "Completed item 2"],
  "remaining": ["TODO item 1", "TODO item 2"],
  "status": "active",
  "pending": "What needs user action (only when status is waiting_approval)"
}
```

Status values:
- `active` — working normally
- `waiting_approval` — set when requesting tool approval from the user
- `blocked` — external dependency or error prevents progress
- `idle` — task complete or waiting for new instructions

Rules:
- Set `goal` after understanding the first request — one concise sentence
- Update `progress` / `remaining` after meaningful milestones, not every small edit
- Rewrite `summary` every ~10 user prompts or at meaningful milestones — one sentence, ≤15 words, describing recent activity (e.g. "Refactored auth.ts, added jwt types, updated config — next wire refresh endpoint"). This is the no-tmux "recent activity" line users see in their statusline.
- Set `status: "waiting_approval"` when requesting user action
- Keep all strings under 80 characters
- Write the file atomically: write to `mission.json.tmp` first, then rename to `mission.json`

Example write (PowerShell):
```powershell
$m = @{ version=1; goal="Add JWT auth to /api/users"; progress=@("read auth.ts"); remaining=@("write tests","update routes"); status="active" } | ConvertTo-Json
$m | Out-File "$HOME\.claude\brif\current\mission.json.tmp" -Encoding utf8 -NoNewline
Move-Item "$HOME\.claude\brif\current\mission.json.tmp" "$HOME\.claude\brif\current\mission.json" -Force
```
