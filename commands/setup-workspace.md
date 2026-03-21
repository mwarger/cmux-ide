# Setup Workspace

Dynamically configure this cmux workspace based on project context. Run this once when a workspace is first created.

## Instructions

### 1. Discover context

Run these commands to understand your environment:
```bash
cmux identify --json
cmux list-panes
```

Read these files (if they exist) to understand the project:
- `AGENTS.md` or `CLAUDE.md` — for dev/build/test commands
- `package.json` — for scripts (dev, start, serve) and framework detection
- `.cmux-ide.json` — for explicit overrides (browser URL, profile, services)

### 2. Detect what's needed

Based on what you found:
- **gitui**: Always add (git TUI for staging/diffing)
- **ralph-tui**: Add only if `.beads/` or `.ralph-tui/` directory exists
- **terminal**: Always add (general-purpose shell)
- **Dev servers**: Look for `dev`, `start`, `serve` scripts in package.json or commands in AGENTS.md. Create a tab per service.
- **Browser**: If a web framework is detected (Next.js, Vite, Convex, etc.), create a linked browser workspace

### 3. Create surface tabs

For each tool/service, create a tab in the RIGHT pane. **Always rename the tab immediately after creating it** — this is critical for usability.

For the FIRST tab in the right pane, use the existing surface from the split (don't create a new one). For all subsequent tabs, create a new surface.

**Pattern for each tab:**
```bash
# For first tab: skip new-surface, use existing right surface
# For additional tabs:
cmux new-surface --pane <right_pane_ref> --workspace <ws_ref>

# ALWAYS rename immediately (before sending any commands)
cmux rename-tab --workspace <ws_ref> --surface <surface_ref> "<label>"

# Then send the launch command
cmux send --workspace <ws_ref> --surface <surface_ref> "cd '<project_dir>' && <command>"
cmux send-key --workspace <ws_ref> --surface <surface_ref> Return
```

**Required tab names** (use these exact labels):
| Tool | Tab label |
|------|-----------|
| gitui | `gitui` |
| ralph-tui | `ralph-tui` |
| terminal | `terminal` |
| Dev servers | Use the service name, e.g. `next dev`, `convex dev`, `bun dev` |

### 4. Create linked browser workspace (if web project)

Run:
```bash
~/bin/cmux-ide-modules/browser.sh <ws_ref> "" <project_dir> <port>
```

Default ports: Next.js=3000, Vite=5173, Nuxt=3000, Svelte=5173, Elixir/Phoenix=4000

### 5. Set sidebar metadata

Run:
```bash
~/bin/cmux-ide-modules/status.sh <ws_ref> "" <project_dir>
```

### 6. Save state

Update `.cmux-ide.state.json` in the project directory with the surfaces you created:
```json
{
  "code_workspace": "<ws_ref>",
  "surfaces": {
    "gitui": "<surface_ref>",
    "ralph-tui": "<surface_ref>",
    "terminal": "<surface_ref>"
  },
  "last_opened": "<ISO timestamp>"
}
```

### 7. Print summary

List what you set up so the user knows their workspace is ready.

## Important

- Use `--workspace` and `--surface` flags on ALL cmux commands (you're sending cross-surface)
- Check if port is in use before starting dev servers: `lsof -i :PORT -sTCP:LISTEN`
- Rename every tab with a short, clear label
- Don't start services that are already running
