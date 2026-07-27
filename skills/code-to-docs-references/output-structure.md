# Output Structure — Vault Layout Reference

Supporting reference for the `code-to-docs` skill. Loaded on demand during Phase 2 (Documentation Generation).

**Frontmatter:** All generated files require frontmatter — see `obsidian-templates.md` for the full schema. Both the Dataview queries in Index.md and the Bases catalog in Documentation.base depend on frontmatter fields (`title`, `language`, `complexity`, `status`, `type`, `generated-at`) and tags (`#code-docs`, `#module`, etc.).

---

## The Reference-Passing Rule

**An agent prompt carries pointers, not payloads.** If content exists on disk, pass its path — and the specific section to read — never its text. Inline context in an agent prompt is capped at roughly 500 tokens; anything larger must be a reference.

This rule exists because the orchestrator runs at Opus. Every payload pasted into an `Agent()` prompt is Opus *output* tokens spent retyping bytes that already exist on disk, and those bytes then exist twice — once in the orchestrator's context and once in the agent's. Passing a path costs ~20 tokens and lets the agent read the content at its own (cheaper) tier.

The analysis artifacts written in Phase 1 (see "Analysis Artifacts" below) exist to make this rule satisfiable: there is always a file to point at.

| Instead of pasting | Pass this reference |
|--------------------|---------------------|
| A module's 7-section analysis report | `_state/modules/<slug>.md` |
| The full synthesis output | `_state/synthesis.md`, naming the `c2d:yN` markers needed |
| One-line purposes of every module (wikilink context) | `module_index` purposes — compact, pass inline |
| A module's issue prose and before/after snippets | `_state/modules/<slug>.md` marker `s7` |

Small structured data — the dependency graph, the module list, issue records — is already compact and may be passed inline.

---

## Phase 2 Dispatch Table

This table is the authoritative dispatch reference for Phase 2. Every `Agent()` call MUST set `model:` to match the Model column.

Dispatch as parallel agents where possible. The Input column is a **reference specification**, not a payload description — pass exactly what is listed, by path where a path is given. Never substitute pasted text for a listed path.

| Output | Model | Input (by reference) | Notes |
|--------|-------|----------------------|-------|
| `Architecture/System Overview.md` | **Sonnet** | `_state/synthesis.md` markers `y1`,`y2`,`y3` (Narrative, Type, Patterns) + `dependency_graph` (inline) | Narrative architecture writing |
| `Architecture/Dependency Map.md` | **Haiku** | `dependency_graph` + `modules` (inline — already compact) | Data → Mermaid + table transform |
| `Architecture/System Map.canvas` | **Haiku** | `dependency_graph` + `modules` (inline) | Data → JSON Canvas transform |
| `Modules/{Name}.md` (×N) | **Sonnet** | `_state/modules/<slug>.md` (all 7 sections) + `module_index` name→purpose pairs (inline) for wikilink context | One agent per module, parallel |
| `Health/Health Summary.md` | **Haiku** | Issue counts by severity/type/module (inline) | Data → Mermaid chart transform |
| `Health/Limitations.md` + `Health/Code Review.md` | **Sonnet** | `issues` filtered by type (inline) + `_state/modules/<slug>.md` marker `s7` for the modules covered | Requires judgment for framing; the §7 prose supplies the before/after snippets |
| `Patterns/{Name}.md` (full mode) | **Sonnet** | `_state/synthesis.md` marker `y3` + report paths of the modules exhibiting the pattern | Pattern identification + writing |
| `Onboarding/` (full mode) | **Sonnet** | `_state/synthesis.md` (all sections) + `module_index` (inline) + report paths | Requires broad codebase understanding |
| `Cross-Cutting/{Name}.md` (full mode) | **Sonnet** | `_state/synthesis.md` marker `y4` + report paths of the relevant modules | Requires cross-module reasoning |
| `Documentation.base` | **Haiku** | `module_index` (inline) | Mechanical YAML assembly |
| `Index.md` | **Haiku** | Project name + timestamp + mode | Template fill (Dataview fallback) |
| `_state/analysis.json` | **Haiku** | Pass 1 + Pass 2 receipts (inline), the **synthesis receipt** (`architecture_type`, `system_patterns`), report paths for the `files:` frontmatter, and the run facts the orchestrator alone holds: `project`, `git_commit`, `timestamp`, `mode`, plus the `sessions` entry for this run | Mechanical JSON assembly |

