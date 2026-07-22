#!/usr/bin/env bash
# code-to-docs: PostToolUse hook — reminds Claude to suggest an update after a git commit.
# Stdout from this script is added to Claude's context.
# Fires on all Bash tool calls; only reminds when the command actually INVOKED `git commit`
# (not merely mentioned it in an echo/string) and the tool did not report an error.

set -euo pipefail

VAULT_PATH="${CODE_TO_DOCS_VAULT:-./docs-vault}"
STATE_FILE="$VAULT_PATH/_state/analysis.json"

# Only produce output if a vault exists
if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
fi

# Decide from the PostToolUse payload (JSON on stdin) whether a real git commit ran.
COMMITTED=$(python3 -c "
import json, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print('no'); raise SystemExit
cmd = data.get('tool_input', {}).get('command', '') or ''
resp = data.get('tool_response', {})
# Match 'git commit' as an actual command invocation (start of line or after ; & | &&),
# not a mention inside an echo/string/comment.
invoked = bool(re.search(r'(?:^|[\n;&|])\s*git\s+commit\b', cmd))
# Skip the reminder if the tool reported a failure/interruption, when that's discernible.
failed = isinstance(resp, dict) and bool(resp.get('is_error') or resp.get('interrupted'))
print('yes' if invoked and not failed else 'no')
" 2>/dev/null <<< "$(cat)" || echo "no")

if [[ "$COMMITTED" != "yes" ]]; then
    exit 0
fi

echo "[code-to-docs] Code was just committed. When the coding session is complete, consider running /code-to-docs:code-to-docs-update to sync documentation with the latest changes."
