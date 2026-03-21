---
name: using-cmux
description: Use when running inside cmux terminal and need split panes for parallel work, browser automation with element refs, notifications for attention, or topology navigation. Triggers include CMUX_* environment variables present, need to run subagents in isolation, web automation tasks, or signaling completion to user.
---

# Using cmux

cmux is a macOS terminal built for AI coding agents. You're running inside it when `CMUX_SOCKET_PATH` is set.

## Quick Orientation

```bash
cmux identify --json    # Where am I? (workspace, pane, surface)
cmux list-workspaces    # All workspaces with refs
```

**Hierarchy:** Window → Workspace (sidebar tab) → Pane (split) → Surface (terminal/browser)

**Refs format:** `workspace:2`, `pane:1`, `surface:7` (prefer over UUIDs)

## Split Panes for Subagents

**When to use:** Long-running tasks, isolated subagent sessions, development servers needing monitoring

**When NOT to use:** Quick bash commands that complete in seconds, non-interactive scripts

```bash
# Split current pane
cmux new-split right                    # Creates pane:2 with new surface
cmux new-split down                     # Horizontal split

# Move between panes
cmux focus-pane --pane pane:2

# Send commands to specific surface
cmux send --surface surface:5 "claude --dangerously-skip-permissions\n"
```

**Why use this:** Each split gets its own terminal context. Subagents don't interfere with your main session.

## Browser Automation

**Workflow:** Open → Snapshot (get refs) → Act with refs → Wait for changes

### Opening & Navigation

```bash
# Open browser (returns surface:N)
cmux browser open https://example.com --json

# Navigate
cmux browser surface:7 goto https://google.com
cmux browser surface:7 back
cmux browser surface:7 forward
cmux browser surface:7 reload

# Get current state
cmux browser surface:7 get url
cmux browser surface:7 get title
```

### Snapshot & Element Refs

**ALWAYS use `--interactive` to get element refs:**

```bash
cmux browser surface:7 snapshot --interactive
```

Returns elements with `[ref=eN]` markers:
```
heading "Welcome" [ref=e1]
button "Submit" [ref=e2]
textbox [ref=e3]
link "Learn more" [ref=e4]
```

**Use refs for ALL interactions** - they survive minor DOM changes:

```bash
cmux browser surface:7 click e2           # Click button
cmux browser surface:7 dblclick e5        # Double-click
cmux browser surface:7 hover e3           # Hover over element
cmux browser surface:7 focus e3           # Focus element
```

### Form Interaction

```bash
cmux browser surface:7 fill e3 "hello"          # Fill input (empty string clears)
cmux browser surface:7 type e3 "world"          # Type text (appends)
cmux browser surface:7 select e7 "option-val"   # Select dropdown option
cmux browser surface:7 check e8               # Check checkbox
cmux browser surface:7 uncheck e8             # Uncheck checkbox
```

### Keyboard & Scrolling

```bash
cmux browser surface:7 press Enter                # Press key
cmux browser surface:7 keydown Shift
cmux browser surface:7 keyup Shift
cmux browser surface:7 scroll --dy 500           # Scroll down 500px
cmux browser surface:7 scroll --selector "#list" --dy 200  # Scroll within element
```

### Waiting & Verification

```bash
# Wait for conditions
cmux browser surface:7 wait --selector "#loaded" --timeout-ms 10000
cmux browser surface:7 wait --text "Success" --timeout-ms 5000
cmux browser surface:7 wait --url-contains "/dashboard"
cmux browser surface:7 wait --load-state complete --timeout-ms 15000
cmux browser surface:7 wait --function "document.readyState === 'complete'"

# Post-action verification
cmux browser surface:7 click e2 --snapshot-after --json    # Get fresh refs after click
```

### Finding Elements

```bash
cmux browser surface:7 find role button           # Find by ARIA role
cmux browser surface:7 find text "Submit"        # Find by visible text
cmux browser surface:7 find label "Email"        # Find by form label
cmux browser surface:7 find placeholder "Search" # Find by placeholder
cmux browser surface:7 find testid "submit-btn"  # Find by data-testid
cmux browser surface:7 find first               # First matching element
cmux browser surface:7 find last                # Last matching element
cmux browser surface:7 find nth 3               # Nth matching element
```

### Getting Page Data

```bash
cmux browser surface:7 get text e3              # Get element text
cmux browser surface:7 get html e3              # Get element HTML
cmux browser surface:7 get value e3             # Get input value
cmux browser surface:7 get attr e3 "href"       # Get attribute
cmux browser surface:7 get count "button"       # Count matching elements
cmux browser surface:7 get box e3               # Get bounding box
cmux browser surface:7 get styles e3            # Get computed styles
```

### JavaScript Evaluation

```bash
cmux browser surface:7 eval 'document.querySelector("h1").innerText'
cmux browser surface:7 eval 'window.location.href'
cmux browser surface:7 eval 'Array.from(document.querySelectorAll("a")).map(a => a.href)'
```

### Session & State