---

## Vault Directory Layout

```
docs-vault/
├── _state/
│   ├── analysis.json           # Incremental contract state file (metadata only)
│   ├── modules/
│   │   └── {slug}.md           # Per-module 7-section analysis report
│   └── synthesis.md            # Cross-module synthesis facts (section-addressable)
├── Architecture/
│   ├── System Overview.md      # Top-level architecture narrative
│   ├── Dependency Map.md       # Cross-module dependency Mermaid
│   └── System Map.canvas       # Canvas linking to all module notes
├── Modules/
│   └── {Module Name}.md        # Per-module doc (beginner/intermediate/advanced + API ref)
├── Patterns/                   # full mode only
│   └── {Pattern Name}.md
├── Onboarding/                 # full mode only
│   ├── Getting Started.md
│   ├── First Contribution.md
│   └── Debugging Guide.md
├── Cross-Cutting/              # full mode only
│   └── {Concern Name}.md
├── Health/
│   ├── Limitations.md          # Architecture and component constraints
│   ├── Code Review.md          # Bugs, risks, and improvement opportunities
│   └── Health Summary.md       # Aggregate charts and severity breakdown
├── Documentation.base          # Obsidian Bases catalog (native, no plugins needed)
└── Index.md                    # Hub page with Dataview queries (fallback)
```

---

## File Naming

- Title case with spaces (Obsidian-native): `User Service.md`, `Payment Gateway.md`
- Pattern files named after the pattern: `Repository Pattern.md`, `Event Sourcing.md`
- One module = one file in `Modules/`
- One pattern = one file in `Patterns/`
- One cross-cutting concern = one file in `Cross-Cutting/`
- Sanitize illegal filename characters (`/`, `:`, `?`, `*`, `<`, `>`, `|`) — replace with hyphens
- **Normalise `&` to `and` in the module *name* itself, at identification time** — so the title is `Packaging and Release`, not `Packaging & Release`. This is not a filename-legality issue; `&` is legal in a filename. It is that agents silently "tidy" an ampersand into `and` when writing a wikilink, and inconsistently: on one live run a Haiku agent wrote `[[Packaging and Release]]` in the Dependency Map and Canvas while a Sonnet agent wrote `[[Packaging & Release]]` in the System Overview, against a file actually named `Packaging & Release.md`. Every one of those links silently failed to resolve. Removing the character from the title removes the temptation. Apply the same reasoning to any character an agent might normalise — smart quotes, en-dashes, non-breaking spaces.

---

## Canvas Generation

Generate exactly one Canvas file: `Architecture/System Map.canvas`

The Canvas file is valid JSON Canvas format. Structure:

```json
{
  "nodes": [
    {
      "id": "module-slug",
      "type": "file",
      "file": "Modules/Module Name.md",
      "x": 0,
      "y": 0,
      "width": 250,
      "height": 60
    }
  ],
  "edges": [
    {
      "id": "edge-slug",
      "fromNode": "source-module-slug",
      "fromSide": "right",
      "toNode": "target-module-slug",
      "toSide": "left",
      "label": "calls"
    }
  ]
}
```

**Node rules:**
- Use `"type": "file"` for all module nodes — links directly into the module doc (Obsidian derives the display label from the file path)
- The `"file"` field is the vault-relative path to the module markdown file
- Assign columns by topological depth: modules with no dependencies go in column 0, modules that depend only on column-0 modules go in column 1, etc.
- Within a column, order rows alphabetically by module name
- Horizontal spacing: 300px between columns
- Vertical spacing: 150px between rows within a column

