# Changelog

All notable changes to the code-to-docs skill are documented in this file.

## 2026-07-26

Reference-passing refactor of the analysis pipeline, aimed at `:update`. It was expensive for a structural reason: the orchestrator acted as a data bus, and every payload it pasted into an agent prompt was Opus *output* tokens retyping bytes that already existed on disk — where they then existed twice, once in the orchestrator's context and once in the agent's.

Two gaps in the state file made that unavoidable rather than merely wasteful. Module root paths were never persisted, yet the update flow required them to decide which module a changed file belonged to — so every run silently re-surveyed the codebase to re-derive them, at orchestrator cost and with the risk that a redrawn boundary renames a module and orphans its doc. And the per-module analysis reports were never persisted, so "carry forward the existing reports" degenerated into reading every unchanged module's full audience-level doc into Opus context and re-serialising it into synthesis.

Hook-script and release-tooling fixes, both found by running the documentation pipeline over this repository's own source. The hook fixes were reproduced against scratch fixtures; the release fixes against a scratch repo with a local origin and a stubbed `gh`. Neither was inferred from reading alone.

### Added

- **Analysis artifacts in `_state/`.** `modules/<slug>.md` holds each module's seven-section report (Pass 1 writes §1-6, Pass 2 appends §7). `synthesis.md` holds cross-module facts in five sections: Architecture Narrative, Architecture Type, System-Wide Patterns, Cross-Cutting Themes, Issue Themes. All headings are exact and fixed, so a downstream agent greps one section instead of reading the file.
- **The reference-passing rule.** Agent prompts carry paths and small structured data, never the text of a file on disk; inline context is capped at roughly 500 tokens. Codified in `output-structure.md`, in the Phase 1 and Phase 2 dispatch tables' Input columns, as Token Efficiency Rules 9–11, and as Red Flags and Rationalization Traps in the generate and update skills.
- **`module_index` in the state file** — per module: slug, purpose, root paths, entry points, language, complexity, LOC, report path, doc path, and per-module `analyzed_at`/`source_commit`. This makes change-to-module mapping a lookup instead of a survey, and makes carry-forward auditable. It is authoritative for module boundaries.
- **`architecture_type` and `system_patterns` in the state file**, so an update can tell whether the system-wide picture moved without reading the previous `synthesis.md` back.
- **`schema_version` and a v1 → v2 migration.** An older vault migrates in place with a Haiku-only backfill — Pass 1 re-extracts §1-6, and a second Haiku agent reformats §7 from the `issues` array v1 already persisted — instead of being forced through a full regenerate. Migrated §7 has no before/after snippets, since v1 stored issue records rather than prose, and the skill says so rather than letting a thin Health entry read as a clean module.
- **`tests/pressure-test-update.md`** — a v2 incremental run and a v1 migration run. Most checkpoints assert *absences* (no re-survey, no unchanged-report reads, no pasted payloads), so they are verified from the transcript rather than the output vault.

### Changed

**Analysis pipeline**

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

**Release tooling**

- The confirmation prompt names what it authorizes — which directories under `~/.claude/skills/` will be replaced, and that both the tag and the release are public — and accepts `yes` as well as `y`. It was previously a bare "Proceed?" that rejected `yes`.
- A manifest version ahead of the newest tag is now reported: it means versions were bumped but never released, so the notes span more than one release.

### Fixed

**After the first live run of the refactored pipeline**

Executing the pipeline against this repo surfaced defects that four passes of prose review had not. The mechanism-level ones are described above; these were found by the pipeline's own Opus issue-analysis agent reading the specification as its subject, and each was independently verified:

- **The new-module trigger cited the wrong resolution case.** Update Steps 4 and 5 referred to "Step 3 rule 3" for paths outside every module root, but renumbering to four cases made that case 4. Full mode fired correctly, then module identification was scoped to case-3 paths — which lie *inside* existing modules — so a genuinely new top-level directory would never be identified, on that run or any later one.
- **The state-writer's JSON literal omitted `purpose`, `architecture_type` and `system_patterns`.** They were added to the schema but not to the shape handed to the Haiku writer, so the produced state file would lack exactly the fields the `purposes_changed` / `patterns_changed` gates, the wikilink context and digest's inventory depend on.
- **The concurrency guard could not detect an in-flight run.** Its claim token was only ever read, never written, so two runs starting in the same window both passed the pre-Step-5 check and both wrote reports — the precise corruption the guard exists to prevent. The claim is now an exclusive-create `_state/.lock`, released on every exit path including the empty-diff one.
- **Adding `_state/` to Exclusions forbade the design.** That section says "do not pass them to agents", which literally prohibited handing report paths to Pass 2. Exclusions is now scoped to what counts as *source*, explicitly excepting the pipeline's own artifacts.
- **`purposes_changed` byte-compared LLM prose.** A re-analysed module almost always rewords its one-line purpose, so the gate was true on nearly every update and quietly restored unconditional regeneration. Both prose signals now compare by substance, with "when unsure, regenerate" as the tie-break.
- **The Phase 1 dispatch table still gated Pass 2 on the raw `escalate` flag**, contradicting the `escalate_final` recomputation defined below it.

