---
name: code-to-docs-update
description: Incrementally update an existing code-to-docs vault after coding changes. Diffs against the last documented commit, re-analyzes only affected modules, merges with existing docs, and tracks issue resolution. Use when someone says update docs, sync docs, refresh documentation, or after making code changes.
---

## Overview

Run an incremental documentation update instead of a full generation. Reads `_state/analysis.json` from the existing vault, diffs against the stored commit, re-analyzes only affected modules, and merges results with existing docs.

**The governing idea:** touch only what changed. A module that did not change is carried forward by *leaving its analysis report alone* on disk — not by reading it, not by re-summarizing it, and never by re-deriving its boundaries. Anything the update needs to know about an unchanged module is already in `_state/analysis.json`.

## Related Skills

| Skill | Purpose |
|-------|---------|
| `code-to-docs:code-to-docs` | Full generation (quick or full mode) — use when no vault exists yet |
| `code-to-docs:code-to-docs-digest` | Load existing vault context before coding (read-only) |

## Invocation

```
Skill(skill: "code-to-docs:code-to-docs-update", args: "<path> [--output <path>]")
```

- `<path>` — codebase root (default: `.` current directory)
- `--output` — vault path containing the existing `_state/analysis.json` (default: `./docs-vault/`)

## Prerequisites

- An existing vault with `_state/analysis.json` at the output path
- The codebase must be a git repository, **and** the vault's stored `git_commit` must be non-null and reachable in the current repo (needed for `git diff`)
- If any prerequisite is missing, fall back to a full generate run and inform the user

A vault written before the analysis artifacts existed (no `schema_version` / `module_index`) is **not** a missing prerequisite — it migrates in place with a one-time Haiku backfill. See Step 1 below.

---

## Model Tiers

Same tiers as `code-to-docs:code-to-docs` — see that skill for the full table. Key rule: use the cheapest model that meets the task's cognitive demand. Haiku for extraction/mechanical, Sonnet for writing, Opus only for complex modules or large-codebase synthesis.

Pass 2 tier selection reads the `escalate` flag from the module's fresh Pass 1 receipt — do not re-derive it from the report's prose.

---

## Pass Pointers, Not Payloads

Same rule as `code-to-docs:code-to-docs`, and it is what makes an update cheap: agent prompts carry paths and small structured data, never the text of a file on disk. See `../code-to-docs-references/output-structure.md` "The Reference-Passing Rule".

In update mode this has one specific consequence worth stating plainly: **carrying a module forward is a no-op.** Its `_state/modules/<slug>.md` report already sits at the path recorded in `module_index`, so an unchanged module costs zero reads and zero tokens. Reading it — or reading its generated `Modules/{Name}.md` — to "carry it forward" defeats the entire mechanism.

---

## Execution

**`../code-to-docs-references/analysis-guide.md` section "Incremental Update Flow" is authoritative for every step below — read it before executing.** Also read `../code-to-docs-references/output-structure.md` (state schema, vault layout) and `../code-to-docs-references/obsidian-templates.md` (formatting rules). Do not duplicate the reference's per-step tables here.

The flow, in order:

