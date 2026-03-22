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

# Extract validate_json from analyze-workspace.sh for unit testing
validate_json() {
  python3 -c "
import json, sys
try:
    plan = json.loads(sys.stdin.read())
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
for tab in plan.get('tabs', []):
    label = tab.get('label', '')
    cmd = tab.get('command', '')
    print(f'tab\t{label}\t{cmd}')
browser = plan.get('browser')
if browser and isinstance(browser, dict) and 'port' in browser:
    print(f'browser\t{browser[\"port\"]}')
"
}

# Minimal plan
result=$(echo '{"tabs":[{"label":"gitui","command":"gitui"},{"label":"terminal","command":""}],"browser":null}' | parse_plan)
line1=$(echo "$result" | sed -n '1p')
line2=$(echo "$result" | sed -n '2p')
line_count=$(echo "$result" | wc -l | tr -d ' ')
assert_eq "minimal plan: 2 lines" "2" "$line_count"
assert_eq "minimal plan: first tab is gitui" $'tab\tgitui\tgitui' "$line1"
assert_eq "minimal plan: second tab is terminal" $'tab\tterminal\t' "$line2"

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

# --- Summary ---

echo ""
echo "────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
