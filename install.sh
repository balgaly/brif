#!/usr/bin/env bash
# ============================================================================
# brif Installer for macOS/Linux (Bash)
# ============================================================================
# Installs the statusline.sh script and configures Claude Code to use it.
#
# One-liner install:
#   curl -sL https://raw.githubusercontent.com/balgaly/brif/main/install.sh | bash
#
# What this script does:
#   1. Downloads statusline.sh to ~/.claude/statusline.sh
#   2. Makes it executable
#   3. Adds the statusLine configuration to ~/.claude/settings.json
#   4. Preserves any existing settings in settings.json
# ============================================================================

set -euo pipefail

# --- Color helpers ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

success() { printf "${GREEN}%s${NC}\n" "$1"; }
warn()    { printf "${YELLOW}%s${NC}\n" "$1"; }
info()    { printf "${CYAN}%s${NC}\n" "$1"; }

# --- Configuration ---
REPO_BASE="https://raw.githubusercontent.com/balgaly/brif/main"
CLAUDE_DIR="$HOME/.claude"
BRIF_DIR="$CLAUDE_DIR/brif"
BRIF_HOOKS_DIR="$CLAUDE_DIR/brif-hooks"
SCRIPT_DEST="$CLAUDE_DIR/statusline.sh"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

STATUSLINE_KEY="statusLine"
STATUSLINE_VALUE='{"type":"command","command":"~/.claude/statusline.sh"}'

# Brif files to download
BRIF_FILES=(
  "brif:$CLAUDE_DIR/brif-launcher"
  "brif-pane.sh:$CLAUDE_DIR/brif-pane.sh"
  "hooks/post-tool-use.sh:$BRIF_HOOKS_DIR/post-tool-use.sh"
  "hooks/user-prompt.sh:$BRIF_HOOKS_DIR/user-prompt.sh"
  "claude-md-snippet.md:$CLAUDE_DIR/brif-claude-md-snippet.md"
)

# --- Main ---
info "brif installer for macOS/Linux"
info "=============================================="
echo ""

# Step 1: Ensure ~/.claude/ directory exists
if [ ! -d "$CLAUDE_DIR" ]; then
    mkdir -p "$CLAUDE_DIR"
    success "Created directory: $CLAUDE_DIR"
else
    info "Directory already exists: $CLAUDE_DIR"
fi

# Step 2: Download statusline.sh
DOWNLOAD_URL="$REPO_BASE/statusline.sh"
info "Downloading statusline.sh from $DOWNLOAD_URL ..."

if [ -f "$SCRIPT_DEST" ]; then
    warn "Existing statusline.sh found at $SCRIPT_DEST -- it will be overwritten."
fi

if command -v curl &>/dev/null; then
    curl -sL "$DOWNLOAD_URL" -o "$SCRIPT_DEST"
elif command -v wget &>/dev/null; then
    wget -q "$DOWNLOAD_URL" -O "$SCRIPT_DEST"
else
    echo "Error: Neither curl nor wget found. Please install one and retry." >&2
    exit 1
fi

chmod +x "$SCRIPT_DEST"
success "Downloaded statusline.sh to $SCRIPT_DEST (executable)"

# Step 2b: Download brif files
info "Downloading brif files ..."
mkdir -p "$BRIF_DIR" "$BRIF_HOOKS_DIR"

for entry in "${BRIF_FILES[@]}"; do
  src="${entry%%:*}"
  dest="${entry##*:}"
  url="$REPO_BASE/$src"
  info "  $src -> $dest"
  if command -v curl &>/dev/null; then
    curl -sL "$url" -o "$dest"
  else
    wget -q "$url" -O "$dest"
  fi
  chmod +x "$dest"
done
success "Downloaded brif files"

# Step 3: Read or create settings.json
if [ ! -f "$SETTINGS_FILE" ]; then
    info "No settings.json found -- creating a new one."
    echo '{}' > "$SETTINGS_FILE"
else
    info "Reading existing settings from $SETTINGS_FILE ..."
    # Validate that the file contains valid JSON
    if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS_FILE" 2>/dev/null \
       && ! (command -v jq &>/dev/null && jq empty "$SETTINGS_FILE" 2>/dev/null); then
        BACKUP_FILE="$SETTINGS_FILE.bak.$(date +%Y%m%d%H%M%S)"
        warn "Could not parse existing settings.json. Backing up and starting fresh."
        cp "$SETTINGS_FILE" "$BACKUP_FILE"
        warn "Backup saved to $BACKUP_FILE"
        echo '{}' > "$SETTINGS_FILE"
    fi
fi

# Step 4: Add/update the statusLine entry (merge, do not overwrite)

# Check if statusLine already exists
has_statusline() {
    if command -v jq &>/dev/null; then
        jq -e ".$STATUSLINE_KEY" "$SETTINGS_FILE" &>/dev/null
    elif command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
sys.exit(0 if '$STATUSLINE_KEY' in d else 1)
" "$SETTINGS_FILE"
    else
        grep -q "\"$STATUSLINE_KEY\"" "$SETTINGS_FILE" 2>/dev/null
    fi
}