1. **Load & validate state** — read and schema-validate `_state/analysis.json`; on missing or malformed state, fall back to a full generate run. If `schema_version` or `module_index` is absent, run the one-time v1 → v2 migration (Haiku-only backfill) and continue — do **not** fall back to full generate. Read only the state file here.
2. **Check the stored commit, then diff** — if `git_commit` is null or unreachable (rebased/squashed/gc'd/shallow), fall back to full generate. Otherwise run `git diff <stored_commit>..HEAD --name-only`, and also capture the **content diff** of changed files inside known module roots, scoped by `module_index[*].roots` (step 4 needs it). Empty diff → report "no changes" and exit.
3. **Map changed files to modules** — a lookup, not a survey: exact `files_analyzed[path]` hit, else a *unique* root prefix match, else an *ambiguous* match where modules share a root, else outside every module. See `output-structure.md` "Resolving a Changed File to Its Module". Build the affected-module list; everything else is carried forward.
4. **Auto-select quick/full** — decide *now*, from the changed-file list, `files_analyzed`, `module_index`, and the step-2 content diff (used to detect new cross-module imports). New/deleted module, changed dependency structure, or >50% churn → full; otherwise quick. When unsure, prefer full.
5. **Re-analyze affected modules** — same two-pass analysis as baseline, writing to each module's existing report path: Pass 1 overwrites sections 1-6, Pass 2 appends section 7. Unchanged modules are left alone entirely.
6. **Merge synthesis** — rebuild the dependency graph from fresh receipts plus the stored graph, rewrite `_state/synthesis.md`, and merge issues (see Issue Tracking below).
7. **Selective generation** — regenerate architecture, health, and affected module docs; preserve unchanged module docs. Pass inputs by reference per the Phase 2 dispatch table.
8. **Update state (with a concurrency guard)** — re-read the state file and abort if its `git_commit`/`timestamp` changed since step 1 (a concurrent update); otherwise write the new state and append a session entry. Re-analyzed modules get fresh `module_index` entries; carried-forward modules keep their **original** `analyzed_at` / `source_commit`.
9. **Verify** — Haiku agent checks wikilinks + frontmatter across the whole vault.

---

## Issue Tracking Across Updates

When merging the new analysis with the previous `issues` array:

| Scenario | Action |
|----------|--------|
| Issue still reported in a re-analyzed module | Keep with status `open` |
| Issue no longer reported, **and** the diff touched its `file`/`lines` | Mark `resolved` |
| Issue no longer reported, but the diff did **not** touch its `file`/`lines` | Keep `open` — treat the omission as Pass 2 non-determinism, not a fix |
| Issue in a module that wasn't re-analyzed | Keep `open` (carried forward) |
| New issue found in a re-analyzed module | Add with status `open` |

Marking an issue `resolved` requires positive evidence that the code it points at actually changed. Never flip an issue to `resolved` merely because a non-deterministic re-analysis didn't mention it — that silently tells users a still-present bug is fixed.

---

## Red Flags

1. Diffing against a null or unreachable stored commit instead of falling back to full generation
2. Marking an issue `resolved` without the diff having touched its file/lines
3. Choosing quick vs full from data that only exists after re-analysis — the mode is decided in step 4 from signals gathered in step 2
4. Re-analyzing unchanged modules — only affected modules get re-analyzed
5. Skipping state-file validation, or overwriting state without the step-8 concurrency guard
6. Deleting unchanged module docs — preserve them, only regenerate affected ones
7. **Re-surveying the codebase to re-derive module roots** — `module_index` is authoritative; a re-survey can rename a module and break every wikilink pointing at it
8. **Reading an unchanged module's `_state/modules/<slug>.md` or `Modules/{Name}.md`** — carrying forward means leaving the file alone, not loading it
9. **Advancing a carried-forward module's `analyzed_at` / `source_commit`** — that falsely claims it was analyzed at this commit and destroys staleness tracking
10. Falling back to a full generate run on a v1 state file instead of migrating it
11. All red flags from `code-to-docs:code-to-docs` also apply during the re-analysis phases — including its reference-passing rules

## Rationalization Traps

| Thought | Reality |
|---------|---------|
| "I need to see the unchanged modules to write a coherent system overview" | Their names, purposes, deps, and complexity are in `analysis.json`, and last run's one-liners are in `_state/synthesis.md` § Module Purposes. |
| "I'll just re-glob for the module roots, it's cheap" | It is not free, and it is not safe: a redrawn boundary renames a module and orphans its doc. `module_index` is the contract. |
| "This vault is the old schema, safest to regenerate from scratch" | Migration is a Haiku-only backfill. A full regenerate is exactly the cost this schema exists to avoid. |
| "Re-analysis didn't mention that issue, so it's fixed" | Only if the diff touched the code it points at. Otherwise it is Pass 2 non-determinism — keep it `open`. |
| "I'll refresh every module's timestamp so state looks consistent" | Then nothing records which reports are stale. Only re-analyzed modules get new timestamps. |