**Edge labels** describe the relationship type: `"calls"`, `"depends on"`, `"publishes to"`, `"imports"`, `"extends"`, etc.

---

## Index.md Template

```markdown
---
title: Documentation Index
type: index
generated-by: code-to-docs
generated-at: <ISO 8601 timestamp>
mode: <quick or full>
---

# Documentation Index

Generated by `code-to-docs`. Use the queries below to navigate the vault.

## Modules by Complexity

\`\`\`dataview
TABLE title, language, complexity, status
FROM #code-docs AND #module
SORT complexity DESC
\`\`\`

## Modules by Language

\`\`\`dataview
TABLE rows.title, rows.complexity, rows.status
FROM #code-docs AND #module
GROUP BY language
\`\`\`

## Documentation Status

\`\`\`dataview
TABLE title, type, status
FROM #code-docs
WHERE status != "generated"
SORT file.name ASC
\`\`\`

## Codebase Health

\`\`\`dataview
TABLE title, type, status
FROM #code-docs AND #health
SORT title ASC
\`\`\`

## All Documentation

\`\`\`dataview
TABLE title, type, generated-at
FROM #code-docs
SORT generated-at DESC
\`\`\`
```

---

## Documentation.base — Obsidian Bases Catalog

Generate `Documentation.base` in the vault root. This provides a native Obsidian Bases view — interactive, filterable, no plugins required. It complements Index.md (which uses Dataview) rather than replacing it.

The `.base` file is YAML (not JSON). Filters use the `and`/`or`/`not` recursive structure — flat filter arrays are not valid. Structure:

```yaml
filters:
  and:
    - 'generated-by == "code-to-docs"'

views:
  - type: table
    name: "All Documentation"
    order:
      - file.name
      - title
      - type
      - language
      - complexity
      - status
      - canonical-source
      - dependencies
      - related-notes
    groupBy:
      property: type
      direction: ASC
```

This creates a table view of all generated docs grouped by type. Users can switch between table and card views, add computed columns, or modify filters directly in Obsidian.

**Generation:** Haiku agent — this is a mechanical YAML transform from `module_index`.

---

## Obsidian CLI Integration (Opportunistic)

At the start of Phase 2, check if the `obsidian` CLI is available:

```bash
which obsidian >/dev/null 2>&1
```

If available **and** Obsidian is running (the CLI requires a running instance), use it for note creation and property management. If not available, fall back to direct file writes — the current behavior, with no degradation.

### When obsidian CLI is available

| Operation | Command | Benefit over direct file write |
|-----------|---------|-------------------------------|
| Create note | `obsidian create name="{title}" content="{content}" path="{vault-path}" silent` | Wikilink resolution, property validation |
| Set property | `obsidian property:set name="{key}" value="{val}" file="{title}"` | Obsidian-native property storage |
| Verify backlinks | `obsidian backlinks file="{title}"` | Uses Obsidian's live graph, not grep |

### When obsidian CLI is NOT available

Fall back to direct file writes using the Write tool — identical to current behavior. This is the default and always-works path.

### Integration rules

- **Never require** the obsidian CLI — it is an enhancement, not a dependency
- **Check once** at the start of Phase 2, store the result, and use it for all subsequent operations in the same run
- **Use `silent` flag** on all `obsidian create` calls — do not open notes in the editor during generation
- **Fall back on any error** — if an `obsidian create` call fails, retry with direct file write for that note
- **Do not mix** — if obsidian CLI is available, use it for all notes in the run (consistency in how properties are stored)

### Skill references

When using obsidian CLI, the `obsidian-markdown`, `json-canvas`, and `obsidian-bases` skills contain the authoritative syntax references. Prefer those skills' conventions over the templates in this file when they conflict.

---

## Analysis Artifacts

