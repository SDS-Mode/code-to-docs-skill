---
name: code-to-docs-digest
description: Load existing code-to-docs vault context into the conversation before coding. Read-only — never writes files. Provides architecture overview, module summaries, known issues, and session history. Use when starting a coding session, loading doc context, or catching up on a documented codebase.
---

## Overview

Load structured context from an existing code-to-docs vault. Read-only, never writes files.

### Related Skills

| Skill | Purpose |
|-------|---------|
| `code-to-docs:code-to-docs` | Generate full documentation vault from a codebase |
| `code-to-docs:code-to-docs-update` | Incremental update — re-analyze only modules with changes since last run |

## Invocation

```
Skill(skill: "code-to-docs:code-to-docs-digest", args: "<vault-path> [--scope <module,...>] [--focus issues|architecture|all]")
```

- `<vault-path>` — path to existing code-to-docs vault (required)
- `--scope` — comma-separated module names to load in full (default: overview only)
- `--focus` — `architecture` (default), `issues`, or `all`

---

## Model

**Haiku** — read-and-present task. No analysis or generation required.

---

## Execution

### Step 1: Validate Vault

1. Check that `<vault-path>/_state/analysis.json` exists. If missing, stop and report:

   > No code-to-docs vault found at `<vault-path>`. Run `/code-to-docs:code-to-docs` to generate one first.

2. Validate `_state/analysis.json` against the schema in `../code-to-docs-references/output-structure.md` "State File Validation" section (required fields and types). If the file exists but is malformed or missing required fields, abort with a specific error naming the problem — do **not** partially load or guess. Suggest regenerating with `/code-to-docs:code-to-docs` or `/code-to-docs:code-to-docs-update`.

   An absent `schema_version` or `module_index` is **not** a validation failure — it marks a v1 vault, which digest reads fine via the fallbacks noted below. Digest is read-only, so it never migrates a v1 vault; that is `code-to-docs:code-to-docs-update`'s job.

**Graceful degradation (Steps 2–4):** if any *other* referenced file (System Overview, Dependency Map, System Map, `_state/synthesis.md`, or a `Health/` file) is missing — as happens with partial or older vaults — note its absence in the summary and continue with the files that do exist. Only a missing or invalid `_state/analysis.json` is fatal.

### Step 2: Load Baseline

Read:
- `_state/analysis.json` — module inventory, dependency graph, timestamps
- `Architecture/System Overview.md` — architecture narrative and diagrams

### Step 3: Load Focus Content

| `--focus` value | Files loaded |
|-----------------|-------------|
| `architecture` (default) | `Architecture/Dependency Map.md`, `Architecture/System Map.canvas` |
| `issues` | `Health/Limitations.md`, `Health/Code Review.md`, `Health/Health Summary.md` |
| `all` | All architecture + all issues files |

### Step 4: Load Scoped Modules

- For modules listed in `--scope`: load the full `Modules/{Name}.md`. This is the reader-facing doc, which is what a human catching up actually wants.
- For all other modules: load only a light overview, using the cheapest source available:

| Vault has | Source for non-scoped module overviews |
|-----------|----------------------------------------|
| `module_index` (v2) | Each entry's `purpose` and `complexity` — **already loaded in Step 2, so this costs no extra reads at all** |
| No `module_index` (v1) | Fall back to per-module extraction: the `### What Is This?` paragraph under `## Beginner`, plus frontmatter `complexity`/`status` |

Prefer the v2 path whenever `module_index` is present: the whole non-scoped inventory comes free from a file Step 2 already read, replacing N partial document reads with zero. Do **not** load the whole `## Beginner` section (prerequisites, key concepts, walkthrough, example) for non-scoped modules on either path — it is far larger than an overview and blows the token budget.

### Step 5: Present Context Summary

Output a structured summary including:
- Architecture overview (from System Overview)
- Module inventory with status
- Focus-specific details (architecture maps or health issues)
- Scoped module deep-dives

---

## Token Budget

These are **soft, best-effort targets** — the skill has no token counter, so treat them as guidance and use the line-count proxies below rather than exact measurement (rough rule: ~4 characters ≈ 1 token).

| Configuration | Soft target | Proxy to stay under it |
|---------------|-------------|------------------------|
| Default (no flags) | ~3K tokens | Non-scoped module overviews ≤ ~6 lines each (one line each via `module_index`); include only the last ~3 sessions |
| `--scope` specified | ~6K tokens | Full docs only for scoped modules; ~6-line overviews for the rest |
| `--focus all` | ~10K tokens | Load all focus files, but truncate the oldest session history first if the summary grows large |

When in doubt, prefer the shorter summary — the user can always pull more in with `--scope`.

---

## Red Flags

Do NOT do any of the following:

- **Writing any files** — this skill is strictly read-only. That includes migrating a v1 state file: read it as-is via the fallbacks and leave it alone
- **Running generation or analysis** — if the user wants updates, suggest `/code-to-docs:code-to-docs-update` instead
- **Loading all modules without `--scope` or `--focus all`** — only load overviews by default to stay within token budget
- **Reading every `Modules/{Name}.md` to build the module inventory** when `module_index` is present — it already carries every module's purpose and complexity, at no extra read
- **Reading `_state/modules/*.md` reports** — those are analysis internals for generate/update. Digest presents the reader-facing vault
- **Using a non-Haiku model** — this is a simple read-and-present task; Haiku is sufficient
