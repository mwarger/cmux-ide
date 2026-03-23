# cmux-ide

Project workspaces for [cmux](https://cmux.com) that set themselves up. Point it at a directory, and it analyzes your project, creates the right tabs and browser windows, then drops you into your AI agent — all in about 3 seconds.

```
  cmux-ide · build-with-gleam (claude)

  ✓ Analyzing project...
  ✓ Creating workspace...
  ✓ Launching claude
```

**Flat layout** (simple projects — two panes, right has surface tabs):
```
┌─────────────────────┬──────────────────────┐
│                     │ [gitui] [rt] [term]  │ ← surface tabs
│    AI Agent         │                      │
│   (full left pane)  │   (active tab)       │
│                     │                      │
└─────────────────────┴──────────────────────┘
```

**Single-service layout** (projects with a dev server):
```
┌─────────────────────┬──────────────────────┐
│                     │ [gitui] [rt] [term]  │ ← tools (top-right)
│    AI Agent         ├──────────────────────┤
│   (full left pane)  │ [bun dev]            │ ← services (bottom-right)
│                     │                      │
└─────────────────────┴──────────────────────┘
```

**Full-stack layout** (multi-service projects — services split side-by-side):
```
┌─────────────────────┬──────────────────────┐
│                     │ [gitui] [rt] [term]  │ ← tools (top-right)
│    AI Agent         ├───────────┬──────────┤
│   (full left pane)  │ admin_demo│ admin_api│ ← services (bottom-right, split)
│                     │           │          │
└─────────────────────┴───────────┴──────────┘
```

**Browser workspace** (linked, full window, separate sidebar entry):
```
┌────────────────────────────────────────────┐
│                                            │
│         browser (localhost:PORT)            │
│           full window                      │
│                                            │
└────────────────────────────────────────────┘
```

Workspaces are cross-referenced via sidebar metadata. The agent can discover the linked browser by running `cmux list-status`.

## Quick start

```bash
# Launch workspace for current directory
cmux-ide

# Launch workspace for a specific project
cmux-ide ~/dev/my-project

# Override agent for one session
CMUX_IDE_AGENT=codex cmux-ide ~/dev/my-project
```

Supports any terminal-based AI agent: Claude Code, Codex CLI, OpenCode, Aider, or custom agents.

## How it works

Setup happens in two phases before the agent launches:

### 1. Analyze

Haiku reads your project context — `package.json`, `CLAUDE.md`, `.cmux-ide.json` — detects frameworks, dev servers, and tooling, then picks a layout archetype and returns a JSON plan.

Layout archetypes:
- **Flat** — simple projects with no dev servers. Two panes: agent left, tools right.
- **Single-service** — projects with one dev server. Three panes: agent left, tools top-right, service bottom-right.
- **Full-stack** — multi-service projects (e.g. frontend + backend). Four panes: agent left, tools top-right, services split side-by-side bottom-right.

### 2. Create

Bash mechanically executes the plan: creates pane splits matching the archetype, adds tabs (gitui, dev servers, terminal), opens a linked browser workspace if a web framework was detected, and sets sidebar metadata (git branch, dirty files, browser link).

### 3. Launch

The agent starts in the left pane with the workspace already fully configured.

## Agent configuration

cmux-ide resolves which agent to launch using this priority:

1. **Env var**: `CMUX_IDE_AGENT=codex cmux-ide ~/project`
2. **Per-project**: `"agent"` field in `.cmux-ide.json`
3. **Global config**: `~/.config/cmux-ide/agent` (single line)
4. **First-run prompt**: Interactive menu on first launch

### Per-project config

Optional `.cmux-ide.json` in your project root:

```json
{
  "agent": "codex",
  "browser": {
    "url": "http://localhost:3000",
    "auto_open": true
  },
  "dev_up": {
    "services": [
      { "name": "Next.js", "cmd": "bun run dev", "port": 3000 },
      { "name": "Convex", "cmd": "bunx convex dev" }
    ]
  }
}
```

## Claude Code integration

When the agent is `claude`, cmux-ide provides deeper integration:

- **SessionStart hook** — injects workspace state (surfaces, browser link, git info) into every Claude Code session automatically
- **cmux skill** — gives Claude the ability to `read-screen`, `send`, `new-split`, `browser` and more on any surface
- **Sidebar metadata** — git branch, dirty file count, linked browser workspace

This means Claude can start/stop dev servers, read terminal output from other tabs, open browser pages, and manage the workspace layout without any manual setup.

## Installation

### Prerequisites

- [cmux](https://cmux.com) (macOS terminal for AI agents)
- An AI agent (one of):
  - [Claude Code](https://claude.com/claude-code) — full integration with smart workspace detection
  - [Codex CLI](https://github.com/openai/codex) — launches directly
  - [OpenCode](https://opencode.ai) — launches directly
  - Any terminal-based AI agent
- [gitui](https://github.com/extrawurst/gitui) (`brew install gitui`) — optional, used in default tab layout

### Install

```bash
git clone git@github.com:mwarger/cmux-ide.git ~/dev/cmux-ide
cd ~/dev/cmux-ide
./install.sh
```

The installer symlinks everything into place and prints manual steps for hooking into Claude Code (SessionStart and Notification hooks in `~/.claude/settings.json`).

## Project structure

```
bin/cmux-ide                       # Main launcher (agent resolution, workspace creation, agent launch)
modules/analyze-workspace.sh       # Phase 1: Haiku analyzes project, picks archetype, returns JSON plan
modules/create-surfaces.sh         # Phase 2: creates zone layout + tabs from plan (flat, single-service, full-stack)
modules/new-tab.sh                 # Helper: creates a single surface tab in a pane
modules/browser.sh                 # Creates linked browser workspace with metadata cross-refs
modules/status.sh                  # Sets sidebar metadata (git info, browser link)
hooks/session-hook                 # SessionStart hook — injects workspace context (Claude Code)
commands/cmux.md                   # /cmux slash command — quick reference (Claude Code)
skills/using-cmux/SKILL.md         # Full cmux skill — browser automation, notifications, etc.
install.sh                         # Symlink installer
tests/test-agent-resolution.sh     # Agent resolution and launch tests
tests/test-workspace-setup.sh      # Workspace setup integration tests
```
