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

# --- Count dev scripts and services for archetype signals ---

dev_script_count=0
service_count=0

if [[ -n "$cmux_ide_json" ]]; then
  service_count=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    svcs = d.get('dev_up', {}).get('services', [])
    print(len(svcs))
except: print(0)
" <<< "$cmux_ide_json" 2>/dev/null) || service_count=0
fi

if [[ -n "$package_json" ]] && [[ "$service_count" -eq 0 ]]; then
  dev_script_count=$(python3 -c "
import json, sys
try:
    pkg = json.loads(sys.stdin.read())
    scripts = pkg.get('scripts', {})
    count = sum(1 for k in scripts if k in ('dev', 'start', 'serve'))
    print(count)
except: print(0)
" <<< "$package_json" 2>/dev/null) || dev_script_count=0
fi

has_bun_lock="$([[ -f "$project_dir/bun.lock" || -f "$project_dir/bun.lockb" ]] && echo true || echo false)"

# --- Build prompt ---

prompt="You are a workspace analyzer. Given project context, return a JSON plan for IDE workspace tabs.

ARCHETYPE CLASSIFICATION:
Based on the project, classify it as one of:
- \"library\": No dev/start/serve scripts, no web framework, no services (e.g. a Rust crate, Go library)
- \"single-service\": Exactly 1 dev server (1 dev script or 1 service in .cmux-ide.json)
- \"full-stack\": 2+ dev servers (2+ dev scripts or 2+ services)
- \"default\": Uncertain or unclear

OUTPUT FORMAT (strict JSON, nothing else):

For \"library\" or \"default\" archetype — use FLAT format:
{
  \"tabs\": [
    {\"label\": \"<tab name>\", \"command\": \"<shell command or empty string>\"}
  ],
  \"browser\": {\"port\": <number>} or null
}

For \"single-service\" or \"full-stack\" archetype — use ZONES format:
{
  \"archetype\": \"single-service\" or \"full-stack\",
  \"zones\": {
    \"tools\": {
      \"position\": \"top-right\",
      \"tabs\": [
        {\"label\": \"gitui\", \"command\": \"gitui\"},
        {\"label\": \"terminal\", \"command\": \"\"}
      ]
    },
    \"services\": {
      \"position\": \"bottom-right\",
      \"style\": \"tabs\" or \"split\",
      \"tabs\": [
        {\"label\": \"<service name>\", \"command\": \"<service command>\"}
      ]
    }
  },
  \"browser\": {\"port\": <number>} or null
}

RULES:
- tools zone: gitui first, ralph-tui if detected, terminal last
- services zone: style \"tabs\" for single-service, style \"split\" for full-stack
- For flat format: Always include gitui first, ralph-tui if detected, terminal last, dev servers in between
- If package.json has \"dev\", \"start\", or \"serve\" scripts, those are the dev servers
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
has_bun_lock: $has_bun_lock
dev_script_count: $dev_script_count
service_count: $service_count"

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
    if 'zones' in plan:
        # Zones format validation
        zones = plan['zones']
        assert isinstance(zones, dict), 'zones must be an object'
        for zone_name, zone in zones.items():
            assert 'position' in zone, f'zone {zone_name} must have position'
            tabs = zone.get('tabs', [])
            assert isinstance(tabs, list) and len(tabs) > 0, f'zone {zone_name} must have non-empty tabs'
            for tab in tabs:
                assert 'label' in tab, f'zone {zone_name}: each tab must have a label'
                assert 'command' in tab, f'zone {zone_name}: each tab must have a command'
        assert 'archetype' in plan, 'zones format requires archetype field'
    elif 'tabs' in plan:
        # Flat format validation
        assert isinstance(plan['tabs'], list), 'tabs must be a list'
        assert len(plan['tabs']) > 0, 'tabs must not be empty'
        for tab in plan['tabs']:
            assert 'label' in tab, 'each tab must have a label'
            assert 'command' in tab, 'each tab must have a command'
    else:
        assert False, 'plan must have either zones or tabs key'
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
