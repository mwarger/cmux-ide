#!/usr/bin/env bash
# Module: create-surfaces — Phase 2: deterministic workspace creation from JSON plan
# Usage: create-surfaces.sh <ws_ref> <project_dir> < plan.json
set -uo pipefail

ws_ref="$1"
project_dir="$2"

MODULES_DIR="$HOME/bin/cmux-ide-modules"

# --- Parse JSON plan (supports both flat and zones format) ---

parsed=$(python3 -c "
import json, sys
plan = json.load(sys.stdin)
if 'zones' in plan:
    print(f'format\tzones\t{plan.get(\"archetype\", \"default\")}')
    for zone_name, zone in plan['zones'].items():
        position = zone.get('position', '')
        style = zone.get('style', 'tabs')
        for tab in zone.get('tabs', []):
            label = tab.get('label', '')
            cmd = tab.get('command', '')
            print(f'zone_tab\t{zone_name}\t{position}\t{style}\t{label}\t{cmd}')
else:
    print('format\tflat\tdefault')
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

# --- Read format line ---

format_line=$(echo "$parsed" | head -1)
plan_format=$(echo "$format_line" | cut -f2)
archetype=$(echo "$format_line" | cut -f3)

declare -A surface_refs
browser_port=""

# Extract browser port from parsed output
browser_line=$(echo "$parsed" | grep '^browser' || echo "")
if [[ -n "$browser_line" ]]; then
  browser_port=$(echo "$browser_line" | cut -f2)
fi

# --- Helper: populate tabs in a pane ---
# Args: pane_ref first_surface tab_lines_variable
populate_tabs() {
  local pane_ref="$1"
  local first_surface="$2"
  local tab_lines="$3"
  local idx=0

  while IFS=$'\t' read -r label cmd; do
    [[ -z "$label" ]] && continue
    local full_cmd=""
    if [[ -n "$cmd" ]]; then
      full_cmd="cd '$project_dir' && $cmd"
    fi

    if [[ "$idx" -eq 0 ]]; then
      # Reuse the surface already in the pane
      cmux rename-tab --workspace "$ws_ref" --surface "$first_surface" "$label" 2>/dev/null || true
      if [[ -n "$full_cmd" ]]; then
        cmux send --workspace "$ws_ref" --surface "$first_surface" "$full_cmd"
        cmux send-key --workspace "$ws_ref" --surface "$first_surface" Return
      fi
      surface_refs["$label"]="$first_surface"
    else
      local local_ref
      local_ref=$("$MODULES_DIR/new-tab.sh" "$ws_ref" "$pane_ref" "$label" "$full_cmd" 2>/dev/null | grep -oE 'surface:[0-9]+' | tail -1) || local_ref=""
      if [[ -n "$local_ref" ]]; then
        surface_refs["$label"]="$local_ref"
      fi
    fi
    idx=$((idx + 1))
  done <<< "$tab_lines"
}

# --- Flat layout (existing behavior) ---

create_flat_layout() {
  cmux set-progress 0.1 --label "Creating panes..." --workspace "$ws_ref" 2>/dev/null || true

  # Create right pane split
  local split_output first_surface
  split_output=$(cmux new-split right --workspace "$ws_ref" 2>&1)
  first_surface=$(echo "$split_output" | grep -oE 'surface:[0-9]+' | head -1)
  sleep 0.3

  if [[ -z "$first_surface" ]]; then
    echo "create-surfaces: failed to create right pane split" >&2
    exit 1
  fi

  # Discover the right pane ref
  local right_pane
  right_pane=$(cmux tree --workspace "$ws_ref" 2>&1 | grep -B1 "$first_surface" | grep -oE 'pane:[0-9]+' | head -1)

  if [[ -z "$right_pane" ]]; then
    echo "create-surfaces: failed to discover right pane ref" >&2
    exit 1
  fi

  # Extract tab lines (label\tcmd)
  local tab_lines
  tab_lines=$(echo "$parsed" | grep '^tab' | while IFS=$'\t' read -r _type label cmd; do
    printf '%s\t%s\n' "$label" "$cmd"
  done)

  local total_tabs
  total_tabs=$(echo "$tab_lines" | grep -c '.' || echo 3)
  [[ "$total_tabs" -lt 1 ]] && total_tabs=3

  local idx=0
  while IFS=$'\t' read -r label cmd; do
    [[ -z "$label" ]] && continue
    local full_cmd=""
    if [[ -n "$cmd" ]]; then
      full_cmd="cd '$project_dir' && $cmd"
    fi

    if [[ "$idx" -eq 0 ]]; then
      cmux rename-tab --workspace "$ws_ref" --surface "$first_surface" "$label" 2>/dev/null || true
      if [[ -n "$full_cmd" ]]; then
        cmux send --workspace "$ws_ref" --surface "$first_surface" "$full_cmd"
        cmux send-key --workspace "$ws_ref" --surface "$first_surface" Return
      fi
      surface_refs["$label"]="$first_surface"
    else
      local local_ref
      local_ref=$("$MODULES_DIR/new-tab.sh" "$ws_ref" "$right_pane" "$label" "$full_cmd" 2>/dev/null | grep -oE 'surface:[0-9]+' | tail -1) || local_ref=""
      if [[ -n "$local_ref" ]]; then
        surface_refs["$label"]="$local_ref"
      fi
    fi

    idx=$((idx + 1))
    cmux set-progress 0.$((10 + 50 * idx / total_tabs)) --label "Created $label" --workspace "$ws_ref" 2>/dev/null || true
  done <<< "$tab_lines"
}

# --- Zone layout (single-service / full-stack) ---

create_zone_layout() {
  cmux set-progress 0.1 --label "Creating layout..." --workspace "$ws_ref" 2>/dev/null || true

  # 1. Create right pane split → this becomes the tools pane (top-right)
  local split_output tools_first_surface
  split_output=$(cmux new-split right --workspace "$ws_ref" 2>&1)
  tools_first_surface=$(echo "$split_output" | grep -oE 'surface:[0-9]+' | head -1)
  sleep 0.3

  if [[ -z "$tools_first_surface" ]]; then
    echo "create-surfaces: failed to create right pane split" >&2
    exit 1
  fi

  # Discover the tools pane ref
  local tools_pane
  tools_pane=$(cmux tree --workspace "$ws_ref" 2>&1 | grep -B1 "$tools_first_surface" | grep -oE 'pane:[0-9]+' | head -1)

  if [[ -z "$tools_pane" ]]; then
    echo "create-surfaces: failed to discover tools pane ref" >&2
    exit 1
  fi

  # Extract zone data
  local tools_tabs services_tabs services_style
  tools_tabs=$(echo "$parsed" | grep '^zone_tab	tools	' | while IFS=$'\t' read -r _type _zone _pos _style label cmd; do
    printf '%s\t%s\n' "$label" "$cmd"
  done)
  services_tabs=$(echo "$parsed" | grep '^zone_tab	services	' | while IFS=$'\t' read -r _type _zone _pos _style label cmd; do
    printf '%s\t%s\n' "$label" "$cmd"
  done)
  services_style=$(echo "$parsed" | grep '^zone_tab	services	' | head -1 | cut -f4)

  local services_count
  services_count=$(echo "$services_tabs" | grep -c '.' || echo 0)

  # 2. If services zone exists, split down from tools pane → creates bottom-right services pane
  local services_first_surface="" services_pane=""
  if [[ "$services_count" -gt 0 ]]; then
    cmux set-progress 0.2 --label "Creating services pane..." --workspace "$ws_ref" 2>/dev/null || true
    local svc_split_output
    svc_split_output=$(cmux new-split down --surface "$tools_first_surface" --workspace "$ws_ref" 2>&1)
    services_first_surface=$(echo "$svc_split_output" | grep -oE 'surface:[0-9]+' | head -1)
    sleep 0.3

    if [[ -n "$services_first_surface" ]]; then
      # Re-discover tools pane (it may have changed after the split)
      tools_pane=$(cmux tree --workspace "$ws_ref" 2>&1 | grep -B1 "$tools_first_surface" | grep -oE 'pane:[0-9]+' | head -1)
      services_pane=$(cmux tree --workspace "$ws_ref" 2>&1 | grep -B1 "$services_first_surface" | grep -oE 'pane:[0-9]+' | head -1)
    fi
  fi

  # 3. If services style is "split" and 2+ services, split services pane right → side-by-side
  local services_second_surface="" services_second_pane=""
  if [[ "$services_style" == "split" ]] && [[ "$services_count" -ge 2 ]] && [[ -n "$services_pane" ]]; then
    cmux set-progress 0.25 --label "Splitting services..." --workspace "$ws_ref" 2>/dev/null || true
    local svc2_split_output
    svc2_split_output=$(cmux new-split right --surface "$services_first_surface" --workspace "$ws_ref" 2>&1)
    services_second_surface=$(echo "$svc2_split_output" | grep -oE 'surface:[0-9]+' | head -1)
    sleep 0.3

    if [[ -n "$services_second_surface" ]]; then
      # Re-discover panes after the second split
      services_pane=$(cmux tree --workspace "$ws_ref" 2>&1 | grep -B1 "$services_first_surface" | grep -oE 'pane:[0-9]+' | head -1)
      services_second_pane=$(cmux tree --workspace "$ws_ref" 2>&1 | grep -B1 "$services_second_surface" | grep -oE 'pane:[0-9]+' | head -1)
    fi
  fi

  # 4. Populate tools zone tabs
  cmux set-progress 0.3 --label "Setting up tools..." --workspace "$ws_ref" 2>/dev/null || true
  populate_tabs "$tools_pane" "$tools_first_surface" "$tools_tabs"

  # 5. Populate services zone
  if [[ -n "$services_first_surface" ]]; then
    cmux set-progress 0.5 --label "Setting up services..." --workspace "$ws_ref" 2>/dev/null || true

    if [[ -n "$services_second_surface" ]] && [[ "$services_count" -ge 2 ]]; then
      # Split mode: first service in left pane, second in right pane, 3+ as tabs in right pane
      local svc_idx=0
      while IFS=$'\t' read -r label cmd; do
        [[ -z "$label" ]] && continue
        local full_cmd=""
        if [[ -n "$cmd" ]]; then
          full_cmd="cd '$project_dir' && $cmd"
        fi

        if [[ "$svc_idx" -eq 0 ]]; then
          # First service: reuse services_first_surface (left)
          cmux rename-tab --workspace "$ws_ref" --surface "$services_first_surface" "$label" 2>/dev/null || true
          if [[ -n "$full_cmd" ]]; then
            cmux send --workspace "$ws_ref" --surface "$services_first_surface" "$full_cmd"
            cmux send-key --workspace "$ws_ref" --surface "$services_first_surface" Return
          fi
          surface_refs["$label"]="$services_first_surface"
        elif [[ "$svc_idx" -eq 1 ]]; then
          # Second service: reuse services_second_surface (right)
          cmux rename-tab --workspace "$ws_ref" --surface "$services_second_surface" "$label" 2>/dev/null || true
          if [[ -n "$full_cmd" ]]; then
            cmux send --workspace "$ws_ref" --surface "$services_second_surface" "$full_cmd"
            cmux send-key --workspace "$ws_ref" --surface "$services_second_surface" Return
          fi
          surface_refs["$label"]="$services_second_surface"
        else
          # 3+ services: add as tabs in the second services pane
          local local_ref
          local_ref=$("$MODULES_DIR/new-tab.sh" "$ws_ref" "$services_second_pane" "$label" "$full_cmd" 2>/dev/null | grep -oE 'surface:[0-9]+' | tail -1) || local_ref=""
          if [[ -n "$local_ref" ]]; then
            surface_refs["$label"]="$local_ref"
          fi
        fi
        svc_idx=$((svc_idx + 1))
      done <<< "$services_tabs"
    else
      # Tabs mode (single-service): all services as tabs in the services pane
      populate_tabs "$services_pane" "$services_first_surface" "$services_tabs"
    fi
  fi
}

# --- Dispatch based on format ---

if [[ "$plan_format" == "zones" ]]; then
  create_zone_layout
else
  create_flat_layout
fi

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
d['archetype'] = '$archetype'
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
if [[ "$archetype" != "default" ]]; then
  summary="[$archetype] $summary"
fi
cmux set-status workspace "$summary" --icon "square.grid.2x2" --color "#4CAF50" --workspace "$ws_ref" 2>/dev/null || true

# stdout kept silent — caller prints its own progress
