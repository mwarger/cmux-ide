#!/usr/bin/env bash
# Module: status — Set sidebar metadata pills for a workspace
set -euo pipefail
ws="$1" _sf="$2" dir="$3"
links_file="$HOME/.config/cmux-ide/links.json"

# Git info
if [[ -d "$dir/.git" ]] || git -C "$dir" rev-parse --git-dir &>/dev/null; then
  dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "??")
  if [[ "$dirty" -gt 0 ]]; then
    cmux set-status git "${branch} (${dirty} changed)" --icon "arrow.triangle.branch" --color "#F44336" --workspace "$ws" 2>/dev/null || true
  else
    cmux set-status git "${branch} ✓" --icon "arrow.triangle.branch" --color "#4CAF50" --workspace "$ws" 2>/dev/null || true
  fi
fi

# Linked browser workspace (read from links.json)
if [[ -f "$links_file" ]]; then
  browser_ws=$(python3 -c "
import json
d = json.load(open('$links_file'))
e = d.get('$ws', {})
print(e.get('browser', ''))
" 2>/dev/null) || browser_ws=""
  if [[ -n "$browser_ws" ]]; then
    cmux set-status browser "$browser_ws" --icon "globe" --color "#4CAF50" --workspace "$ws" 2>/dev/null || true
  fi
fi