```bash
# Cookies
cmux browser surface:7 cookies get
cmux browser surface:7 cookies set --name "session" --value "abc123"
cmux browser surface:7 cookies clear

# Storage
cmux browser surface:7 storage local get --key "user"
cmux browser surface:7 storage session set --key "token" --value "xyz"
cmux browser surface:7 storage local clear

# State persistence (for auth sessions)
cmux browser surface:7 state save ~/.browser-state/session1.json
cmux browser surface:7 state load ~/.browser-state/session1.json

# Browser tabs (within surface)
cmux browser surface:7 tab list
cmux browser surface:7 tab new
cmux browser surface:7 tab switch 2
cmux browser surface:7 tab close 2
```

### Diagnostics

```bash
cmux browser surface:7 console list        # View console messages
cmux browser surface:7 console clear
cmux browser surface:7 errors list          # View JavaScript errors
cmux browser surface:7 errors clear
cmux browser surface:7 highlight e3          # Visually highlight element
cmux browser surface:7 screenshot            # Capture screenshot
cmux browser surface:7 download wait --timeout-ms 10000  # Wait for download
```

### WKWebView Limitations (not_supported)

These return `not_supported` - use alternatives:
- `viewport.set` - Cannot emulate viewports
- `geolocation.set` - Cannot fake location
- `offline.set` - Cannot simulate offline
- `trace.start|stop` - No tracing
- `network.route|unroute|requests` - No request interception
- `screencast.start|stop` - No video recording
- `input_mouse|input_keyboard|input_touch` - Use high-level commands instead

## Notifications: cmux vs osascript

### cmux notify (In-App)

```bash
cmux notify --title "Claude Code" --body "Waiting for approval"
```

**What it does:**
- Blue ring around your pane
- Sidebar notification badge
- Entry in notification panel (Cmd+Shift+U to jump to unread)
- Tied to your workspace/surface context

**Use for:** Workflow notifications, attention signals within cmux, agent state changes.

### osascript (System-Level)

```bash
osascript -e 'display notification "Build complete" with title "Claude Code" subtitle "Tests" sound name "Submarine"'
```

**What it does:**
- macOS Notification Center notification
- Can play sounds (`sound name "Submarine"`, `sound name "Glass"`, etc.)
- Persists in notification history
- Visible when user is in OTHER apps
- Can have action buttons (limited)

**Use for:**
- Critical alerts when user is outside cmux
- Sound-based attention getters
- Notifications that must persist after cmux closes
- System-level integration

### Decision Matrix

| Need | Use |
|------|-----|
| User in cmux, needs to know agent is waiting | `cmux notify` |
| User in another app, critical alert | `osascript` with sound |
| Build/test complete, informational | `cmux notify` |
| Error requiring immediate attention | `osascript` with sound |
| Notification must survive app restart | `osascript` |
| Context-aware (which pane/workspace) | `cmux notify` |

## Hook Integration

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          { "type": "command", "command": "cmux notify --title 'Claude Code' --body 'Waiting for input'" }
        ]
      },
      {
        "matcher": "permission_prompt",
        "hooks": [
          { "type": "command", "command": "cmux notify --title 'Claude Code' --subtitle 'Permission' --body 'Approval needed'" }
        ]
      }
    ]
  }
}
```

## Environment Variables (Auto-Set)

| Variable | Use |
|----------|-----|
| `CMUX_SOCKET_PATH` | Control socket (CLI uses automatically) |
| `CMUX_WORKSPACE_ID` | Your workspace UUID |
| `CMUX_SURFACE_ID` | Your surface UUID |

**Tip:** Commands default to your current workspace/surface when flags omitted.

## Command Quick Reference

| Task | Command |
|------|---------|
| Where am I? | `cmux identify --json` |
| New workspace | `cmux new-workspace --cwd /path` |
| Split pane | `cmux new-split right\|down` |
| List topology | `cmux list-workspaces` / `list-panes` |
| Focus something | `cmux select-workspace --workspace workspace:2` |
| Send keystrokes | `cmux send "command\n"` |
| Flash attention | `cmux trigger-flash` |
| Open browser | `cmux browser open <url> --json` |
| Get element refs | `cmux browser surface:N snapshot --interactive` |
| Click element | `cmux browser surface:N click e3` |
| Fill input | `cmux browser surface:N fill e5 "text"` |
| Select dropdown | `cmux browser surface:N select e7 "value"` |
| Wait for selector | `cmux browser surface:N wait --selector X` |
| Wait for text | `cmux browser surface:N wait --text "Done"` |
| Get page data | `cmux browser surface:N get url\|title\|text\|html` |
| Run JavaScript | `cmux browser surface:N eval 'code'` |
| Find element | `cmux browser surface:N find role\|text\|label X` |
| Save auth state | `cmux browser surface:N state save <path>` |
| In-app notify | `cmux notify --title T --body B` |
| System notify | `osascript -e 'display notification "B" with title "T"'` |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using UUIDs everywhere | Use short refs: `workspace:2`, `surface:7` |
| CSS selectors in browser | Use element refs from snapshot: `e3`, `e5` |
| Forgetting `--interactive` | Always use `--interactive` for element refs |
| Not waiting after click | Use `wait --load-state complete` after navigation |
| Using cmux notify for system alerts | Use `osascript` when user is outside cmux |
| Not re-snapshotting after nav | DOM changes invalidate refs - re-snapshot |
| Using low-level input commands | Use high-level: `click`, `fill`, `type` instead of `input_*` |
