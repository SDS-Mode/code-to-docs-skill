#!/usr/bin/env bash
set -euo pipefail

# bump.sh — Bump version, create GitHub release, update plugin manifest and local install.
#
# Usage:
#   ./scripts/bump.sh patch    # 0.1.0 → 0.1.1
#   ./scripts/bump.sh minor    # 0.1.0 → 0.2.0
#   ./scripts/bump.sh major    # 0.1.0 → 1.0.0
#   ./scripts/bump.sh 0.3.0    # explicit version

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
SKILLS_ROOT="$REPO_ROOT/skills"
LOCAL_SKILLS_ROOT="$HOME/.claude/skills"

# Derive the GitHub repo (owner/name) from the origin remote so the release can never target a
# different repo than the one we tag and push to. Handles both https and ssh remote URLs.
ORIGIN_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
REPO="$(printf '%s' "$ORIGIN_URL" | sed -E 's#^git@github\.com:##; s#^https://github\.com/##; s#\.git$##')"

# --- Parse arguments ---

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <patch|minor|major|X.Y.Z>"
    exit 1
fi

BUMP_TYPE="$1"

# --- Preflight checks (fail before mutating anything) ---

command -v git >/dev/null || { echo "Error: git not found." >&2; exit 1; }
command -v gh  >/dev/null || { echo "Error: gh (GitHub CLI) not found — needed to create the release." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Error: gh is not authenticated. Run 'gh auth login' first." >&2; exit 1; }
if [[ -z "$REPO" || "$REPO" != */* ]]; then
    echo "Error: could not determine the GitHub repo from origin remote ('$ORIGIN_URL')." >&2
    exit 1
fi
# The mirror step copies the working tree, so require a clean tree to avoid releasing a tag that
# doesn't match what gets mirrored/pushed.
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    echo "Error: working tree is not clean. Commit or stash changes before releasing." >&2
    exit 1
fi
echo "Releasing to: $REPO"

# --- Read current version ---

CURRENT_VERSION=$(grep -o '"version": *"[^"]*"' "$MARKETPLACE_JSON" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

echo "Current version: $CURRENT_VERSION"

# --- Compute new version ---

case "$BUMP_TYPE" in
    patch)
        NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
        ;;
    minor)
        NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
        ;;
    major)
        NEW_VERSION="$((MAJOR + 1)).0.0"
        ;;
    [0-9]*)
        NEW_VERSION="$BUMP_TYPE"
        ;;
    *)
        echo "Error: Invalid bump type '$BUMP_TYPE'. Use patch, minor, major, or X.Y.Z"
        exit 1
        ;;
esac

echo "New version: $NEW_VERSION"

# --- Confirm ---

read -rp "Proceed? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    exit 0
fi

# --- Update marketplace.json ---

# sed -i.bak is portable across GNU (Linux) and BSD (macOS) sed; remove the backup after.
sed -i.bak "s/\"version\": *\"$CURRENT_VERSION\"/\"version\": \"$NEW_VERSION\"/" "$MARKETPLACE_JSON"
rm -f "$MARKETPLACE_JSON.bak"
echo "Updated $MARKETPLACE_JSON"

# --- Update local skill install ---

# Maintainer dev-convenience only: mirror skills into the PERSONAL skills dir so local
# invocations pick up edits. This is separate from the marketplace plugin install — on a machine
# that also installed the plugin, these are two distinct skill sources. Full replace per dir so
# files removed or renamed upstream don't linger in the mirror.
for src in "$SKILLS_ROOT"/*/; do
    dir=$(basename "$src")
    rm -rf "${LOCAL_SKILLS_ROOT:?}/$dir"
    mkdir -p "$LOCAL_SKILLS_ROOT/$dir"
    cp -R "$src." "$LOCAL_SKILLS_ROOT/$dir/"
done
echo "Updated local skills at $LOCAL_SKILLS_ROOT/ (mirrored from $SKILLS_ROOT)"

# --- Commit if there are tracked changes, tag, push ---

cd "$REPO_ROOT"

git add "$MARKETPLACE_JSON"
if [[ -n "$(git diff --cached --name-only)" ]]; then
    git commit -m "chore: bump version to v$NEW_VERSION"
    echo "Committed version bump"
else
    echo "No tracked changes to commit (marketplace.json may be gitignored — this is expected)"
fi

# Push the branch first and check it; only then create and push the tag, so the tag can never
# point at a commit that failed to reach origin.
if ! git push; then
    echo "Error: branch push failed — aborting before tagging v$NEW_VERSION." >&2
    exit 1
fi
git tag "v$NEW_VERSION"
git push origin "v$NEW_VERSION"

echo "Pushed tag v$NEW_VERSION"

# --- Generate release notes from commits since last tag ---

PREV_TAG=$(git tag --sort=-v:refname | grep -v "v$NEW_VERSION" | head -1)
SINCE_LABEL="${PREV_TAG:-the initial commit}"

if [[ -n "$PREV_TAG" ]]; then
    CHANGELOG=$(git log "$PREV_TAG"..HEAD --pretty=format:"- %s" --no-merges)
else
    CHANGELOG=$(git log --pretty=format:"- %s" --no-merges | head -20)
fi

if [[ -z "$CHANGELOG" ]]; then
    CHANGELOG="- Version bump (no code changes since last tag)"
fi

# --- Create GitHub release ---

gh release create "v$NEW_VERSION" \
    --repo "$REPO" \
    --title "v$NEW_VERSION" \
    --notes "$(cat <<EOF
## code-to-docs v$NEW_VERSION

### Changes since $SINCE_LABEL

$CHANGELOG

### Installation

\`\`\`
/plugin marketplace add $REPO
/plugin install code-to-docs@code-to-docs-skill
\`\`\`
EOF
)"

echo ""
echo "Done! Released v$NEW_VERSION"
echo "  GitHub: https://github.com/$REPO/releases/tag/v$NEW_VERSION"
echo "  Plugin: $MARKETPLACE_JSON → v$NEW_VERSION"
echo "  Local:  $LOCAL_SKILLS_ROOT/ → updated"