**Hook scripts**

- **Code injection in the SessionStart hook** — `digest-on-start.sh` spliced the vault path into a `python3 -c` string literal, so a quote in the path terminated the literal and the remainder was evaluated as Python. Demonstrated end to end: a vault directory named as a payload both executed a side effect and redirected `open()` to a different file than the one the existence guard had checked. The path is now passed as `argv`, matching the discipline `setup.sh` already used.
- **A hook that misinformed the model it exists to inform** — the same extractor ended in `2>/dev/null || echo "unknown ... 0"`, so *every* failure (a quote in the path, corrupt JSON, schema drift, a missing `python3`) collapsed into a banner of `unknown` values asserting **`Open issues: 0`**. Since that text is injected straight into Claude's context, a vault with open issues was reported as having none. Failures now say so on stdout and print the diagnostic on stderr, and the count is never printed unless it was computed.
- **Setup and teardown deleted co-located user hooks** — both filtered `.claude/settings.json` at the handler-group level, discarding an entire group when any hook inside it carried `source: "code-to-docs"`. A hook the user had added alongside ours vanished on the next `setup.sh` or `teardown.sh` run, with no backup, contradicting the skill's "other hooks are left untouched" promise while `setup.sh` invited the user to hand-edit the file. Both now filter individual hook objects and drop a group only once it is empty.
- **Teardown deleted a settings file it never modified** — the empty-file check ran unconditionally, so a pre-existing `.claude/settings.json` containing only `{}` was unlinked while teardown reported removing zero hooks. Deletion is now conditional on having actually removed something, and the counter counts hooks rather than handler groups.
- **The staleness banner always looked stale** — the stored commit was truncated to 8 characters while the live one came from `git rev-parse --short` (7 in a small repo), so the two never rendered identically even when the vault was current. Both are now 8.
- **`teardown.sh` built its Python program by shell interpolation** — not exploitable, since the settings path is a constant, but the same construction as the injection above and the opposite convention from `setup.sh`. Converted to `argv`; also dropped the trailing `2>&1` that merged tracebacks into normal output.

**Release tooling**

- **`bump.sh` aborted after the tag was public.** `PREV_TAG=$(git tag --sort=-v:refname | grep -v "v$NEW_VERSION" | head -1)` runs *after* the tag is pushed. When the new tag is the repo's only tag, `grep -v` matches nothing and exits 1, `pipefail` promotes that to the pipeline's status and `set -e` ends the run — leaving a public tag with no GitHub release and no error explaining why. The first-release `else` branch below it was therefore unreachable dead code. Release notes are now computed *before* anything is published, which also removes the need to filter the new tag at all: the newest existing tag is by definition the previous release.
- **Nothing prevented releasing from a feature branch.** The documented invariant is "release from `main` after the PR merges," on the reasoning that the branch push would fail preflight. It does not — the push is bare and mid-flight, and on a feature branch with an upstream it succeeds, after which the script tags an unmerged commit and publishes a release from it. Preflight now requires the default branch and a checkout that is not behind origin.
- **No rollback between pushing the tag and creating the release.** Any failure in that window — a `gh` rate limit, an expired token, insufficient permission, a network drop — left an orphaned public tag that also blocks a naive re-run at `git tag`. That window is now covered by a trap that deletes the tag locally and on origin, and reports the state that remains.
- **`rm -rf` under a guard that cannot fire.** `${LOCAL_SKILLS_ROOT:?}` fires only when the variable is unset or empty; under `set -u` an unset `HOME` already aborts earlier, while a `HOME` that is *set but empty* — routine in cron, containers and `env -i` — yields `/.claude/skills`, which is non-empty and passes the guard. The property is now asserted directly.
- **An empty `skills/` created a directory literally named `*`.** Without `nullglob` the unmatched pattern is passed through, so the mirror loop ran once with `dir='*'`, created that directory in the user's skills dir, then aborted on the nonexistent source — with the manifest already bumped.
- **Weak input validation.** The repo slug was only checked for containing a slash, so `ssh://`, GitHub Enterprise and non-GitHub remotes passed and failed later at `gh release create`; `[0-9]*` accepted `1`, `1.2.3.4` and `9junk` as versions; and a tag collision surfaced only at `git tag`, after the manifest and `$HOME` had been rewritten. All three are now preflight checks with shape assertions.

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
