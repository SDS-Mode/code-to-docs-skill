# Changelog

All notable changes to the code-to-docs skill are documented in this file.

## 2026-07-26

Reference-passing refactor. `:update` was expensive for a structural reason: the orchestrator acted as a data bus, and every payload it pasted into an agent prompt was Opus *output* tokens retyping bytes that already existed on disk. Two gaps in the state file made that unavoidable — module root paths were never persisted (so every update silently re-surveyed the codebase to re-derive them), and the per-module analysis reports were never persisted (so "carry forward the existing reports" degenerated into reading every unchanged module's full prose doc into Opus context and re-serializing it into synthesis).

### Added
- **Analysis artifacts in `_state/`** — `modules/<slug>.md` holds each module's seven-section report (Pass 1 writes §1-6, Pass 2 appends §7); `synthesis.md` holds cross-module facts in six fixed sections, including `## Module Purposes` (one line per module, the wikilink context). Their headings are fixed so downstream agents grep one section instead of reading the whole file.
- **The reference-passing rule** — agent prompts carry paths and small structured data, never the text of a file on disk; inline context is capped at roughly 500 tokens. Codified in `output-structure.md`, in the Phase 1 and Phase 2 dispatch tables' Input columns, as Token Efficiency Rules 9–11, and as Red Flags plus Rationalization Traps in the generate and update skills.
- **`module_index` in the state file** — per module: slug, **root path**, entry points, language, complexity, LOC, report path, doc path, and per-module `analyzed_at`/`source_commit`. This makes update's change-to-module mapping an O(1) lookup and makes carry-forward auditable. It is authoritative for module boundaries: re-deriving roots can redraw a boundary, rename a module, and silently invalidate every wikilink pointing at the old name.
- **`schema_version` and a v1 → v2 migration** — an older vault migrates in place with a Haiku-only backfill (Pass 1 for §1-6; §7 recovered from the `issues` array the v1 state already persists) instead of being forced through a full regenerate.
- **`tests/pressure-test-update.md`** — scenarios for a v2 incremental run and a v1 migration run, asserting no re-survey and no unchanged-report reads.

### Changed
- **Pass 1 agents write their report and return a ~150-token receipt** (report path, root, entry points, complexity, LOC, file list, deps, `escalate` flag) instead of returning a ~3K-token report. Previously each report crossed the orchestrator's context twice — once returned, once retyped into the Pass 2 prompt — for three copies, two at the most expensive tier.
- **Pass 2 agents receive a report *path*** and read it themselves; `analysis-guide.md` no longer contains a `[PASTE THE FULL HAIKU EXTRACTION REPORT HERE]` placeholder. They append §7 to the same file and return structured issue records, so the `issues` array is now a concatenation of receipts rather than re-parsed prose.
- **Pass 2 model tier comes from the Pass 1 receipt's `escalate` flag.** The escalation conditions are unchanged (High complexity / >1000 LOC / concurrency-or-security), but they are now evaluated by the agent that actually read the code rather than by the orchestrator inspecting the report's prose.
- **Synthesis works from receipts**, reading a report only where the cross-module narrative depends on that module's internals, and writes `synthesis.md`. Phase 2 narrative agents read named sections of that file instead of being handed "the full synthesis".
- **`files_analyzed` is now path → owning module slug.** It was documented as path → sha256 for change detection, but nothing read the hashes — `git diff` is and was the sole change signal — and the value had drifted to the literal placeholder `"analyzed"` for all 52 entries in the committed example vault. Its declared type (`object (string → string)`) is unchanged, so state-file validation is unaffected.
- **Digest builds non-scoped module overviews from `synthesis.md` § Module Purposes** — one file read in place of N partial document reads — falling back to the previous per-doc extraction on v1 vaults. Digest remains strictly read-only and never migrates a vault.
- **The Pass 1 receipt no longer carries the module's file list.** It moved to a `files:` block in the report frontmatter, and the state-file writer reads it from there at Haiku. Every other receipt field is O(1) in module size; a file list is O(module size), and receipts from every module land in the orchestrator at once — on a large repo that was tens of thousands of tokens of file paths at Opus, which is exactly the cost this design exists to remove. The receipt keeps `file_count` as a cross-check.
- **Per-module one-line purposes live in `module_index`, not in `synthesis.md`.** `synthesis.md` is five sections now, not six. Having them in both places meant an update had to read the previous synthesis back in order to preserve the purposes of modules it hadn't touched — which contradicted the rule that an update loads only the state file. Digest also gets its whole non-scoped module inventory from `module_index` at **no extra read**, rather than the one `synthesis.md` read previously claimed.
- **The concurrency guard now covers the whole run, not just the state write.** Reports are written in Step 5 but state in Step 8, so a guard that only fired at Step 8 could leave a losing run's reports beside the winning run's state. The claim is now recorded at Step 1 and re-checked before any report is written. A torn run is also self-healing: a report whose `source-commit` disagrees with state marks that module affected, so it gets re-analyzed instead of carried forward.
- **Cross-module regeneration is gated on structural signals** (`graph_changed`, `issues_changed`, `purposes_changed`) rather than running unconditionally. These outputs are projections of the dependency graph, the module purposes, and the issue set; if none moved, regenerating produced near-identical prose at Sonnet cost and churned the vault diff. The common update — a bug fix touching no imports — now correctly skips System Overview, Dependency Map, and System Map. Skips must be reported with the unchanged signal named, since a silent skip is indistinguishable from a bug.
- **Update verification is scoped to files written this run**, plus (only when something was deleted or renamed) files carrying links to the removed titles. Those are the only two sets that can newly break. Baseline generate still sweeps the whole vault.
- **Deleted-module cleanup is now specified**: remove the module's doc and report, its `modules`/`module_index`/`files_analyzed` entries, and any `dependency_graph` edges pointing at it; mark its issues `resolved` (deletion is the one case where the evidence rule is met by removal rather than a diff); and sweep for inbound wikilinks to the removed title. Previously an orphan report would be carried forward forever as a module that no longer existed.
- **`roots` is a list, not a single path.** A module can span directories (release tooling covering `scripts/` and `.claude-plugin/`), and several logical modules can share one — `examples/dockhand` has Docker Engine, Database, Auth and Security, and Stacks and Git all inside `src/lib/server/`, which is the "flat structure" case `analysis-guide.md` Step 2 already supported. Because a shared root cannot attribute a file by path alone, resolution is a documented four-case order: exact `files_analyzed` hit, unique root prefix, ambiguous shared root (re-analyze every module sharing it, prefer full mode), then outside all modules.

### Not changed
- **`examples/dockhand/` is deliberately left at the v1 schema**, so it exercises the migration path rather than shipping reconstructed internals. Its `_state/modules/` reports were not back-derived from its module docs: none of those docs contains an API Reference section, so writing the spec'd `### Public API` ("every exported symbol as a code-fenced signature") would have meant inventing signatures that cannot be checked against source — the dockhand codebase is not part of this repository. The authoritative reference for the v2 artifact shape is `output-structure.md` § Analysis Artifacts. (`docs-vault/` is gitignored and local-only, so it is not a committed vault at all.)

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
