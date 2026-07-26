# Changelog

All notable changes to the code-to-docs skill are documented in this file.

## 2026-07-26

Hook-script fixes found by running the documentation pipeline over this repository's own source. All three were reproduced against scratch fixtures rather than inferred from reading.

### Fixed

- **Code injection in the SessionStart hook** — `digest-on-start.sh` spliced the vault path into a `python3 -c` string literal, so a quote in the path terminated the literal and the remainder was evaluated as Python. Demonstrated end to end: a vault directory named as a payload both executed a side effect and redirected `open()` to a different file than the one the existence guard had checked. The path is now passed as `argv`, matching the discipline `setup.sh` already used.
- **A hook that misinformed the model it exists to inform** — the same extractor ended in `2>/dev/null || echo "unknown ... 0"`, so *every* failure (a quote in the path, corrupt JSON, schema drift, a missing `python3`) collapsed into a banner of `unknown` values asserting **`Open issues: 0`**. Since that text is injected straight into Claude's context, a vault with open issues was reported as having none. Failures now say so on stdout and print the diagnostic on stderr, and the count is never printed unless it was computed.
- **Setup and teardown deleted co-located user hooks** — both filtered `.claude/settings.json` at the handler-group level, discarding an entire group when any hook inside it carried `source: "code-to-docs"`. A hook the user had added alongside ours vanished on the next `setup.sh` or `teardown.sh` run, with no backup, contradicting the skill's "other hooks are left untouched" promise while `setup.sh` invited the user to hand-edit the file. Both now filter individual hook objects and drop a group only once it is empty.
- **Teardown deleted a settings file it never modified** — the empty-file check ran unconditionally, so a pre-existing `.claude/settings.json` containing only `{}` was unlinked while teardown reported removing zero hooks. Deletion is now conditional on having actually removed something, and the counter counts hooks rather than handler groups.
- **The staleness banner always looked stale** — the stored commit was truncated to 8 characters while the live one came from `git rev-parse --short` (7 in a small repo), so the two never rendered identically even when the vault was current. Both are now 8.
- **`teardown.sh` built its Python program by shell interpolation** — not exploitable, since the settings path is a constant, but the same construction as the injection above and the opposite convention from `setup.sh`. Converted to `argv`; also dropped the trailing `2>&1` that merged tracebacks into normal output.

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
