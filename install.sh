#!/usr/bin/env bash
# cmux-ide installer — symlinks scripts and installs skills/hooks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing cmux-ide..."

# Ensure directories exist
mkdir -p "$HOME/bin" "$HOME/bin/cmux-ide-modules" "$HOME/.config/cmux-ide"
mkdir -p "$HOME/.claude/commands" "$HOME/.claude/skills/using-cmux"

# Symlink bin scripts
ln -sf "$SCRIPT_DIR/bin/cmux-ide" "$HOME/bin/cmux-ide"
ln -sf "$SCRIPT_DIR/hooks/session-hook" "$HOME/bin/cmux-ide-session-hook"
chmod +x "$HOME/bin/cmux-ide" "$HOME/bin/cmux-ide-session-hook"

# Symlink modules
ln -sf "$SCRIPT_DIR/modules/browser.sh" "$HOME/bin/cmux-ide-modules/browser.sh"
ln -sf "$SCRIPT_DIR/modules/status.sh" "$HOME/bin/cmux-ide-modules/status.sh"
ln -sf "$SCRIPT_DIR/modules/new-tab.sh" "$HOME/bin/cmux-ide-modules/new-tab.sh"
ln -sf "$SCRIPT_DIR/modules/analyze-workspace.sh" "$HOME/bin/cmux-ide-modules/analyze-workspace.sh"
ln -sf "$SCRIPT_DIR/modules/create-surfaces.sh" "$HOME/bin/cmux-ide-modules/create-surfaces.sh"
chmod +x "$HOME/bin/cmux-ide-modules/"*.sh

# Remove old setup-workspace command (replaced by analyze+create modules)
rm -f "$HOME/.claude/commands/setup-workspace.md"

# Symlink Claude Code skills and commands
ln -sf "$SCRIPT_DIR/commands/cmux.md" "$HOME/.claude/commands/cmux.md"
ln -sf "$SCRIPT_DIR/skills/using-cmux/SKILL.md" "$HOME/.claude/skills/using-cmux/SKILL.md"

echo ""
echo "Installed. Remaining manual steps:"
echo ""
echo "1. (Claude Code only) Add SessionStart hook to ~/.claude/settings.json:"
echo '   "SessionStart": [{"hooks": [{"type": "command", "command": "$HOME/bin/cmux-ide-session-hook"}]}]'
echo ""
echo "2. (Claude Code only) Add Notification hook to ~/.claude/settings.json:"
echo '   "Notification": [{"matcher": "", "hooks": [{"type": "command", "command": "cmux notify --title '\''cmux-ide'\'' --body '\''Needs attention'\'' 2>/dev/null || true"}]}]'
echo ""
echo "Agent config:"
echo "  Default agent is set on first launch (interactive prompt)."
echo "  Override per-project: add '\"agent\": \"codex\"' to .cmux-ide.json"
echo "  Override globally:    echo 'codex' > ~/.config/cmux-ide/agent"
echo "  Override per-session: CMUX_IDE_AGENT=codex cmux-ide ~/project"
echo ""
echo "Note: ~/.claude/ skills and commands are Claude Code-specific and optional for other agents."
echo ""
echo "Done."