Phase 1 writes two kinds of durable artifact alongside the state file. They are what make the reference-passing rule possible: every downstream agent has a file to point at instead of a payload to receive. They are also what makes an incremental update cheap — `code-to-docs:code-to-docs-update` carries an unchanged module forward by *leaving its report on disk*, not by reading it.

Both are internal to the skill (like `analysis.json`) and are not part of the reader-facing vault.

### `_state/modules/{slug}.md` — per-module analysis report

One file per module, holding the seven-section report defined in `analysis-guide.md` "Agent Output Schema". **Sections 1–6 are written by the Pass 1 extraction agent; section 7 is appended by the Pass 2 issue-analysis agent.** No other agent writes to it.

```markdown
---
module: Scheduler
slug: scheduler
purpose: Runs recurring background jobs against Docker hosts on a cron schedule.
roots:
  - src/lib/server/scheduler/
language: typescript
complexity: high
loc: 2400
files:
  - src/lib/server/scheduler/index.ts
  - src/lib/server/scheduler/tasks/prune.ts
analyzed-at: 2026-03-29T12:00:00Z
source-commit: 5c3f0fc
---

<!-- c2d:s1 -->
### Architecture
<!-- c2d:s2 -->
### Public API
<!-- c2d:s3 -->
### Internal Patterns
<!-- c2d:s4 -->
### Dependencies
<!-- c2d:s5 -->
### Complexity
<!-- c2d:s6 -->
### Key Files
<!-- c2d:s7 -->
### Limitations & Improvements
```

### Why the markers exist

**Address sections by their `<!-- c2d:sN -->` marker, never by the heading text.** The headings are for human readers; the markers are the machine interface.

This is not belt-and-braces. A report's prose legitimately quotes heading names — a module whose job is to *define* this schema will write `### Dependencies` inside its own Public API section as documentation. The first real run of this pipeline produced exactly that: the report for the module documenting these very sections came back with **twelve** `###` headings instead of six, and a `### Limitations & Improvements` heading present before Pass 2 had run. Every consequence follows from grepping heading text:

- `grep '### Dependencies'` returns more than one hit, so "read one section" reads the wrong one
- the seven-section completeness check passes **spuriously**, on quoted text rather than real sections
- the damage detection in the update flow ("missing a required heading → re-analyse") does not fire
- Pass 2 appends a second §7, and a Health writer grepping for it can get the schema example instead of the issues

An HTML comment cannot appear in quoted heading text, renders as nothing in Obsidian, and survives a Markdown round-trip. So:

| Operation | Do this | Not this |
|-----------|---------|----------|
| Read one section | Find the anchored `<!-- c2d:s4 -->` line, read to the next **anchored** marker line or EOF | `grep '### Dependencies'` |
| Check completeness | Count **anchored** `<!-- c2d:s1 -->`…`<!-- c2d:s7 -->` lines, each exactly once | Count `###` headings, or count loose `<!-- c2d:s` substrings |
| Append §7 | Write `<!-- c2d:s7 -->` alone on its own line, then the heading | Write the heading alone |
| Detect damage | A missing or duplicated **anchored** marker | A missing heading |

<a id="the-anchored-marker-pattern"></a>
#### The anchored marker pattern

**Every marker match — counting, section boundaries, damage detection — must anchor to a whole line:**

```
module reports:  ^<!-- c2d:s[1-7] -->$
synthesis:       ^<!-- c2d:y[1-5] -->$
```

In practice: `grep -cE '^<!-- c2d:s[1-7] -->$' <report>` must return exactly `7`.

**A substring match is not sufficient, and the prompt guard above is not a substitute for this.** Markers are the machine interface, so the modules most likely to be misparsed are precisely the ones that *document the marker scheme* — their prose contains marker strings as data. Measured on a live run of this pipeline: loose `<!-- c2d:s` counted **8** and **9** on two of six reports whose true section count was 7. Adding the "never write a marker in prose" instruction to the Pass 1 prompt moved those counts from 9 to 7 and 8 — it reduced the error without eliminating it, because it asks a probabilistic writer to never emit a string it is legitimately describing.

