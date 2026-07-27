# Changelog

All notable changes to the code-to-docs skill are documented in this file.

## 2026-07-26

Release-tooling fixes found by running the documentation pipeline over this repository's own source, then reproduced against a scratch repo with a local origin and a stubbed `gh`.

### Fixed

- **`bump.sh` aborted after the tag was public.** `PREV_TAG=$(git tag --sort=-v:refname | grep -v "v$NEW_VERSION" | head -1)` runs *after* the tag is pushed. When the new tag is the repo's only tag, `grep -v` matches nothing and exits 1, `pipefail` promotes that to the pipeline's status and `set -e` ends the run — leaving a public tag with no GitHub release and no error explaining why. The first-release `else` branch below it was therefore unreachable dead code. Release notes are now computed *before* anything is published, which also removes the need to filter the new tag at all: the newest existing tag is by definition the previous release.
- **Nothing prevented releasing from a feature branch.** The documented invariant is "release from `main` after the PR merges," on the reasoning that the branch push would fail preflight. It does not — the push is bare and mid-flight, and on a feature branch with an upstream it succeeds, after which the script tags an unmerged commit and publishes a release from it. Preflight now requires the default branch and a checkout that is not behind origin.
- **No rollback between pushing the tag and creating the release.** Any failure in that window — a `gh` rate limit, an expired token, insufficient permission, a network drop — left an orphaned public tag that also blocks a naive re-run at `git tag`. That window is now covered by a trap that deletes the tag locally and on origin, and reports the state that remains.
- **`rm -rf` under a guard that cannot fire.** `${LOCAL_SKILLS_ROOT:?}` fires only when the variable is unset or empty; under `set -u` an unset `HOME` already aborts earlier, while a `HOME` that is *set but empty* — routine in cron, containers and `env -i` — yields `/.claude/skills`, which is non-empty and passes the guard. The property is now asserted directly.
- **An empty `skills/` created a directory literally named `*`.** Without `nullglob` the unmatched pattern is passed through, so the mirror loop ran once with `dir='*'`, created that directory in the user's skills dir, then aborted on the nonexistent source — with the manifest already bumped.
- **Weak input validation.** The repo slug was only checked for containing a slash, so `ssh://`, GitHub Enterprise and non-GitHub remotes passed and failed later at `gh release create`; `[0-9]*` accepted `1`, `1.2.3.4` and `9junk` as versions; and a tag collision surfaced only at `git tag`, after the manifest and `$HOME` had been rewritten. All three are now preflight checks with shape assertions.

### Changed

- The confirmation prompt names what it authorizes — which directories under `~/.claude/skills/` will be replaced, and that both the tag and the release are public — and accepts `yes` as well as `y`. It was previously a bare "Proceed?" that rejected `yes`.
- A manifest version ahead of the newest tag is now reported: it means versions were bumped but never released, so the notes span more than one release.

## 2026-07-22

### Changed
- **Marketplace listing** — expanded the `marketplace.json` plugin description to reflect the whole project: added the codebase health assessment and the incremental-update / read-only-digest lifecycle, so it no longer reads as a one-shot generator.

## 2026-07-21

Fixes from a self-analysis pass (running the skill on its own source surfaced 30 issues).

