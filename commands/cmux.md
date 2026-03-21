# cmux Terminal Control

Use this command to control cmux terminal features for You MUST invoke the using-cmux skill first.

$instructions: Use the using-cmux skill to get comprehensive cmux guidance before responding. Common patterns:

## Quick Actions

After reading the skill, respond with what the user needs.

## Common Tasks

| User says | Use |
|----------|-----|
| "Split pane" / "Create split" | `cmux new-split right\|down` |
| "Open browser" | `cmux browser open <url> --json` |
| "Click element" | `cmux browser surface:N snapshot --interactive` then `click eN` |
| "Notify me" | `cmux notify --title T --body B` |
| "Where am I" | `cmux identify --json` |