The anchor eliminates it structurally instead. A marker quoted in prose is inside backticks, inside a fenced block, or indented in a table cell — none of which can satisfy `^` immediately followed by `<!--` and `-->$`. Keep the prompt guard as well; it reduces reader confusion. But **never rely on it for correctness**, and never let a matcher fall back to a substring because "the guard should have prevented it."

The consequences of getting this wrong are not cosmetic: a spurious count fails the completeness check on a report that is in fact complete, so the update flow's damage detection re-analyzes exactly the modules it just finished analyzing, and "read to the next `<!-- c2d:s`" truncates §1 at a prose mention partway through it.

**Rules:**

- `slug` is the module name lowercased with non-alphanumerics collapsed to single hyphens (`Docker Engine` → `docker-engine`, `Auth and Security` → `auth-and-security`). It must match the `slug` in `module_index` and the values in `files_analyzed`. Derive it from the **normalised** name — because `&` is removed at identification time (see below), a slug never has an ampersand to collapse, and `Packaging and Release` gives `packaging-and-release`. Deriving a slug from an un-normalised `Packaging & Release` yields `packaging-release`, which is no longer reproducible from the module's own name — every later agent that re-derives the slug looks for the wrong file.
- `roots` is a **list**, because a module is not always one directory: it may span several (release tooling covering `scripts/` and `.claude-plugin/`), and several logical modules may **share** one directory (a flat `src/lib/server/` holding Docker, Database, and Auth as separate modules — the case `analysis-guide.md` Step 2 calls a "flat structure"). Record the narrowest directories that cover the module's files.
- The seven `<!-- c2d:sN -->` markers are the addressable interface and must each appear **exactly once**, in order, each alone on its own line so it matches `^<!-- c2d:s[1-7] -->$`. The `###` headings must accompany them and stay exact for human readers, but nothing machine-readable may depend on heading text alone.
- `source-commit` records the commit the report was extracted from, so an update can tell which reports are stale without re-reading them. `analyzed-at` is refreshed only when the module is actually re-analyzed.
- On re-analysis, Pass 1 **overwrites** the file (frontmatter + sections 1–6) and Pass 2 **appends** section 7. Never partially patch a report.

### `_state/synthesis.md` — cross-module synthesis

One file, written by the synthesis step, holding the cross-module facts that Phase 2 narrative agents need. It replaces passing "the full synthesis" as a payload.

```markdown
---
project: dockhand
architecture-type: modular monolith
module-count: 10
synthesized-at: 2026-03-29T12:00:00Z
source-commit: 5c3f0fc
---

<!-- c2d:y1 -->
## Architecture Narrative
<!-- c2d:y2 -->
## Architecture Type
<!-- c2d:y3 -->
## System-Wide Patterns
<!-- c2d:y4 -->
## Cross-Cutting Themes
<!-- c2d:y5 -->
## Issue Themes
```

| Section | Content |
|---------|---------|
| **Architecture Narrative** | The 3–5 paragraph system description from synthesis step 6 |
| **Architecture Type** | Classification (monolith / microservices / modular monolith / plugin-based / hybrid) plus justification |
| **System-Wide Patterns** | Patterns appearing in 3+ modules, each named with the modules exhibiting it |
| **Cross-Cutting Themes** | Concerns spanning modules (error handling, auth, real-time transport). Seeds `Cross-Cutting/` in full mode |
| **Issue Themes** | System-wide issue patterns from synthesis step 7 (e.g. "no error-handling strategy across 4 modules") |