if has_statusline; then
    warn "Existing statusLine configuration found -- updating it."
else
    info "Adding statusLine configuration ..."
fi

# Merge statusLine into settings.json using jq, python3, or sed as fallback
merge_settings() {
    if command -v jq &>/dev/null; then
        # jq approach: merge statusLine into existing settings
        local tmp
        tmp=$(mktemp)
        jq --argjson sl "$STATUSLINE_VALUE" '."'"$STATUSLINE_KEY"'" = $sl' "$SETTINGS_FILE" > "$tmp"
        mv "$tmp" "$SETTINGS_FILE"
        return 0
    fi

    if command -v python3 &>/dev/null; then
        # python3 approach: read, merge, write
        python3 -c "
import json, sys

settings_path = sys.argv[1]
with open(settings_path, 'r') as f:
    settings = json.load(f)

settings['$STATUSLINE_KEY'] = json.loads('$STATUSLINE_VALUE')

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
" "$SETTINGS_FILE"
        return 0
    fi

    warn "Neither jq nor python3 found. Please add this to your settings.json manually:"
    echo '  "statusLine": {"type":"command","command":"~/.claude/statusline.sh"}'
    return 1
}

merge_settings
success "Updated $SETTINGS_FILE with statusLine"

# Step 5: Add hooks configuration to settings.json
info "Configuring brif hooks ..."

merge_hooks() {
    if command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq '
          .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{"type":"command","command":"bash ~/.claude/brif-hooks/post-tool-use.sh"}] | unique_by(.command)) |
          .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{"type":"command","command":"bash ~/.claude/brif-hooks/user-prompt.sh"}] | unique_by(.command))
        ' "$SETTINGS_FILE" > "$tmp"
        mv "$tmp" "$SETTINGS_FILE"
        return 0
    fi

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys

path = sys.argv[1]
with open(path, 'r') as f:
    s = json.load(f)

hooks = s.setdefault('hooks', {})
post = hooks.setdefault('PostToolUse', [])
prompt = hooks.setdefault('UserPromptSubmit', [])

post_cmd = {'type': 'command', 'command': 'bash ~/.claude/brif-hooks/post-tool-use.sh'}
prompt_cmd = {'type': 'command', 'command': 'bash ~/.claude/brif-hooks/user-prompt.sh'}

if not any(h.get('command') == post_cmd['command'] for h in post):
    post.append(post_cmd)
if not any(h.get('command') == prompt_cmd['command'] for h in prompt):
    prompt.append(prompt_cmd)

with open(path, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
" "$SETTINGS_FILE"
        return 0
    fi

    warn "Neither jq nor python3 found. Skipping hooks configuration."
    warn "Add hooks manually — see README for details."
    return 0
}

merge_hooks

# Step 5b: Add brif write permission
merge_permissions() {
    local perm="Write(~/.claude/brif/**)"
    if command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp)
        jq --arg p "$perm" '
          .permissions.allow = ((.permissions.allow // []) + [$p] | unique)
        ' "$SETTINGS_FILE" > "$tmp"
        mv "$tmp" "$SETTINGS_FILE"
        return 0
    fi

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys

path = sys.argv[1]
perm = sys.argv[2]
with open(path, 'r') as f:
    s = json.load(f)

perms = s.setdefault('permissions', {})
allow = perms.setdefault('allow', [])
if perm not in allow:
    allow.append(perm)

with open(path, 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
" "$SETTINGS_FILE" "$perm"
        return 0
    fi

    warn "Neither jq nor python3 found. Skipping permissions configuration."
    warn "Add 'Write(~/.claude/brif/**)' to permissions.allow manually."
    return 0
}

merge_permissions
success "Updated $SETTINGS_FILE with hooks and permissions"

# Step 6: Append brif instructions to CLAUDE.md
SNIPPET_FILE="$CLAUDE_DIR/brif-claude-md-snippet.md"
if [[ -f "$SNIPPET_FILE" ]]; then
    if [[ -f "$CLAUDE_MD" ]] && grep -q "brif - Mission Context" "$CLAUDE_MD" 2>/dev/null; then
        info "CLAUDE.md already contains brif instructions — skipping."
    else
        info "Appending brif instructions to CLAUDE.md ..."
        echo "" >> "$CLAUDE_MD"
        cat "$SNIPPET_FILE" >> "$CLAUDE_MD"
        success "Updated $CLAUDE_MD"
    fi
    rm -f "$SNIPPET_FILE"
fi

# Step 7: Success message
echo ""
success "============================================"
success "  brif installed successfully!"
success "============================================"
echo ""
info "The status line will appear next time you start Claude Code."
info "To customize, edit: $SCRIPT_DEST"
info "Settings stored in: $SETTINGS_FILE"
echo ""
info "brif (mission dashboard) installed. Launch with:"
info "  ~/.claude/brif-launcher"
echo ""
