#!/usr/bin/env bash
# code-to-docs: Hook setup script
# Installs SessionStart and PostToolUse hooks into the project's .claude/settings.json
#
# Usage:
#   ./setup.sh [vault-path]
#
# vault-path defaults to $CODE_TO_DOCS_VAULT, then ./docs-vault (the code-to-docs --output default).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT_PATH="${1:-${CODE_TO_DOCS_VAULT:-./docs-vault}}"
PROJECT_SETTINGS=".claude/settings.json"

# Resolve absolute paths to the hook scripts
DIGEST_HOOK="$SCRIPT_DIR/digest-on-start.sh"
UPDATE_HOOK="$SCRIPT_DIR/update-hint-on-commit.sh"

for hook in "$DIGEST_HOOK" "$UPDATE_HOOK"; do
    if [[ ! -f "$hook" ]]; then
        echo "Error: Cannot find $hook" >&2
        echo "Run this script from the code-to-docs hooks directory or ensure the skill is installed." >&2
        exit 1
    fi
done

# Ensure hooks are executable
chmod +x "$DIGEST_HOOK" "$UPDATE_HOOK"

# Ensure .claude directory exists
mkdir -p .claude

# Build the hook entries and merge into settings.json with python3. All dynamic values are passed
# as argv so json.dumps handles JSON escaping and shlex.quote handles shell escaping — nothing is
# interpolated raw into JSON or into the embedded shell command, so paths with quotes/spaces are safe.
# Re-running with a different vault path REPLACES the existing code-to-docs entries (not a no-op).
python3 - "$PROJECT_SETTINGS" "$VAULT_PATH" "$DIGEST_HOOK" "$UPDATE_HOOK" <<'PY'
import json, os, shlex, sys

settings_path, vault_path, digest_hook, update_hook = sys.argv[1:5]

def command(hook):
    # CODE_TO_DOCS_VAULT=<vault> bash <hook>, each value shell-escaped.
    return f"CODE_TO_DOCS_VAULT={shlex.quote(vault_path)} bash {shlex.quote(hook)}"

new_handlers = {
    "SessionStart": {
        "matcher": "startup",
        "hooks": [{"type": "command", "command": command(digest_hook),
                   "source": "code-to-docs", "timeout": 10}],
    },
    "PostToolUse": {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": command(update_hook),
                   "source": "code-to-docs", "timeout": 5}],
    },
}

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault("hooks", {})
replaced = False
for event, handler in new_handlers.items():
    existing = hooks.setdefault(event, [])
    # Drop any prior code-to-docs hook for this event, then append the fresh one, so a re-run with
    # a new vault path updates the command instead of silently doing nothing.
    #
    # Filter WITHIN each handler group, not at the group level: a group is dropped only once we
    # have emptied it. Discarding a whole group because one hook in it was ours would delete hooks
    # the user added alongside it — and setup.sh's own closing message tells them to hand-edit
    # this file.
    dropped = 0
    for h in existing:
        entries = h.get("hooks", [])
        kept = [k for k in entries if k.get("source") != "code-to-docs"]
        dropped += len(entries) - len(kept)
        h["hooks"] = kept
    existing[:] = [h for h in existing if h.get("hooks")]
    if dropped:
        replaced = True
    existing.append(handler)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print(("Updated" if replaced else "Installed") + f" code-to-docs hooks in {settings_path}")
PY

echo ""
echo "Hooks installed:"
echo "  SessionStart → digest vault summary on session start"
echo "  PostToolUse  → update hint after git commits"
echo ""
echo "Vault path: $VAULT_PATH"
echo ""
echo "To remove hooks: run teardown.sh from this directory"
echo "To customize: edit $PROJECT_SETTINGS directly"
