#!/usr/bin/env bash
# Module: analyze-workspace — Phase 1: gather project context, prompt Haiku, return JSON plan
# Usage: analyze-workspace.sh <project_dir>
# Output: JSON plan to stdout
set -euo pipefail

project_dir="$1"
MAX_LINES=200

# --- Default plan (fallback) ---
default_plan='{"tabs":[{"label":"gitui","command":"gitui"},{"label":"terminal","command":""}],"browser":null}'

# --- Gather context ---

read_if_exists() {
  local file="$1"
  if [[ -f "$file" ]]; then
    head -n "$MAX_LINES" "$file"
  fi
}

package_json=$(read_if_exists "$project_dir/package.json")
agents_md=$(read_if_exists "$project_dir/AGENTS.md")
claude_md=$(read_if_exists "$project_dir/CLAUDE.md")
cmux_ide_json=$(read_if_exists "$project_dir/.cmux-ide.json")

has_beads="false"
[[ -d "$project_dir/.beads" ]] && has_beads="true"

has_ralph_tui="false"
[[ -d "$project_dir/.ralph-tui" ]] && has_ralph_tui="true"

# --- Build prompt ---

prompt="You are a workspace analyzer. Given project context, return a JSON plan for IDE workspace tabs.

OUTPUT FORMAT (strict JSON, nothing else):
{
  \"tabs\": [
    {\"label\": \"<tab name>\", \"command\": \"<shell command or empty string>\"}
  ],
  \"browser\": {\"port\": <number>} or null
}

RULES:
- Always include a \"gitui\" tab (command: \"gitui\") as the first tab
- If has_ralph_tui is true, add a \"ralph-tui\" tab (command: \"ralph-tui\") after gitui
- Always include a \"terminal\" tab (command: empty string) as the last tab
- If package.json has \"dev\", \"start\", or \"serve\" scripts, add tabs for them between gitui and terminal
  - Label format: the script runner + script name, e.g. \"bun dev\", \"npm run dev\"
  - Command format: the actual run command, e.g. \"bun run dev\", \"npm run start\"
  - Prefer bun if bun.lock or bun.lockb exists, otherwise npm
- If .cmux-ide.json has dev_up.services, use those instead of package.json scripts
  - Use the service \"name\" as label and \"cmd\" as command
- Detect web frameworks for browser:
  - Next.js → port 3000
  - Vite → port 5173
  - Nuxt → port 3000
  - SvelteKit → port 5173
  - Phoenix/Elixir → port 4000
  - If .cmux-ide.json specifies browser.url, extract port from it
- If no web framework detected, browser is null
- Return ONLY the JSON object, no markdown, no explanation

PROJECT CONTEXT:
has_beads: $has_beads
has_ralph_tui: $has_ralph_tui
has_bun_lock: $([[ -f "$project_dir/bun.lock" || -f "$project_dir/bun.lockb" ]] && echo true || echo false)"

if [[ -n "$package_json" ]]; then
  prompt="$prompt

package.json:
$package_json"
fi

if [[ -n "$agents_md" ]]; then
  prompt="$prompt

AGENTS.md:
$agents_md"
fi

if [[ -n "$claude_md" ]]; then
  prompt="$prompt

CLAUDE.md:
$claude_md"
fi

if [[ -n "$cmux_ide_json" ]]; then
  prompt="$prompt

.cmux-ide.json:
$cmux_ide_json"
fi

# --- Call Haiku ---

validate_json() {
  python3 -c "
import json, sys
try:
    plan = json.loads(sys.stdin.read())
    # Validate structure
    assert isinstance(plan.get('tabs'), list), 'tabs must be a list'
    assert len(plan['tabs']) > 0, 'tabs must not be empty'
    for tab in plan['tabs']:
        assert 'label' in tab, 'each tab must have a label'
        assert 'command' in tab, 'each tab must have a command'
    browser = plan.get('browser')
    if browser is not None:
        assert isinstance(browser.get('port'), int), 'browser.port must be an int'
    print(json.dumps(plan))
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
"
}

extract_json() {
  # Try to extract JSON from LLM output (may have markdown fences or prose around it)
  python3 -c "
import sys, re
text = sys.stdin.read()
# Try to find JSON block in markdown fences
m = re.search(r'\`\`\`(?:json)?\s*(\{.*?\})\s*\`\`\`', text, re.DOTALL)
if m:
    print(m.group(1))
else:
    # Try to find raw JSON object
    m = re.search(r'(\{.*\})', text, re.DOTALL)
    if m:
        print(m.group(1))
    else:
        print(text)
"
}

for attempt in 1 2; do
  raw=$(echo "$prompt" | claude -p --model haiku 2>/dev/null) || raw=""
  if [[ -n "$raw" ]]; then
    extracted=$(echo "$raw" | extract_json)
    validated=$(echo "$extracted" | validate_json 2>/dev/null) || validated=""
    if [[ -n "$validated" ]]; then
      echo "$validated"
      exit 0
    fi
  fi
  [[ "$attempt" -eq 1 ]] && sleep 0.5
done

# Fallback
echo "$default_plan"
