---
name: code-to-docs-update
description: Incrementally update an existing code-to-docs vault after coding changes. Diffs against the last documented commit, re-analyzes only affected modules, merges with existing docs, and tracks issue resolution. Use when someone says update docs, sync docs, refresh documentation, or after making code changes.
---

## Overview

Run an incremental documentation update instead of a full generation. Reads `_state/analysis.json` from the existing vault, diffs against the stored commit, re-analyzes only affected modules, and merges results with existing docs.

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

---

## Model Tiers

Same tiers as `code-to-docs:code-to-docs` — see that skill for the full table. Key rule: use the cheapest model that meets the task's cognitive demand. Haiku for extraction/mechanical, Sonnet for writing, Opus only for complex modules or large-codebase synthesis.

---

## Execution

**`../code-to-docs-references/analysis-guide.md` section "Incremental Update Flow" is authoritative for every step below — read it before executing.** Also read `../code-to-docs-references/output-structure.md` (state schema, vault layout) and `../code-to-docs-references/obsidian-templates.md` (formatting rules). Do not duplicate the reference's per-step tables here.

The flow, in order:

1. **Load & validate state** — read and schema-validate `_state/analysis.json`; on missing or malformed state, fall back to a full generate run.
2. **Check the stored commit, then diff** — if `git_commit` is null or unreachable (rebased/squashed/gc'd/shallow), fall back to full generate. Otherwise run `git diff <stored_commit>..HEAD --name-only`, and also capture the **content diff** of changed files inside known module roots (step 4 needs it). Empty diff → report "no changes" and exit.
3. **Map changed files to modules** — build the affected-module list.
4. **Auto-select quick/full** — decide *now*, from the changed-file list, `files_analyzed`, and the step-2 content diff (used to detect new cross-module imports). New/deleted module, changed dependency structure, or >50% churn → full; otherwise quick. When unsure, prefer full.
5. **Re-analyze affected modules** — same two-pass analysis as baseline; carry unchanged modules forward without re-analysis.
6. **Merge synthesis** — rebuild the dependency graph and merge issues (see Issue Tracking below).
7. **Selective generation** — regenerate architecture, health, and affected module docs; preserve unchanged module docs.
8. **Update state (with a concurrency guard)** — re-read the state file and abort if its `git_commit`/`timestamp` changed since step 1 (a concurrent update); otherwise write the new state and append a session entry.
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
7. All red flags from `code-to-docs:code-to-docs` also apply during the re-analysis phases