### Fixed
- **Release tooling** — `bump.sh` now derives the GitHub repo from the `origin` remote (it was hardcoded to the wrong owner, so a release could target the wrong repository), pushes the branch with a checked exit status *before* tagging (a failed push was silently swallowed), and runs preflight checks (`gh` auth, clean working tree) before mutating anything.
- **Owner references** — corrected the plugin owner and install instructions from `RCellar` to `SDS-Mode` (`marketplace.json`, `README`).
- **Skill invocation names** — the documented forms (`code-to-docs:update`, `:digest`, `:hooks`) did not resolve; plugin skills resolve by directory name. Frontmatter `name:` fields now match their directories and every invocation example uses the working `code-to-docs:code-to-docs-*` form.
- **Update skill** — falls back to full generation when the stored commit is null or unreachable; marks an issue `resolved` only when the diff actually touched its file/lines (it was falsely resolving issues a non-deterministic re-analysis merely omitted); decides quick/full mode from a content diff gathered *before* the decision (the import-detection trigger was previously unimplementable); added an optimistic-concurrency guard before rewriting state.
- **Generate skill** — `Health/Health Summary.md` is generated at the Haiku tier per the authoritative dispatch table (the prose had mis-assigned it to Sonnet); completed the Opus-escalation restatement.
- **Reference library** — the state-file schema shown to the state-writer now includes the required `issues`/`sessions`/`project` fields (omitting them broke update/digest validation); the "Modules by Language" Dataview query uses `rows.*` so its columns render; added a docs-as-source survey fallback for repos with no conventional application code; removed a reference to a non-existent "separate documentation phase"; noted `xychart-beta` compatibility.
- **Hooks** — `digest-on-start.sh` no longer crashes on a null `git_commit` and honors a custom `CODE_TO_DOCS_VAULT` in its staleness check; `setup.sh` builds `settings.json` with JSON- and shell-safe escaping and updates (rather than silently no-ops) on re-run with a new vault path; `update-hint-on-commit.sh` detects an actual `git commit` invocation and skips failed commits.
- **Digest skill** — validates the state-file schema (not just existence), degrades gracefully when optional vault files are missing, loads a light per-module overview instead of the full Beginner section, and treats token budgets as soft targets with concrete proxies.
- **`.gitignore`** — no longer lists the tracked, required `scripts/`, `tests/`, and `.claude-plugin/` under "not distributed".

### Changed
- De-duplicated the incremental update flow: `analysis-guide.md` is authoritative and `code-to-docs-update/SKILL.md` is now a checklist that points to it.
- Removed the `digest` session type from the state schema — the digest skill is strictly read-only and never writes session entries.

## 2026-04-10

### Added
- Marketplace discovery via `marketplace.json` for plugin system integration
- Separate skills for each lifecycle phase: `code-to-docs:digest`, `code-to-docs:update`, `code-to-docs:hooks`
- Colon-style skill invocations (`code-to-docs:update` instead of flags)

### Changed
- Split monolith SKILL.md into independent skill files per command
- Moved shared reference files (`analysis-guide`, `obsidian-templates`, `output-structure`) to `skills/references/`
- Updated hook scripts and reference files for colon-style invocations

### Fixed
- Hook scripts and reference paths updated for new skill layout

### Housekeeping
- Removed `CLAUDE.md` from git tracking (kept in `.gitignore`)
- Added `.firecrawl/`, `.superpowers/`, `tests/` to `.gitignore`

## 2026-03-30

### Added
- Dispatch tables for model tier cost discipline — explicit Haiku/Sonnet/Opus assignment per agent
- ApexCharts-rendered SVG diagrams in README

### Fixed
- `Documentation.base` template — use YAML with `and`/`or`/`not` filters
- PostToolUse update-hint hook never firing

## 2026-03-29

### Added
- Codebase health assessment output (Limitations, Code Review, Health Summary)
- Three-tier model strategy (Haiku for extraction, Sonnet for writing, Opus for reasoning)
- Development lifecycle: `digest` and `update` modes
- Optional project-level hook automation (SessionStart, PostToolUse)
- Obsidian Bases catalog (`.base` files) and opportunistic CLI integration
- Dockhand example vault demonstrating full mode output

### Fixed
- Hook default vault path to `./docs-vault`
- Path argument defaults to cwd instead of being required
- 6 code health issues identified by self-analysis

## 2026-03-28

### Added
- Initial release: code-to-docs Claude Code skill
- Two-pass analysis pipeline (extract then reason)
- Quick and full generation modes
- Obsidian-native output (wikilinks, Mermaid, frontmatter)
- Parallel agent dispatch for multi-module codebases
