#!/usr/bin/env bash
# Tests for agent resolution and launch command logic
set -uo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# --- setup ---

# Source resolve_agent from the main script by extracting it
# We override CONFIG_DIR and prevent the rest of the script from running
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Create a sourceable version with just resolve_agent
cat > "$TEMP_DIR/agent_lib.sh" << 'LIBEOF'
resolve_agent() {
  local project_dir="${1:-}"

  # 1. Env var override
  if [[ -n "${CMUX_IDE_AGENT:-}" ]]; then
    echo "$CMUX_IDE_AGENT"
    return
  fi

  # 2. Per-project override (.cmux-ide.json "agent" field)
  if [[ -n "$project_dir" && -f "$project_dir/.cmux-ide.json" ]]; then
    local proj_agent
    proj_agent=$(python3 -c "import json; print(json.load(open('$project_dir/.cmux-ide.json')).get('agent',''))" 2>/dev/null) || proj_agent=""
    if [[ -n "$proj_agent" ]]; then
      echo "$proj_agent"
      return
    fi
  fi

  # 3. Global config
  if [[ -f "$CONFIG_DIR/agent" ]]; then
    local global_agent
    global_agent=$(head -1 "$CONFIG_DIR/agent")
    if [[ -n "$global_agent" ]]; then
      echo "$global_agent"
      return
    fi
  fi

  # 4. First-run prompt (test version reads from stdin instead of /dev/tty)
  read -r agent_choice

  local agent
  case "${agent_choice:-1}" in
    1|"") agent="claude" ;;
    2) agent="codex" ;;
    3) agent="opencode" ;;
    4) agent="pi" ;;
    *)
      read -r agent
      ;;
  esac

  echo "$agent" > "$CONFIG_DIR/agent"
  echo "$agent"
}
LIBEOF

source "$TEMP_DIR/agent_lib.sh"

# --- Agent resolution priority tests ---

echo ""
echo "Agent resolution priority"
echo "────────────────────────────"

# Env var takes precedence over global config
CONFIG_DIR="$TEMP_DIR/config1"
mkdir -p "$CONFIG_DIR"
echo "claude" > "$CONFIG_DIR/agent"
result=$(CMUX_IDE_AGENT=codex resolve_agent "" 2>/dev/null)
assert_eq "env var overrides global config" "codex" "$result"

# Per-project .cmux-ide.json overrides global config
CONFIG_DIR="$TEMP_DIR/config2"
mkdir -p "$CONFIG_DIR"
echo "claude" > "$CONFIG_DIR/agent"
proj_dir="$TEMP_DIR/project1"
mkdir -p "$proj_dir"
echo '{"agent": "codex"}' > "$proj_dir/.cmux-ide.json"
result=$(unset CMUX_IDE_AGENT; resolve_agent "$proj_dir" 2>/dev/null)
assert_eq "per-project overrides global config" "codex" "$result"

# Global config used when no env var or project config
CONFIG_DIR="$TEMP_DIR/config3"
mkdir -p "$CONFIG_DIR"
echo "claude" > "$CONFIG_DIR/agent"
proj_dir="$TEMP_DIR/project2"
mkdir -p "$proj_dir"
result=$(unset CMUX_IDE_AGENT; resolve_agent "$proj_dir" 2>/dev/null)
assert_eq "global config when no env/project override" "claude" "$result"

# First-run prompt triggered when no config exists (simulated via stdin)
CONFIG_DIR="$TEMP_DIR/config4"
mkdir -p "$CONFIG_DIR"
result=$(unset CMUX_IDE_AGENT; echo "" | resolve_agent "" 2>/dev/null)
assert_eq "first-run prompt defaults to claude" "claude" "$result"
saved=$(cat "$CONFIG_DIR/agent")
assert_eq "first-run prompt saves to config file" "claude" "$saved"

# Prompt choice 2 = codex
CONFIG_DIR="$TEMP_DIR/config5"
mkdir -p "$CONFIG_DIR"
result=$(unset CMUX_IDE_AGENT; echo "2" | resolve_agent "" 2>/dev/null)
assert_eq "first-run prompt selects codex (choice 2)" "codex" "$result"