The five `<!-- c2d:yN -->` markers are the addressable interface, each appearing exactly once and alone on its own line, for the same reason as the module reports — synthesis prose quotes section names too. Address by marker, never by heading text, and match anchored as `^<!-- c2d:y[1-5] -->$` (see [The anchored marker pattern](#the-anchored-marker-pattern)). Rewrite this file in full on every generate or update run — it is cheap and always cross-module.

**One-line module purposes deliberately live in `module_index`, not here.** They are needed by module-doc writers, by the Onboarding agents, and by digest's module inventory — keeping the single copy in the state file means none of those has to open `synthesis.md`, and an update never has to read the previous synthesis back in order to preserve the purposes of modules it did not touch.

---

## State File

`_state/analysis.json` — written at the end of Phase 1. It holds **metadata only**: the analysis prose lives in the artifacts above. Schema:

```json
{
  "schema_version": 2,
  "project": "string — project name or root directory basename",
  "modules": ["list of module names as strings"],
  "module_index": {
    "Module Name": {
      "slug": "module-name",
      "purpose": "one sentence — what this module is for",
      "roots": ["relative/path/to/module/"],
      "entry_points": ["relative/path/to/module/index.ts"],
      "language": "typescript",
      "complexity": "low | medium | high",
      "loc": 2400,
      "report": "_state/modules/module-name.md",
      "doc": "Modules/Module Name.md",
      "analyzed_at": "ISO 8601",
      "source_commit": "abc123 or null"
    }
  },
  "dependency_graph": {
    "Module Name": ["Dependency Module A", "Dependency Module B"]
  },
  "architecture_type": "modular monolith",
  "system_patterns": ["Repository", "Event Bus"],
  "files_analyzed": {
    "relative/path/to/file.ts": "module-slug",
    "relative/path/to/shared-util.ts": ["module-a", "module-b"]
  },
  "git_commit": "abc123 or null if not a git repo",
  "timestamp": "ISO 8601",
  "mode": "quick | full",
  "issues": [
    {
      "id": "unique-slug",
      "module": "Module Name",
      "type": "limitation | bug-risk | improvement",
      "severity": "low | medium | high",
      "file": "relative/path/to/file.ts",
      "lines": "start-end or null",
      "summary": "one-line description",
      "status": "open | resolved"
    }
  ],
  "sessions": [
    {
      "type": "generate | update",
      "timestamp": "ISO 8601",
      "git_commit_start": "abc123 or null",
      "git_commit_end": "def456",
      "mode": "quick | full",
      "modules_affected": ["Module A", "Module B"],
      "issues_resolved": ["issue-slug-1"],
      "issues_introduced": ["issue-slug-2"]
    }
  ]
}
```

### State File Fields

**Core fields** — written on every generate or update run:
- `schema_version`, `modules`, `module_index`, `dependency_graph`, `files_analyzed`, `git_commit`, `timestamp`, `mode` — snapshot of the codebase as of this run

**`schema_version`** — currently `2`. Its absence marks a v1 state file (see "Schema Migration" below).

**`module_index`** — the module map, keyed by module name. This is the field that makes an incremental update a lookup instead of a re-survey: it persists each module's **root paths**, which `code-to-docs:code-to-docs-update` needs to decide which module a changed file belongs to and whether a path lies outside every module.

`module_index` is **authoritative for module boundaries**. Never re-derive roots by re-surveying the codebase when it is present — a re-survey can draw a boundary differently, rename a module, and silently invalidate every `[[wikilink]]` pointing at the old name.

The `report` and `doc` fields are vault-relative paths, so any agent can be handed a pointer without the orchestrator reconstructing it. `analyzed_at` / `source_commit` are **per module**, refreshed only when that module is re-analyzed — so an update can distinguish a freshly analyzed module from one carried forward, and the carry-forward is auditable.

**`architecture_type` and `system_patterns`** — the classification and the pattern names produced by synthesis. They are stored here, rather than only in `_state/synthesis.md`, so an update can tell whether the system-wide picture moved **without reading the previous synthesis back**. `code-to-docs:code-to-docs-update` gates regeneration of `Architecture/System Overview.md` on them; omitting them would let that document drift out of sync with the synthesis it projects.

**`files_analyzed`** — maps each analyzed file to its **owning module slug**. This is file ownership, not change detection: `git diff` is the sole source of truth for what changed (see `analysis-guide.md` Token Efficiency Rules). Earlier revisions of this schema stored a content hash here; nothing read it, and it drifted to a placeholder in practice.

**A file may have more than one owner**, in which case the value is an array of slugs. This follows directly from roots being shareable: when `src/lib/server/` holds several logical modules, a utility there can genuinely belong to two of them, and both Pass 1 agents will list it in their report's `files:`. Recording only one owner would mean the *other* module never gets re-analyzed when that file changes — a silent staleness bug with no symptom until its documentation is quietly wrong. The state writer must therefore **merge** owners rather than overwrite, and report every shared file it found so the module boundaries can be reviewed.

### Resolving a Changed File to Its Module

`files_analyzed` is exact and unambiguous, so it is always tried first. `roots` is the fallback for files that did not exist at the last analysis, and it can be ambiguous — resolve in this order:

| Order | Condition | Resolution |
|-------|-----------|------------|
| 1 | `files_analyzed[path]` exists | That slug — or **every** slug, if the value is an array (a shared file affects all its owners). Exact, O(1), the common case |
| 2 | Exactly **one** module has a root that prefixes the path | That module — a new file added to it |
| 3 | **Several** modules share a root that prefixes the path | Ambiguous. Re-analyze every module sharing that root, and prefer **full** mode so module identification re-runs scoped to that directory — a genuinely new module may be hiding there |
| 4 | No root prefixes the path | Outside every module — potential new module, triggers **full** mode |

Case 3 is not an edge case: in a flat layout, `Docker Engine`, `Database`, and `Auth and Security` can all list `src/lib/server/` as a root, so a new file there cannot be attributed by path alone. Re-analyzing the modules that share the directory is the safe over-approximation, consistent with the rule that when in doubt you choose full.

**Issues array** — tracks codebase health across runs:
- On generate: all issues start with `status: "open"`
- On update: resolved issues change to `status: "resolved"`, new issues added as `"open"`, unchanged module issues carried forward

**Sessions array** — audit trail of the documentation lifecycle. Only the **generate** and **update** skills append entries; the **digest** skill is read-only and never writes to this array (or any file):
- `type: "generate"` — baseline quick or full run
- `type: "update"` — incremental update via `code-to-docs:code-to-docs-update`
- `git_commit_start` — the stored commit from the previous state (null on first generate)
- `git_commit_end` — HEAD at the time of this session
- `modules_affected` — which modules were analyzed (all for generate, subset for update)
- `issues_resolved` / `issues_introduced` — what changed in the health picture

The sessions array provides continuity across generate and update runs. `code-to-docs:code-to-docs-digest` **reads** it (to report how stale the docs are and what changed recently) but never writes it — so there is no `digest` session type.

This is the **incremental contract**, and `analysis.json` is its index: the state file records *where* things are and *what* is known about them, while the analysis prose lives in `_state/modules/` and `_state/synthesis.md`. The `code-to-docs:code-to-docs-update` skill reads this state, maps changed files to modules via `files_analyzed` and `module_index`, runs `git diff` against the stored commit, and re-analyzes only changed modules — carrying the rest forward by leaving their reports untouched on disk. The `code-to-docs:code-to-docs-digest` skill reads it to provide session-start context. The baseline skill writes all three artifacts on every run — do not skip any of them.

### State File Validation

Before reading `analysis.json` in update or digest mode, validate the following required fields exist and have the expected types. If validation fails, report the specific error and fall back to a full generate run (for update) or abort with an error message (for digest).

| Field | Type | Required |
|-------|------|----------|
| `modules` | array of strings | yes |
| `dependency_graph` | object (string → array of strings) | yes |
| `files_analyzed` | object (string → string, or string → array of strings for a shared file) | yes |
| `git_commit` | string or null | yes |
| `timestamp` | string (ISO 8601) | yes |
| `mode` | string (`"quick"` or `"full"`) | yes |
| `issues` | array of objects | yes (may be empty) |
| `sessions` | array of objects | yes (may be empty) |
| `architecture_type` | string | v2 only |
| `system_patterns` | array of strings | v2 only (may be empty) |
| `schema_version` | number | v2 only — absence means v1, which is valid and migrates |
| `module_index` | object (module name → object) | v2 only — absence means v1, which is valid and migrates |

Each issue object must have: `id` (string), `module` (string), `type` (string), `severity` (string), `status` (string). Missing or malformed issues should be logged and skipped rather than causing a full abort.

Each `module_index` entry must have `slug` (string), `purpose` (string), `roots` (non-empty array of strings), and `report` (string). A `module_index` key that is not in `modules`, or a `modules` entry with no `module_index` key, is a validation failure — the two must agree. Two modules sharing a root is **valid** (see "Resolving a Changed File to Its Module"), but two modules sharing a `slug` is not.

**A missing `schema_version` or `module_index` is not a validation error.** It identifies a v1 state file, which is handled by migration, not rejection. Only the eight core fields above are mandatory for a state file to be usable.

### Schema Migration (v1 → v2)

A v1 state file predates the analysis artifacts. It is detected by **`schema_version` absent or `module_index` absent**, and it has three specific gaps: no module roots, no `_state/modules/` reports, and `files_analyzed` values that are content hashes or the placeholder string `"analyzed"` rather than module slugs.

Migrate rather than falling back to a full generate — the point of this schema is to *avoid* forced regeneration:

1. **Derive `module_index`.** A v1 `files_analyzed` has no module attribution, so recover it from each module doc: its `canonical-source` frontmatter names the module's primary file, and its `Dependencies` / API content names the rest. Set `roots` to the narrowest directories covering those files — several modules legitimately sharing one directory is fine. Take each module's `purpose` from the opening sentence of its doc's `### What Is This?`. Survey the codebase only if attribution is genuinely undecidable. Rewrite `files_analyzed` values to module slugs.

2. **Backfill missing reports with Pass 1 (Haiku) only.** This is the cheapest tier, and far cheaper than the v1 behaviour of reading generated prose docs into orchestrator context.

3. **Append section 7 to each backfilled report with a second Haiku agent.** The Pass 1 prompt deliberately forbids writing §7, so something must add it or every backfilled report stops at §6 — which fails the seven-heading check in `analysis-guide.md` synthesis step 1 and leaves the module looking damaged to the next update. This agent does **not** analyse anything; it reformats issue records that v1 already persisted:

   > Read the `issues` array entries whose `module` is `[MODULE_NAME]`. Append a `### Limitations & Improvements` section to `_state/modules/[MODULE_SLUG].md` with one entry per issue, giving its type, severity, file, line range, and summary. Do not evaluate the code, do not add issues, and do not read source files. If there are no issues for this module, write "None recorded in the previous run's state."

   Note the resulting §7 carries **no before/after code snippets** — v1 state stored only issue records, not the prose. A migrated module's `Health/` entries will therefore be thinner than a freshly analysed one's until that module is next re-analysed. Say so rather than letting it look like the module is clean.

4. **Write `_state/synthesis.md`** from the existing `Architecture/System Overview.md`, and populate `architecture_type` and `system_patterns` in state from it. If the System Overview is missing, leave `system_patterns` empty — an empty stored list makes `patterns_changed` true on the next run, which regenerates the System Overview. That is the correct fallback: it fails toward a rewrite, not toward silent staleness.

5. **Tell the user**, e.g. `"v1 state detected — backfilling module index and 8 reports (one-time, Haiku). Health detail for these modules is limited to what the previous state recorded until they are next re-analysed."`

Then continue the run normally against v2. Write `schema_version: 2` on the way out.

**Note:** `_state/` is internal to the skill. If the vault is committed to git, add `_state/` to `.gitignore` to avoid leaking commit refs and analysis internals from the analyzed codebase.
