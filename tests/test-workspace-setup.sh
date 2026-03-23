#!/usr/bin/env bash
# Tests for two-phase workspace setup (analyze + create)
# These test the JSON parsing/validation logic without requiring cmux to be running.
set -uo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- test harness ---

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $label"
    ((PASS++))
  else
    echo "  ✗ $label"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    ((FAIL++))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  ✓ $label"
    ((PASS++))
  else
    echo "  ✗ $label"
    echo "    expected to contain: '$needle'"
    echo "    actual: '$haystack'"
    ((FAIL++))
  fi
}

assert_exit_code() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $label"
    ((PASS++))
  else
    echo "  ✗ $label"
    echo "    expected exit code: $expected"
    echo "    actual exit code:   $actual"
    ((FAIL++))
  fi
}

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# --- JSON validation tests ---

echo "JSON plan validation"
echo "────────────────────────────"

# Extract validate_json from analyze-workspace.sh for unit testing (supports both formats)
validate_json() {
  python3 -c "
import json, sys
try:
    plan = json.loads(sys.stdin.read())
    if 'zones' in plan:
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

# Valid minimal plan
result=$(echo '{"tabs":[{"label":"gitui","command":"gitui"},{"label":"terminal","command":""}],"browser":null}' | validate_json 2>/dev/null)
rc=$?
assert_exit_code "valid minimal plan passes" 0 "$rc"
assert_contains "valid plan has gitui" '"gitui"' "$result"

# Valid plan with browser
result=$(echo '{"tabs":[{"label":"gitui","command":"gitui"},{"label":"bun dev","command":"bun run dev"},{"label":"terminal","command":""}],"browser":{"port":3000}}' | validate_json 2>/dev/null)
rc=$?
assert_exit_code "valid plan with browser passes" 0 "$rc"
assert_contains "plan has browser port" '"port": 3000' "$result"

# Empty tabs array
echo '{"tabs":[],"browser":null}' | validate_json 2>/dev/null
rc=$?
assert_exit_code "empty tabs rejected" 1 "$rc"

# Missing command field
echo '{"tabs":[{"label":"gitui"}],"browser":null}' | validate_json 2>/dev/null
rc=$?
assert_exit_code "missing command rejected" 1 "$rc"

# Missing label field
echo '{"tabs":[{"command":"gitui"}],"browser":null}' | validate_json 2>/dev/null
rc=$?
assert_exit_code "missing label rejected" 1 "$rc"

# Browser with non-integer port
echo '{"tabs":[{"label":"t","command":""}],"browser":{"port":"3000"}}' | validate_json 2>/dev/null
rc=$?
assert_exit_code "string port rejected" 1 "$rc"

# Not JSON at all
echo 'this is not json' | validate_json 2>/dev/null
rc=$?
assert_exit_code "non-JSON rejected" 1 "$rc"

# --- JSON extraction tests ---

echo ""
echo "JSON extraction from LLM output"
echo "────────────────────────────────"

extract_json() {
  python3 -c "
import sys, re
text = sys.stdin.read()
m = re.search(r'\`\`\`(?:json)?\s*(\{.*?\})\s*\`\`\`', text, re.DOTALL)
if m:
    print(m.group(1))
else:
    m = re.search(r'(\{.*\})', text, re.DOTALL)
    if m:
        print(m.group(1))
    else:
        print(text)
"
}

# Raw JSON
result=$(echo '{"tabs":[{"label":"gitui","command":"gitui"}],"browser":null}' | extract_json)
assert_contains "raw JSON extracted" '"tabs"' "$result"

# Markdown fenced JSON
result=$(printf 'Here is the plan:\n```json\n{"tabs":[{"label":"gitui","command":"gitui"}],"browser":null}\n```\n' | extract_json)
assert_contains "fenced JSON extracted" '"tabs"' "$result"

# JSON with prose before
result=$(printf 'Based on the project context, here is my analysis:\n{"tabs":[{"label":"gitui","command":"gitui"}],"browser":null}' | extract_json)
assert_contains "JSON with prose extracted" '"tabs"' "$result"

# --- Plan parsing tests (create-surfaces JSON → tab-separated) ---

echo ""
echo "Plan JSON → tab-separated parsing"
echo "────────────────────────────────"

parse_plan() {
  python3 -c "
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
"
}

# Minimal flat plan (now emits format line first)
result=$(echo '{"tabs":[{"label":"gitui","command":"gitui"},{"label":"terminal","command":""}],"browser":null}' | parse_plan)
line1=$(echo "$result" | sed -n '1p')
line2=$(echo "$result" | sed -n '2p')
line3=$(echo "$result" | sed -n '3p')
line_count=$(echo "$result" | wc -l | tr -d ' ')
assert_eq "minimal plan: 3 lines (format + 2 tabs)" "3" "$line_count"
assert_eq "minimal plan: format line" $'format\tflat\tdefault' "$line1"
assert_eq "minimal plan: first tab is gitui" $'tab\tgitui\tgitui' "$line2"
assert_eq "minimal plan: second tab is terminal" $'tab\tterminal\t' "$line3"

# Plan with browser
result=$(echo '{"tabs":[{"label":"gitui","command":"gitui"}],"browser":{"port":5173}}' | parse_plan)
browser_line=$(echo "$result" | grep '^browser')
assert_eq "browser port parsed" $'browser\t5173' "$browser_line"

# Plan without browser
result=$(echo '{"tabs":[{"label":"gitui","command":"gitui"}],"browser":null}' | parse_plan)
browser_line=$(echo "$result" | grep '^browser' || echo "")
assert_eq "null browser produces no browser line" "" "$browser_line"

# --- Surface ref extraction tests ---

echo ""
echo "Surface ref extraction from cmux output"
echo "────────────────────────────────────────"

# new-split output
result=$(echo "OK surface:55 workspace:1" | grep -oE 'surface:[0-9]+' | head -1)
assert_eq "surface ref from new-split" "surface:55" "$result"

# tree output → pane ref for a surface
tree_output='    ├── pane pane:40
    │   ├── surface surface:55 [terminal] "gitui"
    │   └── surface surface:56 [terminal] "terminal" [selected]'
result=$(echo "$tree_output" | grep -B1 "surface:55" | grep -oE 'pane:[0-9]+' | head -1)
assert_eq "pane ref from tree for surface" "pane:40" "$result"

# new-tab.sh output filtering (may include rename OK + surface ref)
multi_output=$'OK action=rename tab=tab:56 workspace=workspace:1\nsurface:56'
result=$(echo "$multi_output" | grep -oE 'surface:[0-9]+' | tail -1)
assert_eq "surface ref from multi-line new-tab output" "surface:56" "$result"

# --- Default plan tests ---

echo ""
echo "Default plan for non-claude agents"
echo "────────────────────────────────────"

default_plan='{"tabs":[{"label":"gitui","command":"gitui"},{"label":"terminal","command":""}],"browser":null}'
result=$(echo "$default_plan" | validate_json 2>/dev/null)
rc=$?
assert_exit_code "default plan validates" 0 "$rc"

parsed=$(echo "$default_plan" | parse_plan)
tab_count=$(echo "$parsed" | grep -c '^tab')
assert_eq "default plan has 2 tabs" "2" "$tab_count"
format_line=$(echo "$parsed" | head -1)
assert_eq "default plan parsed as flat" $'format\tflat\tdefault' "$format_line"

# --- Zones format validation tests ---

echo ""
echo "Zones format validation"
echo "────────────────────────────"

# Valid single-service zones plan
result=$(echo '{"archetype":"single-service","zones":{"tools":{"position":"top-right","tabs":[{"label":"gitui","command":"gitui"},{"label":"terminal","command":""}]},"services":{"position":"bottom-right","style":"tabs","tabs":[{"label":"bun dev","command":"bun run dev"}]}},"browser":{"port":3000}}' | validate_json 2>/dev/null)
rc=$?
assert_exit_code "valid single-service zones plan passes" 0 "$rc"
assert_contains "zones plan has archetype" '"archetype"' "$result"

# Valid full-stack zones plan
result=$(echo '{"archetype":"full-stack","zones":{"tools":{"position":"top-right","tabs":[{"label":"gitui","command":"gitui"},{"label":"terminal","command":""}]},"services":{"position":"bottom-right","style":"split","tabs":[{"label":"bun dev","command":"bun run dev"},{"label":"convex","command":"bunx convex dev"}]}},"browser":{"port":3000}}' | validate_json 2>/dev/null)
rc=$?
assert_exit_code "valid full-stack zones plan passes" 0 "$rc"
assert_contains "full-stack plan has split style" '"split"' "$result"

# Empty zone tabs rejected
echo '{"archetype":"single-service","zones":{"tools":{"position":"top-right","tabs":[]}},"browser":null}' | validate_json 2>/dev/null
rc=$?
assert_exit_code "empty zone tabs rejected" 1 "$rc"

# Zone missing position rejected
echo '{"archetype":"single-service","zones":{"tools":{"tabs":[{"label":"gitui","command":"gitui"}]}},"browser":null}' | validate_json 2>/dev/null
rc=$?
assert_exit_code "zone missing position rejected" 1 "$rc"

# Zones format without archetype rejected
echo '{"zones":{"tools":{"position":"top-right","tabs":[{"label":"gitui","command":"gitui"}]}},"browser":null}' | validate_json 2>/dev/null
rc=$?
assert_exit_code "zones without archetype rejected" 1 "$rc"

# Neither tabs nor zones rejected
echo '{"browser":null}' | validate_json 2>/dev/null
rc=$?
assert_exit_code "neither tabs nor zones rejected" 1 "$rc"

# --- Zones format parsing tests ---

echo ""
echo "Zones plan JSON → tab-separated parsing"
echo "────────────────────────────────────────"

# Single-service zones plan
result=$(echo '{"archetype":"single-service","zones":{"tools":{"position":"top-right","tabs":[{"label":"gitui","command":"gitui"},{"label":"terminal","command":""}]},"services":{"position":"bottom-right","style":"tabs","tabs":[{"label":"bun dev","command":"bun run dev"}]}},"browser":{"port":3000}}' | parse_plan)
format_line=$(echo "$result" | head -1)
assert_eq "zones format detected" $'format\tzones\tsingle-service' "$format_line"
zone_tab_count=$(echo "$result" | grep -c '^zone_tab')
assert_eq "zones plan has 3 zone_tab lines" "3" "$zone_tab_count"
tools_count=$(echo "$result" | grep -c '^zone_tab	tools	')
assert_eq "2 tools tabs" "2" "$tools_count"
services_count=$(echo "$result" | grep -c '^zone_tab	services	')
assert_eq "1 services tab" "1" "$services_count"
browser_line=$(echo "$result" | grep '^browser')
assert_eq "zones plan browser port" $'browser\t3000' "$browser_line"

# Full-stack zones plan
result=$(echo '{"archetype":"full-stack","zones":{"tools":{"position":"top-right","tabs":[{"label":"gitui","command":"gitui"}]},"services":{"position":"bottom-right","style":"split","tabs":[{"label":"bun dev","command":"bun run dev"},{"label":"convex","command":"bunx convex dev"}]}},"browser":null}' | parse_plan)
format_line=$(echo "$result" | head -1)
assert_eq "full-stack format detected" $'format\tzones\tfull-stack' "$format_line"
# Check style field is preserved
svc_line=$(echo "$result" | grep '^zone_tab	services	' | head -1)
assert_contains "services style is split" $'\tsplit\t' "$svc_line"

# Old flat format backward compat
result=$(echo '{"tabs":[{"label":"gitui","command":"gitui"}],"browser":null}' | parse_plan)
format_line=$(echo "$result" | head -1)
assert_eq "flat format backward compat" $'format\tflat\tdefault' "$format_line"
tab_count=$(echo "$result" | grep -c '^tab')
assert_eq "flat format has tab lines" "1" "$tab_count"

# --- Summary ---

echo ""
echo "────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