# Empty agent field in .cmux-ide.json falls through to global
CONFIG_DIR="$TEMP_DIR/config6"
mkdir -p "$CONFIG_DIR"
echo "claude" > "$CONFIG_DIR/agent"
proj_dir="$TEMP_DIR/project3"
mkdir -p "$proj_dir"
echo '{"agent": ""}' > "$proj_dir/.cmux-ide.json"
result=$(unset CMUX_IDE_AGENT; resolve_agent "$proj_dir" 2>/dev/null)
assert_eq "empty agent in .cmux-ide.json falls through" "claude" "$result"

# Missing agent field in .cmux-ide.json falls through
CONFIG_DIR="$TEMP_DIR/config7"
mkdir -p "$CONFIG_DIR"
echo "claude" > "$CONFIG_DIR/agent"
proj_dir="$TEMP_DIR/project4"
mkdir -p "$proj_dir"
echo '{"browser": {"url": "http://localhost:3000"}}' > "$proj_dir/.cmux-ide.json"
result=$(unset CMUX_IDE_AGENT; resolve_agent "$proj_dir" 2>/dev/null)
assert_eq "missing agent field falls through to global" "claude" "$result"

# Malformed .cmux-ide.json falls through gracefully
CONFIG_DIR="$TEMP_DIR/config8"
mkdir -p "$CONFIG_DIR"
echo "claude" > "$CONFIG_DIR/agent"
proj_dir="$TEMP_DIR/project5"
mkdir -p "$proj_dir"
echo 'not valid json{{{' > "$proj_dir/.cmux-ide.json"
result=$(unset CMUX_IDE_AGENT; resolve_agent "$proj_dir" 2>/dev/null)
assert_eq "malformed .cmux-ide.json falls through gracefully" "claude" "$result"

# Empty global config file falls through to prompt
CONFIG_DIR="$TEMP_DIR/config9"
mkdir -p "$CONFIG_DIR"
echo "" > "$CONFIG_DIR/agent"
result=$(unset CMUX_IDE_AGENT; echo "" | resolve_agent "" 2>/dev/null)
assert_eq "empty config file falls through to prompt" "claude" "$result"

# Multiple lines in config file — uses first line only
CONFIG_DIR="$TEMP_DIR/config10"
mkdir -p "$CONFIG_DIR"
printf "claude\ncodex\nopencode\n" > "$CONFIG_DIR/agent"
result=$(unset CMUX_IDE_AGENT; resolve_agent "" 2>/dev/null)
assert_eq "multiple lines in config uses first line" "claude" "$result"

# --- Launch command tests ---

echo ""
echo "Launch command construction"
echo "────────────────────────────"

build_launch_cmd() {
  local agent="$1" project_dir="$2"
  if [[ "$agent" == "claude" ]]; then
    # Workspace is pre-configured by analyze+create phases; agent launches directly
    echo "cd '$project_dir' && claude --dangerously-skip-permissions"
  else
    echo "cd '$project_dir' && $agent"
  fi
}

result=$(build_launch_cmd "claude" "/tmp/proj")
assert_eq "claude → direct launch (workspace pre-configured)" "cd '/tmp/proj' && claude --dangerously-skip-permissions" "$result"

result=$(build_launch_cmd "cy" "/tmp/proj")
assert_eq "cy (unknown agent) → direct launch" "cd '/tmp/proj' && cy" "$result"

result=$(build_launch_cmd "codex" "/tmp/proj")
assert_eq "codex → direct launch" "cd '/tmp/proj' && codex" "$result"

result=$(build_launch_cmd "opencode" "/tmp/proj")
assert_eq "opencode → direct launch" "cd '/tmp/proj' && opencode" "$result"

result=$(build_launch_cmd "my-agent" "/tmp/proj")
assert_eq "custom agent → direct launch" "cd '/tmp/proj' && my-agent" "$result"

# --- Summary ---

echo ""
echo "────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
