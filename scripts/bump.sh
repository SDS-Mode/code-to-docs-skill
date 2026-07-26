#!/usr/bin/env bash
set -euo pipefail

# bump.sh — Bump version, create GitHub release, update plugin manifest and local install.
#
# Usage:
#   ./scripts/bump.sh patch    # 0.1.0 → 0.1.1
#   ./scripts/bump.sh minor    # 0.1.0 → 0.2.0
#   ./scripts/bump.sh major    # 0.1.0 → 1.0.0
#   ./scripts/bump.sh 0.3.0    # explicit version
#
# The script mutates three systems in sequence — the working tree, $HOME, and GitHub — so the
# ordering rule is: everything checkable happens before the first mutation, and the one window
# that can leave a *public* half-state (tag pushed, release missing) is covered by a trap.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
SKILLS_ROOT="$REPO_ROOT/skills"

# `${VAR:?}` fires only when VAR is unset or empty. Under `set -u` an unset HOME already aborts
# before that guard is reached, while a HOME that is *set but empty* — routine in cron, containers
# and `env -i` — yields "/.claude/skills", which is non-empty and passes, aiming the rm -rf in the
# mirror step at a root-level path. Assert the property being relied on instead.
if [[ -z "${HOME:-}" || "$HOME" == "/" ]]; then
    echo "Error: HOME is unset or '/'; refusing to mirror skills." >&2
    exit 1
fi
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
# Assert the slug's shape, not merely that it contains a slash: the sed above strips exactly two
# remote-URL forms, so ssh://, GitHub Enterprise and non-GitHub remotes all yield something with a
# slash in it that would only be caught by `gh release create` — after the tag is public.
if [[ ! "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    echo "Error: origin remote ('$ORIGIN_URL') did not yield an owner/repo slug." >&2
    exit 1
fi
# The mirror step copies the working tree, so require a clean tree to avoid releasing a tag that
# doesn't match what gets mirrored/pushed.
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    echo "Error: working tree is not clean. Commit or stash changes before releasing." >&2
    exit 1
fi

# Release from the default branch only. This invariant is documented, but nothing enforced it: the
# `git push` below is bare and mid-flight, so on a feature branch with an upstream it succeeds, and
# the script then tags an unmerged commit and publishes a release from it.
DEFAULT_BRANCH="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
if [[ -z "$DEFAULT_BRANCH" ]]; then
    DEFAULT_BRANCH="$(gh repo view "$REPO" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)"
fi
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
CURRENT_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]]; then
    echo "Error: on branch '$CURRENT_BRANCH'. Release from '$DEFAULT_BRANCH' after the PR merges," >&2
    echo "       otherwise the tag points at a commit that is not on the default branch." >&2
    exit 1
fi
# A stale checkout would otherwise fail the push mid-flight — after $HOME has been rewritten.
# Fetch tags too: the tag-collision check and the changelog baseline below are both wrong if the
# local tag set is behind origin's.
git -C "$REPO_ROOT" fetch --quiet --tags origin "$DEFAULT_BRANCH"
if [[ -n "$(git -C "$REPO_ROOT" rev-list "HEAD..origin/$DEFAULT_BRANCH")" ]]; then
    echo "Error: local $DEFAULT_BRANCH is behind origin/$DEFAULT_BRANCH. Pull first." >&2
    exit 1
fi

