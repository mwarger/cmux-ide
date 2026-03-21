#!/usr/bin/env bash
# Module: browser — Create linked browser workspace (full-screen browser, no terminal)
set -uo pipefail
code_ws="$1" _sf="$2" dir="$3" port="${4:-3000}"
project_name=$(basename "$dir")
links_file="$HOME/.config/cmux-ide/links.json"
state_file="$dir/.cmux-ide.state.json"

# Create browser workspace
browser_ws=$(cmux new-workspace 2>&1 | grep -oE 'workspace:[0-9]+' | head -1)
if [[ -z "$browser_ws" ]]; then
  echo "browser: failed to create workspace" >&2
  exit 1
fi

sleep 0.3

cmux rename-workspace --workspace "$browser_ws" "${project_name} 🌐"

# Get the initial terminal surface so we can close it after opening browser
initial_sf=$(cmux send --workspace "$browser_ws" " " 2>&1 | grep -oE 'surface:[0-9]+' | head -1) || initial_sf=""

# Open browser in the new workspace (creates a browser split)
cmux browser open "http://localhost:$port" --workspace "$browser_ws" 2>/dev/null || true

# Close the initial terminal surface — leaves only the full-screen browser
if [[ -n "$initial_sf" ]]; then
  cmux close-surface --workspace "$browser_ws" --surface "$initial_sf" 2>/dev/null || true
fi

# Cross-reference via set-status on both workspaces
cmux set-status browser "$browser_ws" --icon "globe" --color "#4CAF50" --workspace "$code_ws" 2>/dev/null || true
cmux set-status code "$code_ws" --icon "terminal.fill" --color "#2196F3" --workspace "$browser_ws" 2>/dev/null || true

# Update global links.json
python3 -c "
import json, os
f = '$links_file'
d = json.load(open(f)) if os.path.exists(f) else {}
d['$code_ws'] = {'browser': '$browser_ws', 'project': '$dir', 'port': $port}
json.dump(d, open(f, 'w'), indent=2)
" 2>/dev/null || true

# Update project-level state file
python3 -c "
import json, os
from datetime import datetime, timezone
f = '$state_file'
d = json.load(open(f)) if os.path.exists(f) else {}
d['code_workspace'] = '$code_ws'
d['browser_workspace'] = '$browser_ws'
d['last_opened'] = datetime.now(timezone.utc).isoformat()
json.dump(d, open(f, 'w'), indent=2)
" 2>/dev/null || true

echo "browser: linked $code_ws <-> $browser_ws (localhost:$port)"
