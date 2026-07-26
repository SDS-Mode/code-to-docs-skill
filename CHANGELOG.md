# Changelog

All notable changes to the code-to-docs skill are documented in this file.

## 2026-07-26

Reference-passing refactor of the analysis pipeline, aimed at `:update`. It was expensive for a structural reason: the orchestrator acted as a data bus, and every payload it pasted into an agent prompt was Opus *output* tokens retyping bytes that already existed on disk — where they then existed twice, once in the orchestrator's context and once in the agent's.

Two gaps in the state file made that unavoidable rather than merely wasteful. Module root paths were never persisted, yet the update flow required them to decide which module a changed file belonged to — so every run silently re-surveyed the codebase to re-derive them, at orchestrator cost and with the risk that a redrawn boundary renames a module and orphans its doc. And the per-module analysis reports were never persisted, so "carry forward the existing reports" degenerated into reading every unchanged module's full audience-level doc into Opus context and re-serialising it into synthesis.

### Added

- **Analysis artifacts in `_state/`.** `modules/<slug>.md` holds each module's seven-section report (Pass 1 writes §1-6, Pass 2 appends §7). `synthesis.md` holds cross-module facts in five sections: Architecture Narrative, Architecture Type, System-Wide Patterns, Cross-Cutting Themes, Issue Themes. All headings are exact and fixed, so a downstream agent greps one section instead of reading the file.
- **The reference-passing rule.** Agent prompts carry paths and small structured data, never the text of a file on disk; inline context is capped at roughly 500 tokens. Codified in `output-structure.md`, in the Phase 1 and Phase 2 dispatch tables' Input columns, as Token Efficiency Rules 9–11, and as Red Flags and Rationalization Traps in the generate and update skills.
- **`module_index` in the state file** — per module: slug, purpose, root paths, entry points, language, complexity, LOC, report path, doc path, and per-module `analyzed_at`/`source_commit`. This makes change-to-module mapping a lookup instead of a survey, and makes carry-forward auditable. It is authoritative for module boundaries.
- **`architecture_type` and `system_patterns` in the state file**, so an update can tell whether the system-wide picture moved without reading the previous `synthesis.md` back.
- **`schema_version` and a v1 → v2 migration.** An older vault migrates in place with a Haiku-only backfill — Pass 1 re-extracts §1-6, and a second Haiku agent reformats §7 from the `issues` array v1 already persisted — instead of being forced through a full regenerate. Migrated §7 has no before/after snippets, since v1 stored issue records rather than prose, and the skill says so rather than letting a thin Health entry read as a clean module.
- **`tests/pressure-test-update.md`** — a v2 incremental run and a v1 migration run. Most checkpoints assert *absences* (no re-survey, no unchanged-report reads, no pasted payloads), so they are verified from the transcript rather than the output vault.

### Changed

- **Pass 1 agents write their report and return a receipt** — report path, purpose, roots, entry points, language, complexity, LOC, `file_count`, deps, and an `escalate` flag — instead of returning the report itself. Previously each report crossed the orchestrator's context twice, once returned and once retyped into the Pass 2 prompt: three copies, two at the most expensive tier. The receipt is a fixed small size regardless of module size; the module's file list lives in the report's `files:` frontmatter, because a list that grows with the codebase would reintroduce exactly the cost being removed.
- **Pass 2 agents receive a report *path*** and read it themselves; `analysis-guide.md` no longer contains a `[PASTE THE FULL HAIKU EXTRACTION REPORT HERE]` placeholder. They append §7 to the same file and return structured issue records, so the `issues` array is a concatenation of receipts rather than re-parsed prose.
- **Pass 2 model tier comes from the receipt's `escalate` flag.** The escalation conditions are unchanged (High complexity / >1000 LOC / concurrency-or-security), but they are evaluated by the agent that actually read the code rather than by the orchestrator inspecting the report's prose.
- **Synthesis works from receipts and paths**, reading a report only where the cross-module narrative depends on that module's internals. It is dispatched to an agent in both branches — Sonnet for ≤4 tree-shaped modules, Opus above — rather than run inline; the orchestrator *is* Opus, so inline meant Sonnet-level narrative writing at Opus rates.
- **`files_analyzed` is now path → owning module slug**, or an array of slugs for a file two modules genuinely share. It was documented as path → sha256 for change detection, but nothing read the hashes (`git diff` is and was the sole change signal) and the value had drifted to the literal string `"analyzed"` for all 52 entries in the committed example vault. Owners are merged, never overwritten: dropping one would leave that module never re-analysed when a file it owns changes.
- **`roots` is a list, and may be shared.** A module can span directories (release tooling covering `scripts/` and `.claude-plugin/`), and several logical modules can share one — `examples/dockhand` has Docker Engine, Database, Auth and Security, and Stacks and Git all inside `src/lib/server/`, the "flat structure" case `analysis-guide.md` already supported. Resolution is a documented four-case order: exact `files_analyzed` hit, unique root prefix, ambiguous shared root (re-analyse every module sharing it, prefer full mode), then outside all modules.
- **Cross-module docs regenerate conditionally**, gated on `graph_changed` / `issues_changed` / `purposes_changed` / `patterns_changed` / `modules_changed`. They are projections of the graph, the purposes, the patterns and the issue set; if none moved, regenerating produced near-identical prose at Sonnet cost and churned the vault diff. **A gate must cover every input in its output's Phase 2 dispatch-table row** — the rule is stated where gates are defined, because the first System Overview gate omitted system-wide patterns and would have let the vault's flagship document silently stop matching the synthesis it projects. Skips must name the unchanged signal; a silent skip is indistinguishable from a bug.
- **Update verification is scoped** to the files written this run, plus — only when something was deleted or renamed — files carrying links to the removed titles. Those are the only two sets that can newly break. Baseline generate still sweeps the whole vault.
- **The concurrency guard covers the whole run.** Reports are written at Step 5 but state at Step 8, so a guard that only fired at Step 8 could leave a losing run's reports beside the winner's state. The claim is recorded at Step 1 and re-checked before any report is written. Damage is also self-healing: a carried-forward report that is missing, has no frontmatter, lacks a required `###` heading, or whose `source-commit` disagrees with state marks that module affected, so it is re-analysed rather than trusted.
- **Deleted-module cleanup is specified end to end.** Remove the module's doc and report, its `modules` / `module_index` / `files_analyzed` entries, and any `dependency_graph` edges pointing at it; mark its issues `resolved` in the Step 6 merge (deletion is the one case where the evidence rule is met by removal rather than a diff). Modules that linked to it form a **relink set**: their docs are regenerated from their existing, untouched reports — no re-analysis — so the dangling `dependencies:` entries and prose wikilinks are actually repaired instead of reported once and then made invisible by scoped verification.
- **Digest builds non-scoped module overviews from `module_index`**, which Step 2 already reads — replacing N partial document reads with none — falling back to per-doc extraction on v1 vaults. Digest remains strictly read-only and never migrates a vault.

### Removed

- **The duplicated issue-merge table in `code-to-docs-update/SKILL.md`.** That file instructs "do not duplicate the reference's per-step tables here" and then hosted one twenty lines below, and the two copies had already drifted. `CLAUDE.md` records that these files drifted once before, which is why the SKILL was collapsed into a checklist. The merge rules now live only in `analysis-guide.md`, with the one non-negotiable invariant — resolved requires positive evidence — restated as a guardrail.
- **Per-file content hashes** from `files_analyzed` (see above).

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
