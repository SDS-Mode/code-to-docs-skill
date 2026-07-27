#!/usr/bin/env bash
# code-to-docs: Hook teardown script
# Removes code-to-docs hooks from the project's .claude/settings.json

set -euo pipefail

PROJECT_SETTINGS=".claude/settings.json"

if [[ ! -f "$PROJECT_SETTINGS" ]]; then
    echo "No $PROJECT_SETTINGS found — nothing to remove."
    exit 0
fi

# The settings path is passed as argv rather than interpolated into the program text, matching
# setup.sh. It is a constant today, so nothing is exploitable — but the interpolated form is the
# same construction that made digest-on-start.sh injectable, and it becomes live the moment this
# path is parameterised.
python3 - "$PROJECT_SETTINGS" <<'PY'
import json, os, sys

settings_path = sys.argv[1]

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
removed = 0

for event in list(hooks.keys()):
    # Filter WITHIN each handler group, not at the group level. Dropping a whole group because one
    # hook in it is ours would delete hooks the user added alongside it — settings.json is a file
    # SKILL.md invites the user to hand-edit, and SKILL.md promises theirs are left untouched.
    for handler in hooks[event]:
        entries = handler.get('hooks', [])
        kept = [h for h in entries if h.get('source') != 'code-to-docs']
        removed += len(entries) - len(kept)
        handler['hooks'] = kept
    # Drop only groups we emptied, and empty event arrays
    hooks[event] = [h for h in hooks[event] if h.get('hooks')]
    if not hooks[event]:
        del hooks[event]

# Remove empty hooks object
if not hooks and 'hooks' in settings:
    del settings['hooks']

# Delete the file only if we actually emptied it. A settings.json that was already `{}` before
# this ran is the user's file, not ours to unlink.
if removed and settings == {}:
    os.remove(settings_path)
    print(f'Removed {removed} code-to-docs hook(s). Deleted now-empty {settings_path}.')
elif removed:
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
    print(f'Removed {removed} code-to-docs hook(s) from {settings_path}.')
else:
    print(f'No code-to-docs hooks found in {settings_path} — nothing removed.')
PY
