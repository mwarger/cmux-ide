# cmux-ide

IDE-like workspace launcher for [cmux](https://cmux.com). Creates project workspaces with a two-pane layout, then lets your AI agent dynamically configure surfaces based on your project context.

Supports any terminal-based AI agent: Claude Code, Codex CLI, Aider, or custom agents.

## How it works

```
cmux-ide (bash)
  └── Resolves agent (env var > .cmux-ide.json > global config > first-run prompt)
  └── Creates workspace skeleton (2 panes: AI agent | empty right pane)
  └── Launches agent in project directory
        └── Claude Code: runs /setup-workspace to auto-configure surfaces
        └── Other agents: launched directly in the project dir
```

### Layout

**Code workspace** (two panes, right has surface tabs):
```
┌─────────────────────┬──────────────────────┐
│                     │ [gitui] [rt] [term]  │ ← surface tabs
│    AI Agent         │                      │
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

Workspaces are cross-referenced via `cmux set-status` metadata. The agent can discover the linked browser by running `cmux list-status`.

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

### Claude Code integration

When the agent is `claude`, cmux-ide:
- Uses Haiku to analyze project context and determine what tabs/browser to create
- Mechanically creates all surfaces from the JSON plan (~3-5s total)
- Creates gitui, terminal, dev server tabs, and linked browser workspaces
- Sets sidebar metadata (git branch, dirty files, browser link)

Every Claude Code session automatically knows about its workspace via:
- **cmux CLI** — gives all sessions the ability to `read-screen`, `send`, `new-split`, `browser` and more on any surface
- **SessionStart hook** — injects workspace state (surfaces, browser link, git info) into every session on launch

## Usage

```bash
# Launch workspace for current directory
cmux-ide

# Launch workspace for a specific project
cmux-ide ~/dev/my-project

# Override agent for one session
CMUX_IDE_AGENT=codex cmux-ide ~/dev/my-project
```

## Installation

```bash
git clone git@github.com:mwarger/cmux-ide.git ~/dev/cmux-ide
cd ~/dev/cmux-ide
./install.sh
```

The installer symlinks everything into place. See the output for manual steps (hooks).

### Prerequisites

- [cmux](https://cmux.com) (macOS terminal for AI agents)
- An AI agent (one of):
  - [Claude Code](https://claude.com/claude-code) — full integration with smart workspace detection
  - [Codex CLI](https://github.com/openai/codex) — launches directly
  - [OpenCode](https://opencode.ai) — launches directly
  - [Pi](https://pi.ai) — launches directly
  - Any terminal-based AI agent
- [gitui](https://github.com/extrawurst/gitui) (`brew install gitui`) — optional, for Claude Code auto-setup

## File structure

```
bin/cmux-ide                    # Main launcher (workspace skeleton + agent launch)
modules/browser.sh              # Creates linked browser workspace with metadata cross-refs
modules/status.sh               # Sets sidebar metadata (git info, browser link)
hooks/session-hook              # SessionStart hook — injects workspace context (Claude Code)
commands/setup-workspace.md     # /setup-workspace skill — dynamic surface setup (Claude Code)
commands/cmux.md                # /cmux slash command — quick reference (Claude Code)
skills/using-cmux/SKILL.md      # Full cmux skill — browser automation, notifications, etc.
install.sh                      # Symlink installer
tests/test-agent-resolution.sh  # Agent resolution and launch tests
```

## How workspace linking works

When a browser workspace is created, both workspaces get cross-referenced:

```
Code workspace sidebar:     browser=workspace:23  (green globe icon)
Browser workspace sidebar:  code=workspace:22     (blue terminal icon)
```

The agent discovers this by running `cmux list-status` and reading the `browser` key. The linking info is also stored in `~/.config/cmux-ide/links.json` and per-project `.cmux-ide.state.json`.
