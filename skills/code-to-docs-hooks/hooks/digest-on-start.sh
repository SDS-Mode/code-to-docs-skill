#!/usr/bin/env bash
# code-to-docs: SessionStart hook — injects vault context into Claude's conversation.
# Stdout from this script is automatically added to Claude's context.
# This script is READ-ONLY — it never modifies the vault.

set -euo pipefail

VAULT_PATH="${CODE_TO_DOCS_VAULT:-./docs-vault}"

STATE_FILE="$VAULT_PATH/_state/analysis.json"

if [[ ! -f "$STATE_FILE" ]]; then
    echo "[code-to-docs] No documentation vault found at $VAULT_PATH — run /code-to-docs:code-to-docs to generate one."
    exit 0
fi

# Extract key fields from the state file (single python3 invocation).
#
# The path is passed as argv, never interpolated into the program text: bash expands a spliced
# "$STATE_FILE" before python3 ever parses it, so a quote in the path is a Python syntax error at
# best and arbitrary code execution at worst. Same argv discipline as setup.sh.
#
# A failure here is reported, not swallowed. The previous blanket `2>/dev/null || echo unknown...`
# fallback asserted "Open issues: 0" for any unreadable vault — worse than saying nothing, because
# this text is injected straight into Claude's context.
if ! SUMMARY=$(python3 - "$STATE_FILE" <<'PY'
import json, sys

try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except (OSError, ValueError) as e:
    print(f'{type(e).__name__}: {e}', file=sys.stderr)
    raise SystemExit(2)

def name(m):
    if isinstance(m, dict):
        return str(m.get('name') or m.get('slug') or m)
    return str(m)

issues = [i for i in d.get('issues', []) if isinstance(i, dict)]
print('\t'.join([
    str(d.get('project', 'unknown')),
    ', '.join(name(m) for m in d.get('modules', [])),
    (d.get('git_commit') or 'unknown')[:8],
    str(d.get('timestamp', 'unknown')),
    str(d.get('mode', 'unknown')),
    str(len([i for i in issues if i.get('status') == 'open'])),
]))
PY
); then
    echo "[code-to-docs] A vault exists at $VAULT_PATH but its state file could not be read."
    echo "  $STATE_FILE is unreadable or not valid JSON (diagnostic on stderr)."
    echo "  Run /code-to-docs:code-to-docs to regenerate it."
    exit 0
fi

IFS=$'\t' read -r PROJECT MODULES COMMIT TIMESTAMP MODE ISSUE_COUNT <<< "$SUMMARY"

# Check staleness. Match the stored commit's width (8) so the same commit renders as the same
# string — `--short` yields 7 in a small repo, which made every session's banner look stale.
CURRENT_HEAD=$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")

cat <<EOF
[code-to-docs] Project documentation available for: $PROJECT
  Modules: $MODULES
  Last run: $TIMESTAMP ($MODE mode) at commit $COMMIT
  Current HEAD: $CURRENT_HEAD
  Open issues: $ISSUE_COUNT

To load full context, run: /code-to-docs:code-to-docs-digest $VAULT_PATH
To load specific modules: /code-to-docs:code-to-docs-digest $VAULT_PATH --scope {module names}
To see known issues: /code-to-docs:code-to-docs-digest $VAULT_PATH --focus issues
EOF

if [[ "$COMMIT" != "unknown" && "$CURRENT_HEAD" != "unknown" && "$COMMIT" != "$CURRENT_HEAD" ]]; then
    CHANGES=$(git diff --stat "${COMMIT}..HEAD" -- . ":!${VAULT_PATH#./}" 2>/dev/null | tail -1 || echo "")
    if [[ -n "$CHANGES" ]]; then
        echo "  Documentation may be stale — $CHANGES since last run."
        echo "  Run /code-to-docs:code-to-docs-update after your work to sync."
    fi
fi
