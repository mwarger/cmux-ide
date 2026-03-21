# cmux-ide

IDE-like workspace launcher for [cmux](https://cmux.com). Creates project workspaces with a two-pane layout, then lets Claude Code dynamically configure surfaces based on your project context.

## How it works

```
cmux-ide (bash)
  └── Creates workspace skeleton (2 panes: Claude Code | empty right pane)
  └── Launches cy /setup-workspace
        └── Claude reads AGENTS.md, package.json, .cmux-ide.json
        └── Dynamically creates surface tabs:
            - gitui (always)
            - ralph-tui (if .beads/ or .ralph-tui/ exists)
            - terminal (always)
            - Dev server tabs (from package.json scripts)
            - Linked browser workspace (if web framework detected)
            - Sidebar metadata (git branch, dirty files, browser link)
```

### Layout

**Code workspace** (two panes, right has surface tabs):
```
┌─────────────────────┬──────────────────────┐
│                     │ [gitui] [rt] [term]  │ ← surface tabs
│    Claude Code      │                      │
│   (full left pane)  │   (active tab)       │
│                     │                      │
└─────────────────────┴──────────────────────┘
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

Workspaces are cross-referenced via `cmux set-status` metadata. Claude Code can discover the linked browser by running `cmux list-status`.

## Persistent IDE management

Every cy session automatically knows about its workspace via:

- **cmuxlayer MCP server** — gives all cy sessions tools to `read_screen`, `send_input`, `spawn_agent`, `stop_agent` on any surface
- **SessionStart hook** — injects workspace state (surfaces, browser link, git info) into every cy session on launch

This means any cy session can:
- Start/restart dev servers
- Diagnose compilation errors by reading terminal output
- Open a browser workspace on demand
- Manage the IDE layout at any time

## Usage

```bash
# Interactive project picker (favorites, recents, project listing)
cmux-ide

# Launch a specific project
cmux-ide ~/dev/my-project

# Quick-switch by name (matches favorites)
ide my-project
ide my-app

# Manage favorites
cmux-ide --add-fav ~/dev/my-project
cmux-ide --rm-fav
cmux-ide --list-fav
```

## Project-level config

Optional `.cmux-ide.json` in your project root:

```json
{
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

## Installation

```bash
git clone git@github.com:mwarger/cmux-ide.git ~/dev/cmux-ide
cd ~/dev/cmux-ide
./install.sh
```

The installer symlinks everything into place. See the output for manual steps (MCP server, hooks, shell alias).

### Prerequisites

- [cmux](https://cmux.com) (macOS terminal for AI agents)
- [Claude Code](https://claude.com/claude-code) (`cy` alias for `claude --dangerously-skip-permissions`)
- [gitui](https://github.com/extrawurst/gitui) (`brew install gitui`)
- [cmuxlayer](https://github.com/EtanHey/cmuxlayer) MCP server (for persistent IDE management)

## File structure

```
bin/cmux-ide                    # Main launcher (workspace skeleton + cy launch)
modules/browser.sh              # Creates linked browser workspace with metadata cross-refs
modules/status.sh               # Sets sidebar metadata (git info, browser link)
hooks/session-hook              # SessionStart hook — injects workspace context
commands/setup-workspace.md     # /setup-workspace skill — dynamic surface setup
commands/cmux.md                # /cmux slash command — quick reference
skills/using-cmux/SKILL.md      # Full cmux skill — browser automation, notifications, etc.
install.sh                      # Symlink installer
```

## How workspace linking works

When a browser workspace is created, both workspaces get cross-referenced:

```
Code workspace sidebar:     browser=workspace:23  (green globe icon)
Browser workspace sidebar:  code=workspace:22     (blue terminal icon)
```

Claude Code discovers this by running `cmux list-status` and reading the `browser` key. The linking info is also stored in `~/.config/cmux-ide/links.json` and per-project `.cmux-ide.state.json`.