# Resolve the skill directories once, up front: without nullglob an empty skills/ leaves the
# pattern unexpanded, and the mirror loop then runs once with dir='*', creating a junk directory
# literally named '*' in the user's skills dir before aborting on the nonexistent source.
shopt -s nullglob
skill_dirs=("$SKILLS_ROOT"/*/)
shopt -u nullglob
if [[ ${#skill_dirs[@]} -eq 0 ]]; then
    echo "Error: no skill directories found under $SKILLS_ROOT." >&2
    exit 1
fi
skill_names=()
for src in "${skill_dirs[@]}"; do skill_names+=("$(basename "$src")"); done

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
        # `[0-9]*` is a glob meaning "starts with a digit", not "is a version" — without this check
        # `1`, `1.2.3.4` and `9junk` are all accepted verbatim into the manifest and the tag.
        if [[ ! "$BUMP_TYPE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "Error: '$BUMP_TYPE' is not a valid X.Y.Z version." >&2
            exit 1
        fi
        NEW_VERSION="$BUMP_TYPE"
        ;;
    *)
        echo "Error: Invalid bump type '$BUMP_TYPE'. Use patch, minor, major, or X.Y.Z"
        exit 1
        ;;
esac

echo "New version: $NEW_VERSION"

# The target tag must not already exist, locally or on origin. Without this the collision surfaces
# at `git tag`, i.e. after the manifest and $HOME have already been rewritten.
if git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/v$NEW_VERSION" >/dev/null; then
    echo "Error: tag v$NEW_VERSION already exists locally." >&2
    exit 1
fi
if [[ -n "$(git -C "$REPO_ROOT" ls-remote --tags origin "refs/tags/v$NEW_VERSION")" ]]; then
    echo "Error: tag v$NEW_VERSION already exists on origin." >&2
    exit 1
fi

# --- Release notes, computed BEFORE anything is public ---
#
# Deliberately ahead of the tagging block: a bug in this section used to abort the run *after* the
# tag had been pushed. It also means the newest existing tag is by definition the previous release
# (the new one does not exist yet), so no filtering is needed — the old `grep -v "v$NEW_VERSION"`
# exited 1 whenever that tag was the only one, which `pipefail` turned into a silent abort.

PREV_TAG=$(git -C "$REPO_ROOT" tag --sort=-v:refname | head -1)
SINCE_LABEL="${PREV_TAG:-the initial commit}"

if [[ -n "$PREV_TAG" ]]; then
    CHANGELOG=$(git log "$PREV_TAG"..HEAD --pretty=format:"- %s" --no-merges)
    # A manifest ahead of the newest tag means versions were bumped but never released — either a
    # run that aborted after committing the bump (the tree is clean again, so no other check can
    # see it) or a manual edit. Worth saying out loud, because the changelog then spans more than
    # one release and the bump skips the untagged versions.
    if [[ "$PREV_TAG" != "v$CURRENT_VERSION" ]]; then
        echo "Warning: the manifest is at $CURRENT_VERSION but the newest tag is $PREV_TAG — the versions"
        echo "         between them were never released, and these notes will span $PREV_TAG..HEAD."
    fi
else
    CHANGELOG=$(git log --pretty=format:"- %s" --no-merges | head -20)
fi

if [[ -z "$CHANGELOG" ]]; then
    CHANGELOG="- Version bump (no code changes since last tag)"
fi

# --- Confirm ---

echo ""
echo "This will:"
echo "  - bump $MARKETPLACE_JSON to $NEW_VERSION and commit it"
echo "  - REPLACE these directories under $LOCAL_SKILLS_ROOT/: ${skill_names[*]}"
echo "  - push branch '$CURRENT_BRANCH' and public tag v$NEW_VERSION to $REPO"
echo "  - publish a public GitHub release for v$NEW_VERSION"
read -rp "Proceed? [y/N] " confirm
if [[ ! "$confirm" =~ ^([yY]|[yY][eE][sS])$ ]]; then
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
for src in "${skill_dirs[@]}"; do
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

# --- Create GitHub release ---
#
# From here until the release exists, a failure leaves an orphaned PUBLIC tag: recovery is entirely
# manual, and the orphan is self-blocking, because a naive re-run then dies at `git tag`. Arm
# cleanup for exactly that window and disarm it once the release is up.

cleanup_tag() {
    trap - ERR INT TERM
    echo "" >&2
    echo "Error: the GitHub release was not created — removing tag v$NEW_VERSION so a re-run can succeed." >&2
    git tag -d "v$NEW_VERSION" >/dev/null 2>&1 || true
    git push origin ":refs/tags/v$NEW_VERSION" >/dev/null 2>&1 || true
    echo "Note: $MARKETPLACE_JSON is still at $NEW_VERSION and that bump is committed and pushed." >&2
    echo "      Re-run with an explicit version ($0 $NEW_VERSION) rather than a bump type." >&2
    exit 1
}
trap cleanup_tag ERR INT TERM

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

trap - ERR INT TERM

echo ""
echo "Done! Released v$NEW_VERSION"
echo "  GitHub: https://github.com/$REPO/releases/tag/v$NEW_VERSION"
echo "  Plugin: $MARKETPLACE_JSON → v$NEW_VERSION"
echo "  Local:  $LOCAL_SKILLS_ROOT/ → updated"
