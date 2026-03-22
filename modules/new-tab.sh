#!/usr/bin/env bash
# Usage: new-tab.sh <workspace_ref> <pane_ref> <label> [command]
# Creates a surface, renames it, optionally sends a command, and prints the surface ref.
set -euo pipefail

ws_ref="$1"
pane_ref="$2"
label="$3"
cmd="${4:-}"

# Create surface and capture ref
surface_ref=$(cmux new-surface --pane "$pane_ref" --workspace "$ws_ref" 2>&1 | grep -oE 'surface:[0-9]+' | head -1)
if [[ -z "$surface_ref" ]]; then
  echo "Error: Failed to create surface" >&2
  exit 1
fi

# Rename immediately
cmux rename-tab --workspace "$ws_ref" --surface "$surface_ref" "$label"

# Optionally send command
if [[ -n "$cmd" ]]; then
  cmux send --workspace "$ws_ref" --surface "$surface_ref" "$cmd"
  cmux send-key --workspace "$ws_ref" --surface "$surface_ref" Return
fi

# Output the ref for caller to use
echo "$surface_ref"
