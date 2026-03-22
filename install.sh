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
chmod +x "$HOME/bin/cmux-ide-modules/"*.sh

# Symlink Claude Code skills and commands
ln -sf "$SCRIPT_DIR/commands/setup-workspace.md" "$HOME/.claude/commands/setup-workspace.md"
ln -sf "$SCRIPT_DIR/commands/cmux.md" "$HOME/.claude/commands/cmux.md"
ln -sf "$SCRIPT_DIR/skills/using-cmux/SKILL.md" "$HOME/.claude/skills/using-cmux/SKILL.md"

echo ""
echo "Installed. Remaining manual steps:"
echo ""
echo "1. Add SessionStart hook to ~/.claude/settings.json:"
echo '   "SessionStart": [{"hooks": [{"type": "command", "command": "$HOME/bin/cmux-ide-session-hook"}]}]'
echo ""
echo "2. Add Notification hook to ~/.claude/settings.json:"
echo '   "Notification": [{"matcher": "", "hooks": [{"type": "command", "command": "cmux notify --title '\''Claude Code'\'' --body '\''Needs attention'\'' 2>/dev/null || true"}]}]'
echo ""
echo "3. Add ide() function to ~/.zshrc:"
echo '   ide() { local m=$(grep -i "/${1}$" ~/.config/cmux-ide/favorites 2>/dev/null | head -1); [[ -z "$m" ]] && m=$(grep -i "$1" ~/.config/cmux-ide/favorites 2>/dev/null | head -1); [[ -n "$m" ]] && cmux-ide "$m" || { echo "No match: $1"; cmux-ide --list-fav; }; }'
echo ""
echo "Done."
