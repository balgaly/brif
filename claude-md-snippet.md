## brif - Mission Context

When working on tasks, maintain a mission context file for the brif dashboard.
After completing a significant milestone (feature done, file created, test passed,
blocker encountered), update the file at:
  ~/.claude/brif/current/mission.json

The file schema:
{
  "version": 1,
  "goal": "One-sentence objective for this session",
  "progress": ["Completed item 1", "Completed item 2"],
  "remaining": ["TODO item 1", "TODO item 2"],
  "status": "active | waiting_approval | blocked | idle",
  "pending": "Description of what needs user action (optional)"
}

Status values:
- "active" — working normally
- "waiting_approval" — set this when you request tool approval from the user
- "blocked" — an external dependency or error prevents progress
- "idle" — task complete or waiting for new instructions

Rules:
- Set the goal after understanding the user's first request
- Update progress/remaining after meaningful milestones, not every small edit
- Set status to "waiting_approval" when requesting tool approval
- Keep descriptions concise (under 80 chars each)
- Do not update color or updated_at — the system manages those
