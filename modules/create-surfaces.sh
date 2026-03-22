#!/usr/bin/env bash
# Module: create-surfaces — Phase 2: deterministic workspace creation from JSON plan
# Usage: create-surfaces.sh <ws_ref> <project_dir> < plan.json
set -uo pipefail

ws_ref="$1"
project_dir="$2"

MODULES_DIR="$HOME/bin/cmux-ide-modules"

# --- Parse JSON plan ---

parsed=$(python3 -c "
import json, sys
plan = json.load(sys.stdin)
for tab in plan.get('tabs', []):
    label = tab.get('label', '')
    cmd = tab.get('command', '')
    print(f'tab\t{label}\t{cmd}')
browser = plan.get('browser')
if browser and isinstance(browser, dict) and 'port' in browser:
    print(f'browser\t{browser[\"port\"]}')
") || {
  echo "create-surfaces: failed to parse plan JSON" >&2
  exit 1
}

# --- Create workspace surfaces ---

cmux set-progress 0.1 --label "Creating panes..." --workspace "$ws_ref" 2>/dev/null || true

# Create right pane split — capture the surface ref from output
split_output=$(cmux new-split right --workspace "$ws_ref" 2>&1)
first_surface=$(echo "$split_output" | grep -oE 'surface:[0-9]+' | head -1)
sleep 0.3

if [[ -z "$first_surface" ]]; then
  echo "create-surfaces: failed to create right pane split" >&2
  exit 1
fi

# Discover the right pane ref from tree (the pane containing our new surface)
right_pane=$(cmux tree --workspace "$ws_ref" 2>&1 | grep -B1 "$first_surface" | grep -oE 'pane:[0-9]+' | head -1)

if [[ -z "$right_pane" ]]; then
  echo "create-surfaces: failed to discover right pane ref" >&2
  exit 1
fi

# --- Create tabs ---

# Count total tabs for progress calculation
total_tabs=$(echo "$parsed" | grep -c '^tab' || echo 3)
[[ "$total_tabs" -lt 1 ]] && total_tabs=3

declare -A surface_refs
tab_index=0
browser_port=""

while IFS=$'\t' read -r type arg1 arg2; do
  case "$type" in
    tab)
      label="$arg1"
      cmd="$arg2"
      full_cmd=""
      if [[ -n "$cmd" ]]; then
        full_cmd="cd '$project_dir' && $cmd"
      fi

      if [[ "$tab_index" -eq 0 ]]; then
        # First tab: reuse the surface created by new-split
        cmux rename-tab --workspace "$ws_ref" --surface "$first_surface" "$label" 2>/dev/null || true
        if [[ -n "$full_cmd" ]]; then
          cmux send --workspace "$ws_ref" --surface "$first_surface" "$full_cmd"
          cmux send-key --workspace "$ws_ref" --surface "$first_surface" Return
        fi
        surface_refs["$label"]="$first_surface"
      else
        # Subsequent tabs: use new-tab.sh helper
        local_ref=$("$MODULES_DIR/new-tab.sh" "$ws_ref" "$right_pane" "$label" "$full_cmd" 2>/dev/null | grep -oE 'surface:[0-9]+' | tail -1) || local_ref=""
        if [[ -n "$local_ref" ]]; then
          surface_refs["$label"]="$local_ref"
        fi
      fi

      tab_index=$((tab_index + 1))
      cmux set-progress 0.$((10 + 50 * tab_index / total_tabs)) --label "Created $label" --workspace "$ws_ref" 2>/dev/null || true
      ;;
    browser)
      browser_port="$arg1"
      ;;
  esac
done <<< "$parsed"

# --- Browser workspace ---

if [[ -n "$browser_port" ]]; then
  cmux set-progress 0.7 --label "Setting up browser..." --workspace "$ws_ref" 2>/dev/null || true
  "$MODULES_DIR/browser.sh" "$ws_ref" "" "$project_dir" "$browser_port" 2>/dev/null || true
fi

# --- Sidebar metadata ---

cmux set-progress 0.8 --label "Setting metadata..." --workspace "$ws_ref" 2>/dev/null || true
"$MODULES_DIR/status.sh" "$ws_ref" "" "$project_dir" 2>/dev/null || true

# --- Write state file ---

cmux set-progress 0.9 --label "Saving state..." --workspace "$ws_ref" 2>/dev/null || true

# Build surfaces map as tab-separated lines for python
surfaces_lines=""
for label in "${!surface_refs[@]}"; do
  surfaces_lines="${surfaces_lines}${label}\t${surface_refs[$label]}\n"
done

printf "%b" "$surfaces_lines" | python3 -c "
import json, os, sys
from datetime import datetime, timezone
surfaces = {}
for line in sys.stdin:
    line = line.strip()
    if line:
        parts = line.split('\t', 1)
        if len(parts) == 2:
            surfaces[parts[0]] = parts[1]
f = '$project_dir/.cmux-ide.state.json'
d = json.load(open(f)) if os.path.exists(f) else {}
d['code_workspace'] = '$ws_ref'
d['surfaces'] = surfaces
d['last_opened'] = datetime.now(timezone.utc).isoformat()
json.dump(d, open(f, 'w'), indent=2)
" 2>/dev/null || true

# --- Done ---

cmux clear-progress --workspace "$ws_ref" 2>/dev/null || true

# Build a summary of what was created
tab_labels=""
for label in "${!surface_refs[@]}"; do
  if [[ -n "$tab_labels" ]]; then
    tab_labels="$tab_labels, $label"
  else
    tab_labels="$label"
  fi
done
summary="$tab_labels"
if [[ -n "$browser_port" ]]; then
  summary="$summary + browser :$browser_port"
fi
cmux set-status workspace "$summary" --icon "square.grid.2x2" --color "#4CAF50" --workspace "$ws_ref" 2>/dev/null || true

# stdout kept silent — caller prints its own progress
