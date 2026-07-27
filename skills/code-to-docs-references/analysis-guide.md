# Analysis Guide — Codebase Analysis and Parallel Dispatch Reference

This file is loaded during Phase 1 (Intake & Analysis) of the code-to-docs skill. It defines the survey procedure, module identification heuristics, parallel agent dispatch rules, and synthesis steps.

---

## Phase 1: Intake & Analysis

### Step 1: Codebase Survey

Before any deep reading, gather the lay of the land.

1. `ls` the root directory — identify top-level structure
2. `Glob("**/*.{ts,js,py,go,rs,java}")` (adapt extensions to the detected language) — get a file inventory. **If this matches few or no files, the repo may not be conventional application code** — broaden the glob (e.g. add `rb,php,cs,kt,swift,c,cpp,scala,ex`) and, if there is still no code, apply the docs-as-source fallback below.
3. Read `README.md` if it exists — extract stated architecture, entry points, and dependencies
4. Read the primary manifest (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, or a non-code manifest such as `.claude-plugin/marketplace.json`, `action.yml`, or a docs-site config) — extract the dependency list and available scripts
5. Identify entry points: main files, index files, server startup files, CLI entry points

> **Docs-as-source / config-as-source fallback.** Some repos have little or no traditional source — e.g. prompt/skill libraries (`SKILL.md` + Markdown), infrastructure-as-code, GitHub Actions, or documentation sites. When the language globs and standard manifests come up empty, treat the project's primary artifacts as its source: Markdown/YAML/JSON instruction or config files, shell scripts, templates. Modules are then directories of related artifacts (e.g. one skill = one module). The rest of the analysis proceeds unchanged.
>
> **Prose test scenarios still count as tests.** In a docs-as-source repo a `tests/` directory may hold Markdown rather than code — manual scenarios, checklists, fixtures. Those remain **out of scope** under the test-file exclusion: analysis documents the thing being tested, not the tests. Exclude them and say so in the survey output, so a reader can see the choice was made deliberately rather than missed.

**Record the following before proceeding:**

| Field | Notes |
|---|---|
| Primary language(s) | e.g., TypeScript, Python |
| Build system / package manager | e.g., npm, poetry, cargo |
| Entry points | Paths to main/index/server/cli files |
| Top-level directory structure | List of top-level dirs and their apparent purpose |
| Approximate LOC | Rough count from Glob output |

---

### Step 2: Module Identification

A **module** is an independent subsystem that can be understood without reading another module's internals.

**Heuristics for identifying modules:**

- Top-level directories containing related source files (e.g., `src/auth/`, `src/payments/`)
- Packages or namespaces with a distinct, singular responsibility
- Services in a microservice architecture (each service is one module)
- Major class hierarchies with clear external boundaries
- Files grouped by feature rather than by technical layer

**For flat structures** (no obvious subdirectory grouping), identify modules by:

- Import clusters — files that import heavily from each other form a module
- Shared domain concepts — files that operate on the same data types or business entities
- Named prefixes or suffixes in filenames (e.g., all `*-service.ts` files may form one module)

**For each identified module, record:**

| Field | Content |
|---|---|
| Name | Title Case label (e.g., Auth, Payments, Worker Queue). **Write `and`, never `&`** — and likewise avoid smart quotes, en-dashes and non-breaking spaces. The name becomes a filename and the text of every `[[wikilink]]` pointing at it, and agents silently "tidy" an ampersand into `and` when writing links, inconsistently. Normalise here, at identification time, so no later agent has the chance. `Packaging and Release`, not `Packaging & Release` |
| Purpose | One sentence, under 20 words — what the module is for. Becomes the wikilink context every later agent uses |
| Slug | Name lowercased, non-alphanumerics collapsed to single hyphens (`Worker Queue` → `worker-queue`, `Packaging and Release` → `packaging-and-release`) |
| Root paths | **List** of the narrowest directories covering this module's files, relative to repo root |
| Language | Primary language of this module |
| Entry points | Files that are the module's public surface (index, main, exports) |
| Suspected dependencies | Other modules or external packages this module calls |

**Root paths are a list, and they need not be exclusive.** Two shapes are both normal:

- A module spanning several directories — release tooling covering `scripts/` and `.claude-plugin/`.
- Several modules **sharing** one directory — the flat-structure case above, where `src/lib/server/` holds Docker, Database, and Auth as separate logical modules. Each lists `src/lib/server/` as a root, and file-level ownership is what distinguishes them.

That is why `files_analyzed` (path → owning module) is the primary lookup in later updates and `roots` is only the fallback for files that did not exist yet. See `output-structure.md` "Resolving a Changed File to Its Module".

The name and root paths settled here are **durable**: they are written to `module_index` and become the module's wikilink identity and the key that future updates use to map changed files back to it. Renaming a module or redrawing its roots in a later run orphans its `Modules/{Name}.md` and breaks inbound wikilinks, so treat these as decisions rather than labels.

---

### Phase 1 Dispatch Table

Every `Agent()` call in Phase 1 MUST set `model:` to match this table.

**Agents write artifacts and return receipts.** The Output column below names a *file the agent writes*, and the Returns column names the small structured value it hands back to the orchestrator. This is the core cost discipline of Phase 1: a full report returned through the orchestrator's context and then re-pasted into the next agent's prompt costs three copies of the same bytes, two of them at Opus. See `output-structure.md` "The Reference-Passing Rule".

| Agent | Model | Input (by reference) | Output (writes) | Returns | Condition |
|-------|-------|----------------------|-----------------|---------|-----------|
| Extraction (×N) | **haiku** | module details + entry points | `_state/modules/<slug>.md` §§1-6 | extraction receipt | always, parallel if 3+ modules |
| Issue Analysis (×N) | **sonnet** | `_state/modules/<slug>.md` path | appends §7 to that file | issue records | `escalate_final` false |
| Issue Analysis (×N) | **opus** | `_state/modules/<slug>.md` path | appends §7 to that file | issue records | `escalate_final` true |

`escalate_final` is **not** the receipt's raw `escalate` flag — it is `escalate OR loc > 1000 OR complexity == "high" OR language ∈ {bash, sh, zsh, shell, powershell}`, recomputed by the orchestrator. See "Model selection for Pass 2" below for why.
| Synthesis | **sonnet** | extraction receipts + report paths | `_state/synthesis.md` | synthesis receipt | ≤4 modules, tree-shaped deps |
| Synthesis | **opus** | extraction receipts + report paths | `_state/synthesis.md` | synthesis receipt | 5+ modules or cyclic deps |
| State file write | **haiku** | receipts (inline) + report paths for `files:` | `_state/analysis.json` | confirmation | always |

### Step 3: Parallel Agent Dispatch

**Rule: 3 or more independent modules MUST be analyzed in parallel.**

For 1–2 modules, analyze sequentially in the current session.

For 3+ modules, analysis is a two-pass process per module. Both passes dispatch in parallel across modules.

**Either way, the artifacts are the same.** Sequential analysis still writes `_state/modules/<slug>.md` per module and still produces the receipts the later steps consume — the artifact layout is what update and digest depend on, so it is not an optimization that only applies to the parallel path.

---

#### Pass 1: Extraction (Haiku agents)

Dispatch one **Haiku** agent per module. These agents extract structured facts from the code — no judgment about quality or issues.

**The agent writes its report to disk and returns only a receipt.** Do not ask it to return the report text. The report is the Pass 2 agent's input, and Pass 2 reads it from the path in the receipt — so the report never enters the orchestrator's context at all.

**Haiku Agent Prompt Template:**

```
You are extracting structured information from a single module of a codebase. Your job is to read the code and report facts. Do not evaluate code quality or suggest improvements — only extract what is there.

Do not read files outside this module's root paths unless they define types or interfaces this module directly imports. If another module shares one of your root directories, restrict yourself to the files listed below and the ones they import.

## Module Details

- **Name:** [MODULE_NAME]
- **Slug:** [MODULE_SLUG]
- **Root paths:** [MODULE_ROOT_PATHS — one or more directories covering this module]
- **Language:** [LANGUAGE]
- **Entry points:** [COMMA_SEPARATED_ENTRY_POINT_PATHS]
- **Known dependencies on other modules:** [LIST_OR_"none known"]
- **The complete list of module names in this project:** [ALL_MODULE_NAMES]
- **Write your report to:** [VAULT_PATH]/_state/modules/[MODULE_SLUG].md
- **Source commit:** [GIT_COMMIT_OR_"none"]
- **Timestamp to record:** [CURRENT_ISO_8601] — use this verbatim; do not try to determine the current time yourself

## Instructions

Work in this order:

1. List the files under your root paths using Glob. If a root is shared with another module, work only from your own entry points and the files they reach.
2. For any file larger than 500 lines, use Grep to locate the key symbols (exports, class names, function signatures, route definitions) before reading. Never read a file over 500 lines in full without grepping first.
3. Read entry point files in full.
4. Trace the primary execution flow from the entry point — follow the call chain through at most 3 levels of depth.
5. Identify repeated patterns (e.g., middleware chains, repository pattern, event emitter usage, decorators).
6. Map all imports that reference paths outside this module — these are the module's external dependencies.
7. Assess complexity: estimate cyclomatic complexity by counting branching constructs in the core files; note any files with deeply nested logic or functions exceeding 100 lines.

## Step 1 — Write the report file

Write your findings to the report path given above, overwriting it if it exists. The file has this exact frontmatter followed by exactly the six sections below.

**Each section is preceded by an HTML-comment marker (`<!-- c2d:sN -->`). Emit the markers exactly as shown, each alone on its own line** with nothing before or after it — they are matched anchored, as `^<!-- c2d:s[1-7] -->$`. They are how a later agent locates one section without reading the whole file, and they must each appear exactly once in the file.

**If your prose needs to mention one of these section names** — for example when documenting a schema that defines them — write it inline in backticks (`` `### Dependencies` ``), never as a real heading, and never emit a `<!-- c2d:` marker inside prose. A duplicated heading or marker makes the section unaddressable and silently corrupts the report.

---
module: [MODULE_NAME]
slug: [MODULE_SLUG]
purpose: <one sentence, under 20 words — what this module is for>
roots:
  - [one line per root path]
language: [LANGUAGE]
complexity: low | medium | high
loc: <integer — total lines across the files you attributed to this module, excluding tests>
files:
  - <one line per file you attributed to this module, relative to the repo root>
analyzed-at: [CURRENT_ISO_8601]
source-commit: [GIT_COMMIT_OR_"none"]
---

<!-- c2d:s1 -->
### Architecture
Describe the internal structure of this module. What is the top-level design pattern (MVC, service/repository, functional pipeline, actor model, etc.)? How are files organized within the module? Where does control flow enter and exit?

<!-- c2d:s2 -->
### Public API
List every symbol this module exports that is consumed by other modules: function signatures, class names with their public methods, exported types/interfaces, HTTP routes or event names if applicable. Format each entry as a code-fenced signature with a one-line description.

<!-- c2d:s3 -->
### Internal Patterns
Describe patterns used internally that are not visible from outside (e.g., caching strategies, retry logic, internal event bus, singleton instances, factory functions). Note any patterns that deviate from the surrounding codebase conventions.

<!-- c2d:s4 -->
### Dependencies
List all external dependencies in two groups:
1. **Other project modules** — module name and what is imported
2. **Third-party packages** — package name, version if determinable, and what it is used for

Do not list standard library imports.

<!-- c2d:s5 -->
### Complexity
Rate overall complexity: Low / Medium / High.
Provide a one-paragraph justification. Identify the single most complex file or function and explain why.

<!-- c2d:s6 -->
### Key Files
List the 3–7 files most important to understanding this module. For each, provide the path and a one-sentence description of its role.

Do not add a "Limitations & Improvements" section — a later agent appends that.

## Step 2 — Return the receipt

After writing the file, return ONLY this JSON object and nothing else. No preamble, no summary, no excerpt of the report.

{
  "module": "[MODULE_NAME]",
  "slug": "[MODULE_SLUG]",
  "report": "_state/modules/[MODULE_SLUG].md",
  "purpose": "<the same one-sentence purpose you wrote in the frontmatter>",
  "roots": ["[MODULE_ROOT_PATHS]"],
  "entry_points": ["..."],
  "language": "[LANGUAGE]",
  "complexity": "low | medium | high",
  "loc": <integer>,
  "file_count": <integer — how many files you listed in the frontmatter>,
  "deps": ["module names this one depends on — each MUST be copied verbatim from the project module list above"],
  "escalate": <true | false>,
  "escalate_reason": "<short reason, or null if escalate is false>"
}

Do NOT put the file list in the receipt — it belongs in the report frontmatter, where a later agent reads it. The receipt must stay a fixed small size no matter how many files the module has.

`deps` rules — these are strict, because the dependency graph is built directly from this field:
- Every entry MUST be an exact string from the project module list given above. Copy it character for character.
- Do NOT use file paths, directory names, or slugs. `code-to-docs-references/analysis-guide.md` and `code-to-docs` are wrong; the module *name* is right.
- Do NOT list third-party packages or external commands (`git`, `sed`, `jq`) here — those belong in the Dependencies section of the report, not in `deps`.
- Omit yourself. Return `[]` if this module depends on no other project module.

Set `escalate` to true if ANY of the following hold, and name which one in `escalate_reason`:
- you rated complexity High
- the module exceeds 1000 lines of code — compare against the `loc` you just computed
- the module involves concurrency, shared mutable state, async/sync bridging, or security-sensitive logic (auth, crypto, input validation, permissions, writing user config files, shell escaping)

Otherwise set `escalate` to false and `escalate_reason` to null. Keep `escalate_reason` to one short clause.
```

**Why the receipt carries these fields.** Each one removes a downstream read the orchestrator would otherwise have to do:

| Field | What it saves |
|-------|---------------|
| `report` | The Pass 2 prompt is a path, not a pasted report |
| `deps` | The dependency graph builds from receipts alone — no report reads during synthesis |
| `escalate` / `escalate_reason` | Feeds the Pass 2 model tier without the orchestrator reading the report's Complexity and Architecture prose to judge it. The agent that read the code makes the *subjective* call; the orchestrator recomputes the objective ones and ORs them in, so this flag can only add escalation, never withhold it |
| `purpose` | Populates `module_index`, which is the single source for module one-liners — used as wikilink context by module-doc writers and as digest's module inventory, so neither ever opens a report |
| `roots` / `entry_points` / `language` / `complexity` / `loc` | Populate `module_index` directly |
| `file_count` | A sanity check only. The **file list itself lives in the report frontmatter**, not here |

**Why the file list is deliberately not in the receipt.** Every other receipt field is O(1) in the size of the module, so a receipt costs roughly the same whether the module has 4 files or 400. A file list is O(module size), and receipts from every module land in the orchestrator's context at once — on a large repo that is tens of thousands of tokens of file paths at Opus, which is precisely the cost this design exists to avoid. The state-file writer needs the mapping, so it reads the `files:` frontmatter out of each report at Haiku instead.

---

#### Pass 2: Issue Analysis (Sonnet or Opus agents)

After Pass 1 completes, dispatch one agent per module to produce the Limitations & Improvements section. These agents are given **the path to the Pass 1 report** and read it themselves — they do NOT receive it pasted into their prompt, and they do NOT re-read the code files unless they need to verify a specific concern.

The agent **appends** section 7 to the same report file and returns structured issue records. Two things follow from that:

- The report file ends up holding the complete seven-section report, at one known path, ready for Phase 2 and for carry-forward on the next update.
- The returned issue records are exactly the shape `analysis.json.issues` needs, so **the issues array assembles by concatenating Pass 2 returns** — no prose re-parsing, and the state-file writer never needs the synthesis.

**Model selection for Pass 2.** Compute it from the receipt, but do **not** take `escalate` at face value:

```
escalate_final =  receipt.escalate
              OR  receipt.loc > 1000
              OR  receipt.complexity == "high"
              OR  receipt.language ∈ {bash, sh, zsh, shell, powershell}
```

| `escalate_final` | Model |
|------------------|-------|
| true | Opus |
| false | Sonnet |

**Why the recomputation.** Three of the four conditions are objective and are *already in the receipt* — LOC, the complexity rating, and the primary language. Only the middle of `receipt.escalate` (concurrency, shared mutable state, security-sensitive logic) is a judgment that requires having read the code, so that one is taken on trust — but it is taken as a signal that can only *add* escalation, never as permission to skip it.

Recomputing the objective conditions costs nothing and closes two real failures observed on live runs of this pipeline:

- **Arithmetic.** A Haiku agent reported `loc: 1682` and `escalate: false` in the same receipt, which would have sent the largest and densest module in the codebase to Sonnet. A second run reported `loc: 1769 / complexity: low / escalate: false` for the same module. Extraction agents are the cheapest tier by design; do not make them the sole arbiter of arithmetic.
- **Security judgment.** A module consisting of shell scripts that write user configuration files and interpolate paths into `python3 -c` program text — shell escaping and user-config writing, both explicitly named in the escalation criteria above — returned `escalate: false, complexity: low, loc: 298`, routing to Sonnet. Sonnet happened to find the command injection anyway, so this was a latent gap rather than a demonstrated miss, but the routing was wrong on the criteria as written.

**Why primary language is the proxy for the security condition.** The security criterion is the one an extraction agent is least able to apply to its own output: recognising that quoting a variable into an interpolated string is an injection sink is exactly the reasoning the escalation exists to buy, so requiring it *before* escalating is circular. Primary language is the cheapest objective correlate available in the receipt. Shell modules concentrate injection, quoting, word-splitting and `rm -rf` defects that a Sonnet pass finds only opportunistically — in this pipeline's own repository, both shell modules shipped exactly such bugs, and both became security fixes.

This is a deliberate over-approximation and it does cost money: a small shell module that does nothing dangerous still goes to Opus. Accept that. Shell modules are typically few and short, the escalation applies per module rather than per file, and the asymmetry favours it — the downside of an unnecessary Opus pass is a modest bill, while the downside of a missed injection is a vulnerability shipped in a released plugin. Match on the receipt's **primary** `language` field, not on the presence of any `.sh` file in a mixed module, so a repository that merely keeps a build script does not escalate every module that contains one.

Still **do not re-derive the tier by reading the report's prose** — everything needed is in the receipt. If a receipt is missing or malformed, default to Opus and note it.

**Parse receipts leniently.** Agents wrap JSON in ```` ``` ```` fences and sometimes add a line of preamble despite being told not to. Extract the first JSON object or array in the response rather than requiring a bare value, and if a required field is missing, treat that module as needing Opus rather than guessing.

**Issue Analysis Agent Prompt Template:**

```
You are reviewing a module for limitations, bugs, risks, and improvement opportunities. A structured extraction report already exists for this module — read it and use it as your primary source. Only read source files directly if you need to verify a specific concern.

## Module Details

- **Name:** [MODULE_NAME]
- **Root paths:** [MODULE_ROOT_PATHS — one or more directories covering this module]
- **Language:** [LANGUAGE]
- **Extraction report:** [VAULT_PATH]/_state/modules/[MODULE_SLUG].md

## Instructions

1. Read the extraction report at the path above. It contains six sections: Architecture, Public API, Internal Patterns, Dependencies, Complexity, Key Files.
2. Review the Architecture section for design constraints, missing abstraction boundaries, and scalability bottlenecks.
3. Review the Public API section for inconsistent interfaces, missing error types, or unclear contracts.
4. Review the Internal Patterns section for anti-patterns, deviations from conventions, or fragile implementations.
5. Review the Complexity section — if a specific file or function was flagged, read it directly (Grep first if >500 lines) to assess whether the complexity is warranted or indicates a problem.
6. If the report mentions concurrency, async/sync bridging, shared state, or security-sensitive operations, read the relevant code sections to assess race conditions, deadlock potential, and data integrity risks.

Only read source files when verifying a specific concern identified from the report. Do not re-read the entire module, and do not read files outside this module's root paths — a report that cites another module's files, or the project's own test scenarios, has strayed outside its boundary.

## Step 1 — Append your section to the report

Append the following to the END of the extraction report file, preserving everything already in it. Emit the marker line first, then the heading, exactly as shown.

<!-- c2d:s7 -->
### Limitations & Improvements

For each issue, classify as one of:
- **Limitation** — architectural or design constraint that restricts what the module can do (e.g., single-threaded, no retry logic, hard-coded config, missing abstraction boundary)
- **Bug or Risk** — code that is incorrect, fragile, or likely to fail under specific conditions (e.g., unhandled exception path, race condition, missing null check)
- **Improvement Opportunity** — code that works but could be better (e.g., duplicated logic that should be extracted, overly complex function that should be split, missing error context, inconsistent naming)

For each item provide: the file path and line range, a description of the issue, the severity (low/medium/high), and a suggested fix or approach. Where the fix is clear, include a short before/after code snippet — the documentation generated later draws its educational content from this prose, so it must live in the file. Do not fabricate issues — only report what is evidently present in the code. If the module is well-written with no notable issues, state that explicitly.

## Step 2 — Return the issue records

After appending, return ONLY a JSON array of the issues you recorded, and nothing else. No preamble, no restatement of the prose.

[
  {
    "id": "short-kebab-case-slug, unique within this module",
    "type": "limitation | bug-risk | improvement",
    "severity": "low | medium | high",
    "file": "relative/path/to/file.ts",
    "lines": "start-end, or null if not localised",
    "summary": "one-line description"
  }
]

Return an empty array [] if you found no issues. The prose you appended in Step 1 is the full record — the array is an index into it, so keep each summary to one line.
```

---

### Step 4: Synthesis

After all Pass 1 and Pass 2 agents return, each module's complete seven-section report is sitting at `_state/modules/<slug>.md`, and the orchestrator holds only receipts. Synthesis works from the receipts, reading a report **only** where the cross-module story genuinely depends on that module's internals.

**Model selection for synthesis:**

| Condition | Approach |
|-----------|----------|
| ≤4 modules with tree-shaped dependencies (no cycles, no bidirectional) | Dispatch a **Sonnet agent** — narrative writing at the tier that matches it |
| 5+ modules | Dispatch an **Opus agent** — it receives the receipts plus the report paths |
| Any number of modules with cycles or bidirectional dependencies | Dispatch an **Opus agent** — complex dependency reasoning needed |

Either way, **dispatch an agent — do not synthesize inline.** The orchestrator runs at Opus, so writing the narrative in the current session bills Sonnet-level work at Opus rates; that is the same mistake the dispatch tables exist to prevent. Dispatching is cheap here precisely because the inputs are receipts and paths, not documents.

Pass the receipt list inline (they are small) and the report **paths**. Never paste report contents into the synthesis prompt.

**Synthesis steps:**

1. **Verify report completeness** — for each module, confirm the report file exists and contains each of the seven `<!-- c2d:sN -->` markers **exactly once**, matched anchored: `grep -cE '^<!-- c2d:s[1-7] -->$' <report>` must return `7`. Grep for the markers, not the headings, and anchor the pattern rather than matching the bare `<!-- c2d:s` substring: report prose legitimately quotes both heading names and marker strings, so counting headings gives false passes and a loose marker count gives false *failures*. Do not read the files in full. Flag any missing or duplicated marker before proceeding.
2. **Build the cross-module dependency graph** — from the `deps` field of each receipt. Identify cycles or bidirectional dependencies. No report reads are needed for this step.
3. **Identify system-wide patterns** — patterns that appear in 3+ modules are architectural conventions worth documenting at the top level. Read the `c2d:s3` section of each report rather than the whole file: from the anchored `^<!-- c2d:s3 -->$` line to the next anchored marker line.
4. **Resolve naming consistency** — standardize module names if agents used different labels for the same module. Whatever names are settled on here become the wikilink identities for the whole vault and are recorded in `module_index`.
5. **Determine architecture type** — classify the system as one of: monolith, microservices, modular monolith, plugin-based, or hybrid. Justify the classification.
6. **Generate the top-level architecture narrative** — a 3–5 paragraph description of the system that a new engineer could read to understand how the pieces fit together.
7. **Aggregate limitations and improvements** — from the Pass 2 issue records (already in hand), deduplicate, identify system-wide themes (e.g., "no error handling strategy across 4 modules"), and rank by severity. This feeds the Health/ directory in Phase 2.

**Write `_state/synthesis.md`** — record the results of steps 3, 5, 6, and 7 in the five-section format defined in `output-structure.md` "Analysis Artifacts". This file is what Phase 2's narrative agents read; it exists so no agent is ever handed "the full synthesis" as a payload. Write it in full on every run. Per-module one-liners are **not** written here — they live in `module_index`.

**Return a synthesis receipt** carrying the two facts the state file needs:

```json
{
  "architecture_type": "modular monolith",
  "system_patterns": ["Repository", "Event Bus"]
}
```

These are stored in `analysis.json` so a later update can detect that the system-wide picture moved **without reading the previous `_state/synthesis.md` back**. Skipping them leaves `code-to-docs:code-to-docs-update` unable to tell whether `Architecture/System Overview.md` needs regenerating, and it will silently go stale.

**Write `_state/analysis.json`** — dispatch a **Haiku agent** for this mechanical data transform. Its input is the **receipts plus the report paths**, not the synthesis: the Pass 1 receipts supply `module_index`, the reports' `files:` frontmatter supplies `files_analyzed`, and the Pass 2 issue records supply `issues`. Give the agent the receipt list inline and instruct it to read each report's frontmatter for the file list — that keeps the file paths out of the orchestrator entirely. Have it populate **every** field of the state schema defined in `output-structure.md` "State File" — including `project`, `issues`, and `sessions`. The `issues` and `sessions` arrays are **required** (use `[]` only when genuinely empty); a state file missing them fails `output-structure.md` "State File Validation", which breaks the next update and the next digest (aborts). Shape:

```json
{
  "schema_version": 2,
  "project": "project name or root basename",
  "modules": ["list of module names"],
  "module_index": {
    "Module Name": {
      "slug": "module-name",
      "purpose": "one sentence — what this module is for",
      "roots": ["relative/path/"],
      "entry_points": ["relative/path/index.ts"],
      "language": "typescript",
      "complexity": "medium",
      "loc": 850,
      "report": "_state/modules/module-name.md",
      "doc": "Modules/Module Name.md",
      "analyzed_at": "ISO 8601",
      "source_commit": "HEAD commit hash or null"
    }
  },
  "dependency_graph": {
    "Module Name": ["Dependency Module A", "Dependency Module B"]
  },
  "architecture_type": "modular monolith",
  "system_patterns": ["Repository", "Event Bus"],
  "files_analyzed": {
    "relative/path/to/file.ts": "module-slug"
  },
  "git_commit": "HEAD commit hash or null if not a git repo",
  "timestamp": "ISO 8601",
  "mode": "quick or full",
  "issues": [],
  "sessions": []
}
```

Field-by-field, this is a direct transform of receipt data — no judgment, which is why it is a Haiku task:

| State field | Source |
|-------------|--------|
| `module_index` entries | Pass 1 receipt `purpose` / `roots` / `entry_points` / `language` / `complexity` / `loc`, plus the settled module name from synthesis step 4 |
| `files_analyzed` | The `files:` frontmatter of each report (read at Haiku), each path mapped to that report's `slug`. **Merge, never overwrite** — a path listed by two reports gets an array of both slugs |
| `dependency_graph` | Pass 1 receipt `deps` |
| `issues` | Pass 2 issue records, each with the module name added and `status: "open"` |
| `architecture_type`, `system_patterns` | The synthesis receipt |

None of `purpose`, `architecture_type` or `system_patterns` is optional: they are what the `purposes_changed` and `patterns_changed` gates compare, what supplies wikilink context to module-doc writers, and what digest reads for its module inventory. A state file missing them leaves the next update unable to tell whether `Architecture/System Overview.md` needs regenerating, so it goes stale silently.

Cross-check each report's `file_count` receipt field against the number of `files:` entries it actually read, and report any mismatch rather than silently writing a partial `files_analyzed` — an incomplete ownership map degrades the next update into re-surveying.

**A path claimed by two reports is expected, not an error.** Modules may share a root, so a utility can genuinely belong to two of them. Merge the owners into an array and **list every shared file in the run summary** — both because it affects change attribution (a change to a shared file re-analyses all its owners) and because a long shared list is a signal that the module boundaries were drawn too finely. Overwriting instead of merging would leave the losing module never re-analysed when a file it owns changes: silent, symptomless staleness.

On a baseline generate run, populate `issues` from the Pass 2 records (each with `status: "open"`) and `sessions` with one `"generate"` entry — do not ship the arrays empty if issues were found. See `output-structure.md` for the full schema description and incremental contract details.

---

## Agent Output Schema

All seven sections are required per module, and all seven live in **one file** at `_state/modules/<slug>.md`. Sections 1-6 are written there by the Haiku extraction agent; section 7 is appended there by the Sonnet/Opus issue analysis agent. There is no separate "combine" step — the file *is* the combined report, and its `###` headings are fixed so downstream agents can grep a single section.

| Section | Source | Model | Content |
|---|---|---|---|
| **Architecture** | Pass 1 | Haiku | Internal design pattern, file organization, control flow entry and exit points |
| **Public API** | Pass 1 | Haiku | All exported symbols consumed externally: function signatures, class public methods, exported types, HTTP routes or event names |
| **Internal Patterns** | Pass 1 | Haiku | Implementation patterns not visible from outside: caching, retry logic, internal buses, factories, singletons |
| **Dependencies** | Pass 1 | Haiku | Two groups: (1) other project modules with specific imports, (2) third-party packages with version and purpose |
| **Complexity** | Pass 1 | Haiku | Rating (Low/Medium/High) with one-paragraph justification and identification of the single most complex file or function |
| **Key Files** | Pass 1 | Haiku | 3–7 files most important to understanding the module, each with path and one-sentence role description |
| **Limitations & Improvements** | Pass 2 | Sonnet or Opus | Classified issues (limitation/bug-risk/improvement) with file path, severity, and suggested fix. "None identified" if the module is clean. |

---

## Exclusions

The following paths and file types are NEVER analyzed during Phase 1. Do not Glob into them, do not Read them as source, do not pass them to agents **as material to analyse**.

This is a rule about what counts as *source*. It does not restrict the pipeline's own artifacts: `_state/modules/<slug>.md` paths are passed to Pass 2 agents by design, the state writer reads report frontmatter, and the update flow loads `_state/analysis.json`. Those are the skill's working files, not the analysed codebase.

**Directories:**

- `node_modules/`
- `vendor/`
- `.git/`
- `__pycache__/`
- `dist/`
- `build/`
- `.next/`
- `target/`
- `.cache/`
- `.turbo/`
- `coverage/`
- `.nyc_output/`
- **Any directory that is itself a generated code-to-docs vault.** Detect it by the presence of `_state/analysis.json`, or by a directory of `.md` files whose frontmatter carries `generated-by: code-to-docs`. The default output path `docs-vault/` is the common case, but the vault may be anywhere, including nested under `examples/`. This matters more than it looks: running the skill on a repo that already has a vault will otherwise glob that vault's generated Markdown as source and invent "modules" out of your own output. It bit this project's own repo on the first live run, which contains both `docs-vault/` and `examples/*/docs-vault/`.

**File types:**

- `*.min.js` — minified JavaScript
- `*.map` — source maps
- Lock files: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Pipfile.lock`, `poetry.lock`, `Cargo.lock`, `go.sum`
- Binary files: `*.png`, `*.jpg`, `*.gif`, `*.svg`, `*.ico`, `*.woff`, `*.woff2`, `*.ttf`, `*.eot`, `*.pdf`, `*.zip`, `*.tar`, `*.gz`
- Test files: `*.test.ts`, `*.spec.ts`, `*.test.js`, `*.spec.js`, `*_test.go`, `test_*.py`, `*_test.py` — analysis focuses on production code; test files are out of scope

---

## Token Efficiency Rules

These rules apply to all agents and to the orchestrating session.

1. **Grep before Read** — never read a file larger than 500 lines without first using Grep to locate the specific symbols or sections needed. Reading a large file in full when only 20 lines are relevant wastes context and slows synthesis.

2. **One extraction agent per module** — do not spawn multiple Haiku agents for a single module. The issue analysis agent (Pass 2) is a separate, second agent for the same module — this is the intended two-pass design, not a violation.

3. **Suppress verbose output** — agents must not quote large blocks of source code in their reports. Reports describe and summarize; they include code-fenced signatures only in the Public API section, and only the signature line (not the full implementation).

4. **Skip dependency internals** — document only the project's own code. Do not trace into `node_modules`, `vendor`, or any third-party package source. External packages are recorded by name, version, and purpose only.

5. **Use the cheapest sufficient model** — Haiku for extraction and mechanical tasks, Sonnet for writing and standard issue analysis, Opus only when escalation conditions are met (see Step 3 and Step 4 model selection tables). Do not use Opus "just to be safe" — it costs 10-15x more than Haiku per token.

6. **Pass 2 agents receive a report path, not code and not a pasted report** — issue analysis agents are given `_state/modules/<slug>.md` and read it themselves. Only read source files to verify a specific concern. This avoids both re-reading the entire module at a higher-cost tier and paying for the report twice in the orchestrator's context.

7. **Parallel generation in Phase 2** — module docs, mechanical files (Canvas, Index, Dependency Map, state file), and health reports are independent outputs. Dispatch them in parallel to keep each agent's context small and focused.

8. **Update mode: only re-analyze changed modules** — unchanged modules keep their existing reports **on disk, unread**. Carrying a module forward is a no-op, not a read. Do not re-run analysis on a module just because it was loaded into context. The `git diff` output is the sole source of truth for what changed.

9. **Pass pointers, not payloads** — an agent prompt carries paths and small structured data (receipts, the dependency graph, issue records), never the text of a file that exists on disk. Inline context in an agent prompt is capped at roughly 500 tokens; above that, pass a path and name the section to read. The orchestrator runs at Opus, so a pasted payload is charged twice: once as Opus output tokens retyping it, and again in the receiving agent's context. See `output-structure.md` "The Reference-Passing Rule".

10. **Agents write artifacts and return receipts** — an agent that produces a document writes it to its destination and returns a short structured summary. Never ask an agent to return a full report or document as its result, because the return value lands in the orchestrator's context whether it is needed there or not.

11. **Do not read to verify** — resist reading back a file an agent just wrote to check it. Artifact completeness is verified by grepping for the required headings (synthesis step 1) and by the Phase 3 Haiku verification agent, not by the orchestrator reading content.

---

## Incremental Update Flow

This section applies when invoked via `code-to-docs:code-to-docs-update`. For baseline generation (`code-to-docs`), follow Steps 1-4 above.

**The governing idea:** an update should touch only what changed. A module that did not change is carried forward by *leaving its report file alone* — not by reading it, not by re-summarizing it, and never by re-deriving its boundaries. If a step below seems to require knowing something about an unchanged module, that something is already in `analysis.json`.

### Update Step 1: Load and Validate Previous State

1. Read `_state/analysis.json` from the existing vault at `--output` path
2. If the file does not exist, abort update and fall back to a full generate run. Inform the user: "No previous state found — running full generation instead."
3. Validate the state file against the schema in `output-structure.md` "State File Validation" section. If required fields are missing or have wrong types, report the validation error and fall back to a full generate run.
4. **Check the schema version.** If `schema_version` or `module_index` is absent, this is a v1 state file — run the one-time migration in `output-structure.md` "Schema Migration (v1 → v2)" before continuing, and report it to the user. Do **not** fall back to a full generate; the migration backfills with Haiku only.
5. Extract: `git_commit` (the commit hash from the last run), `modules`, `module_index`, `dependency_graph`, `files_analyzed`, `issues`

Load **only** the state file in this step. Do not read `_state/synthesis.md` or any `Modules/*.md` at any point in the update flow — nothing in it needs their contents in the orchestrator's context.

The one permitted touch of a report is a **frontmatter grep** in Step 3 for `source-commit`, to detect a torn previous run. That reads one line per module, never a section body.

### Update Step 2: Diff

**Before diffing, confirm the stored commit is usable:**

- If `git_commit` is `null` (the baseline was generated on a non-git codebase), fall back to a full generate run — there is no commit to diff against. Inform the user: "Previous run had no git commit — running full generation instead."
- If `git_commit` is non-null but not reachable in the current repo — verify with `git cat-file -e "<git_commit>^{commit}"` — it was likely rebased, squashed, garbage-collected, or the clone is shallow. Fall back to a full generate run. Inform the user: "Stored commit `<hash>` is unreachable — running full generation instead."

Only once the stored commit is confirmed reachable:

1. Run `git diff <stored_git_commit>..HEAD --name-only` in the codebase root to get the changed file paths
2. Filter out excluded paths (see Exclusions section)
3. Capture the **content diff** for the changed files that fall within a known module's root — the roots come from `module_index[*].roots`, so this is scoped without any survey: `git diff <stored_git_commit>..HEAD -- <those paths>`. Step 4 needs the added lines to detect new cross-module imports; gathering it here (once) avoids a second diff pass
4. The result is the list of **changed files** (with content for module-root files) since the last documentation run

If the diff is empty (no changes since last run), report "No changes since last documentation run" and exit without modifying the vault.

### Update Step 3: Map Changes to Modules

This is a **lookup, not a survey.** `files_analyzed` maps every previously analyzed path to its owning module slug, and `module_index` records every module's root paths. Both come from the state file loaded in Step 1.

Resolve each changed file using the four-case order in `output-structure.md` "Resolving a Changed File to Its Module": exact `files_analyzed` hit, then a *unique* root prefix match, then an *ambiguous* match where modules share a root, then no match at all. A `files_analyzed` value may be an **array** — a shared file marks all of its owners affected.

**Never re-derive module roots by re-surveying the codebase.** `module_index` is authoritative for boundaries. A re-survey may draw a boundary differently and rename a module, which silently invalidates every `[[wikilink]]` pointing at the old name and orphans its `Modules/{Name}.md`.

Classify the changes:

| Category | Detection | Implication |
|----------|-----------|-------------|
| **Modified within existing module** | Case 1 — `files_analyzed[path]` hit | Re-analyze that module |
| **New file in one existing module's directory** | Case 2 — exactly one module's root prefixes the path | Re-analyze that module |
| **New file in a directory shared by several modules** | Case 3 — more than one module's root prefixes the path | Re-analyze every module sharing that root, and prefer full mode — a new module may be hiding there |
| **New file outside all modules** | Case 4 — no root prefixes the path | Potential new module — triggers full mode |
| **Deleted file** | Path in `files_analyzed` no longer exists on disk | Re-analyze the owning module |
| **New top-level directory with source files** | New directory at project root matching no root | New module — triggers full mode |

Build the list of **affected modules** — modules that need re-analysis. Every other module in `modules` is **carried forward**: its report stays at `module_index[name].report` untouched, and its `analyzed_at` / `source_commit` are preserved unchanged.

### Update Step 4: Auto-Select Mode

Decide **before** re-analysis, using only signals available now: the changed-file list (Step 2), the `files_analyzed` map, and the content diff of module-root files (Step 2.3). Do **not** defer this to the Step 6 dependency-graph comparison — that only exists after re-analysis, which the mode choice gates.

| Condition | How to detect it now | Mode |
|-----------|----------------------|------|
| All changes within existing modules, no new/deleted modules | every changed path resolves via Step 3 rule 1 or 2 | **Quick** |
| New module detected | a changed/added path hits Step 3 **case 4** — no root prefixes it | **Full** |
| Module deleted | every file of a module is gone from disk | **Full** |
| Dependency structure changed | the Step 2.3 content diff has **added** (`+`) import/require lines in one module's files that resolve into a different module's `module_index` root | **Full** |
| >50% of tracked files changed | `|changed ∩ files_analyzed keys| / |files_analyzed| > 0.5`, computed globally | **Full** |

Detecting "new cross-module imports" scans only the added (`+`) lines of the Step 2.3 content diff for import/require/include statements whose target resolves into a *different* module's root than the file's own. This is a heuristic — it can over-trigger on comments or strings that look like imports. When in doubt, choose **Full**; it is the safe over-approximation.

Report the auto-selected mode to the user: "Update mode: quick (2 of 8 modules affected)" or "Update mode: full (new module detected: Scheduler)".

### Update Step 5: Re-Analyze Affected Modules

For each affected module, run the same two-pass analysis as baseline, writing to the **same report path** the module already has in `module_index`:

1. **Haiku extraction** (sections 1-6) — same agent prompt template as Step 3 Pass 1. It **overwrites** `_state/modules/<slug>.md`, refreshing `analyzed-at` and `source-commit`.
2. **Sonnet/Opus issue analysis** (section 7) — same agent prompt template as Step 3 Pass 2, tier chosen by recomputing **`escalate_final`** from the fresh Pass 1 receipt exactly as in Step 3 ("Model selection for Pass 2"). Do **not** branch on the raw `escalate` flag: an update runs the same two-pass analysis as a baseline, so it inherits the same failure — a receipt reporting `loc: 1769 / complexity: low / escalate: false` would send the largest module in the codebase to Sonnet. It **appends** section 7 to the overwritten file.

For **unchanged modules**, carrying forward is a no-op: their report files already sit at known paths with correct frontmatter, and their `module_index` entries are reused verbatim. Do not read them, do not re-summarize them, and do not re-analyze them.

If auto-selected mode is **full**, also run Step 2 (Module Identification) — scoped to the paths that hit Step 3 **case 4** (outside every known root), not the whole codebase — to identify any new modules, then analyze those as well. Existing module boundaries stay as `module_index` defines them.

**Case 4 is the one that yields new modules; case 3 does not.** Case 3 paths lie inside a directory that existing modules already share, so they are handled by re-analysing those modules. Scoping identification to case 3 instead of case 4 means a genuinely new top-level directory triggers full mode and is then excluded from the very step meant to identify it — the new module is never found, on that run or any later one, because the next update sees no new change.

### Update Step 6: Merge Synthesis

Synthesis in update mode works from the same inputs as baseline — receipts and paths — with the carried-forward modules represented by their existing `module_index` entries rather than fresh receipts.

Assemble the synthesis input as:

- **Affected modules** — the fresh Pass 1 receipts from Step 5
- **Carried-forward modules** — their `module_index` entries (name, slug, purpose, roots, complexity, loc, report path) plus their `dependency_graph` edges, all already loaded from state in Step 1
- **Report paths** for every module, affected or not, so the synthesis agent can read one if the narrative genuinely needs its internals

This is the step where the old flow leaked the most: there is no need to read an unchanged module's report, its generated doc, **or the previous `_state/synthesis.md`** to include it in the system story. Its name, purpose, dependencies, and complexity are all in `module_index`, which Step 1 already loaded.

Run the same synthesis procedure as Step 4, but with awareness of what changed:

1. Rebuild dependency graph — fresh `deps` from the Step 5 receipts, carried-forward edges from the state's `dependency_graph`
2. Compare new dependency graph to previous — flag any structural changes
3. Regenerate the architecture narrative and **rewrite `_state/synthesis.md` in full** — from receipts and `module_index`, never by reading the previous synthesis back
4. Merge issues:
   - Issues in re-analyzed modules that the new analysis still reports: keep/replace with the new details, status `open`
   - Issues in unchanged modules: carry forward with status `open`
   - Issues in a **deleted** module: mark `resolved`. Deletion is the one case where the evidence rule below is satisfied by removal rather than by a diff touching the lines — the code the issue points at is gone. Do this here, in the merge, not later: Step 8 writes whatever this step produces
   - Issues from a previous run that the new analysis no longer reports: mark `resolved` **only if** the changed files (Step 2) actually touched the issue's recorded `file` (and, when line ranges are recorded, overlap its `lines`). If the code the issue points at was **not** touched, the omission is almost certainly Pass 2 non-determinism, not a fix — keep the issue `open`. When unsure, keep it `open`. Marking `resolved` requires positive evidence that the referenced code changed.

### Update Step 7: Selective Generation

Use the same Phase 2 generation flow and the same dispatch table in `output-structure.md`, including its reference-based Input column — but selectively.

**First compute the change signals** from Step 6's merge. They are cheap comparisons over data already in hand, and they gate the cross-module outputs.

**A gate must cover every input its output actually consumes.** Look up the output's row in the `output-structure.md` Phase 2 dispatch table, and make sure a signal covers each thing listed in its Input column. A gate that omits one input does not merely regenerate less — it lets the output silently drift out of sync with the thing it projects.

| Signal | True when |
|--------|-----------|
| `modules_changed` | A module was added or removed |
| `graph_changed` | The rebuilt `dependency_graph` differs from the stored one, or `modules_changed` |
| `purposes_changed` | A module was added or removed, **or** a re-analysed module's `purpose` differs from the stored one in substance — not merely in wording |
| `patterns_changed` | The synthesized `system_patterns` list differs from the stored one, or the synthesized `architecture_type` differs from the stored one |
| `issues_changed` | The merged `issues` array differs from the stored one in any element (added, removed, changed `status`/`severity`), **or** any re-analyzed module has at least one issue — because Pass 2 rewrites its §7 prose, which the Health writers read |

`system_patterns` and `architecture_type` are stored in `analysis.json` for exactly this reason: without them, detecting a pattern change would require reading the previous `_state/synthesis.md`, which the update flow forbids.

**Compare `purpose` and `system_patterns` by meaning, not by bytes.** Both are LLM-generated prose, so a re-analysed module will almost always produce a differently-worded sentence describing the same thing. A byte comparison is therefore true on nearly every update, which silently defeats the gate and returns you to regenerating everything — the same non-determinism trap that the Step 6 issue-merge rule guards against when it refuses to mark an issue `resolved` just because a re-analysis didn't mention it. Treat a reworded purpose or a renamed-but-equivalent pattern as **unchanged**; require a real difference — a module now described as doing something else, a pattern added or dropped from the list. When genuinely unsure, treat it as changed and regenerate.

| Output | When to regenerate | Inputs the gate must cover |
|--------|-------------------|----------------------------|
| `Architecture/System Overview.md` | If `graph_changed` **or** `purposes_changed` **or** `patterns_changed` | narrative, architecture type, system-wide patterns, dependency graph |
| `Architecture/Dependency Map.md` | If `graph_changed` | dependency graph, module list |
| `Architecture/System Map.canvas` | If `graph_changed` | dependency graph, module list |
| `Modules/{Name}.md` for affected modules | Always | that module's report |
| `Modules/{Name}.md` for modules in the **relink** set | Always — from their existing reports (see "the relink set") | that module's unchanged report |
| `Modules/{Name}.md` for all other unchanged modules | **Never** — preserve existing | — |
| `Health/Health Summary.md` | If `issues_changed` | issue counts |
| `Health/Limitations.md`, `Health/Code Review.md` | If `issues_changed` | issue records **and** §7 prose |
| `Documentation.base` | If `modules_changed` **or** `purposes_changed` | `module_index` |
| `Patterns/` (full mode) | If auto-selected full | system-wide patterns, report paths |
| `Onboarding/` (full mode) | If auto-selected full | full synthesis, `module_index` |
| `Cross-Cutting/` (full mode) | If auto-selected full | cross-cutting themes, report paths |
| `Index.md` | Always (Haiku template fill; keeps the timestamp honest) | project, timestamp, mode |
| `_state/synthesis.md` | Always (written in Step 6) | — |
| `_state/modules/<slug>.md` for affected modules | Always (written in Step 5) | — |
| `_state/modules/<slug>.md` for unchanged modules | **Never** — leave untouched, including frontmatter | — |
| `_state/analysis.json` | Always (must reflect new state) | — |

**Why gate rather than always regenerate.** These outputs are *projections* of the graph, the purposes, the patterns, and the issue set. If none of those moved, regenerating produces near-identical prose at Sonnet cost and churns the vault's diff for no reader benefit. The common update — a bug fix inside one module that changes no imports and shifts no patterns — correctly skips Dependency Map, Canvas, and System Overview.

**Why `patterns_changed` exists.** System-wide patterns are derived from the module reports, so re-analyzing a single module can change them with the graph and purposes both untouched. Gating System Overview on structure alone would let it drift: `synthesis.md` § System-Wide Patterns gets rewritten while the reader-facing document that projects it does not. Any gate you add later must be checked the same way — against the output's full Input column, not against intuition about what "usually" changes it.

When any gating comparison is ambiguous — a malformed stored value, a signal you are not sure covers every input — **regenerate**. A redundant Sonnet call costs far less than a stale architecture doc that nothing will ever correct.

Report what was skipped and why: `"Regenerated 3 files; skipped System Overview, Dependency Map, System Map (dependency graph and module purposes unchanged)."` A silent skip is indistinguishable from a bug.

**Deletions.** When a module is removed (detected in Step 3, which forces full mode), clean up every artifact that referred to it:

1. Delete `Modules/{Name}.md` and `_state/modules/<slug>.md`
2. Remove its entry from `modules`, `module_index`, and `dependency_graph` — including edges *pointing at* it from other modules' dependency lists
3. Drop its files from `files_analyzed`
4. **Regenerate the doc of every module that referenced it** — see "the relink set" below
5. Note the removed title so Step 9 sweeps for any remaining inbound `[[wikilinks]]`

Its issues were already marked `resolved` during the Step 6 merge — that belongs with the rest of the issue merging, not here.

Skipping step 1 leaves an orphan report that every future update dutifully carries forward as a module that no longer exists. Note that removing a module makes `modules_changed` and `graph_changed` true, so `Documentation.base`, the Dependency Map, and the Canvas all correctly regenerate without it.

#### The relink set — modules whose docs reference something removed

A deleted module does not only leave its own artifacts behind. Every module that depended on it has, in its **own** doc:

- a `dependencies:` frontmatter entry `"[[Deleted Module]]"`
- `[[Deleted Module]]` wikilinks in its prose

Those modules are **not affected for analysis** — their code did not change, so re-running Pass 1 and Pass 2 on them would be waste. But the "preserve unchanged module docs" rule cannot apply to them either: preserved, their links dangle permanently. Verification would report the breakage once, and on every later run scoped verification has no deletion to sweep for, so the broken links become invisible.

So distinguish two kinds of affected:

| Set | Meaning | Cost |
|-----|---------|------|
| **affected** | Code changed (or its report is damaged) → re-run Pass 1 + Pass 2, then regenerate its doc | Full two-pass |
| **relink** | Analysis unchanged, but the doc references a module that was removed or renamed → regenerate the doc **from its existing, untouched report** | One Sonnet doc write, no analysis |

Build the relink set from the `dependency_graph` edges you removed in step 2: any module that had an edge pointing at a deleted module. Add any module whose doc contains a `[[wikilink]]` to a removed title, found with the **exact** Step 9 sweep pattern — `!?\[\[<removed title>([#|][^\]]*)?\]\]`, covering aliased, section, block-reference and embed forms, not just the bare `[[Title]]` (see "[The removed-title sweep pattern](#the-removed-title-sweep-pattern)"). If this step uses a narrower pattern than Step 9, Step 9 finds dangling links that Step 7 was never given the chance to repair. A module in both sets is simply **affected** — the fuller treatment wins.

This is the one case where an unchanged module's doc is legitimately regenerated. State it in the run summary so it does not look like a violation of the preserve rule: `"Regenerated 2 docs to drop links to the removed Scheduler module (analysis unchanged, reports reused)."`

The same logic applies to a **rename**, if one ever happens — which is why `module_index` treats names as durable. A rename is a delete plus an add, and every inbound link needs the same repair.

### Update Step 8: Update State File

**Re-check the concurrency guard (final check).** Re-read `_state/analysis.json` and compare its `git_commit` and `timestamp` to the values loaded in Step 1. If either changed, another update ran while this one was in progress (for example a hook-triggered update racing a manual one) — abort without writing and tell the user to re-run, rather than clobber the other run's merged `issues` and `sessions` history.

This is the **second** check; the first happens before Step 5 writes any report (see "Concurrency Across the Whole Run" below). Checking only here would let a losing run overwrite reports it then never records in state.

Then write `_state/analysis.json` with:
- `schema_version` → `2`
- `git_commit` → current HEAD
- `timestamp` → now
- `mode` → the auto-selected mode
- `modules` → merged module list (may include new modules in full mode)
- `module_index` → merged map: **replaced** entries for re-analyzed modules (fresh `complexity`, `loc`, `analyzed_at`, `source_commit` from their new receipts), **verbatim** entries for carried-forward modules — their `analyzed_at` and `source_commit` must keep the older values, since that is what makes the carry-forward auditable
- `files_analyzed` → merged map (re-analyzed modules' file lists replaced from their receipts, carried forward for unchanged; drop entries for deleted files)
- `issues` → merged array with status updates
- `sessions` → append new session entry (see `output-structure.md` for schema)

A carried-forward module whose `analyzed_at` silently advances to now is a bug: it claims the module was analyzed at this commit when it was not, and the next update loses the ability to tell how stale that report is.

### Update Step 9: Verify

Dispatch a **Haiku** agent to check wikilinks and frontmatter, scoped as described in "Scoping Verification" below.

---

## Concurrency Across the Whole Run

Once analysis reports became durable files, the state file stopped being the only thing a concurrent run can corrupt. Reports are written in Step 5 but state is written in Step 8, so a guard that only fires at Step 8 leaves a window: two updates both re-analyze module M, both overwrite `_state/modules/m.md`, and the loser aborts at Step 8 — leaving **the loser's report beside the winner's state**. The vault then claims module M was analyzed at the winner's commit while its report describes a different one.

Guard the whole run, not just the write:

1. **Claim (Step 1), by writing.** Create `_state/.lock` containing this run's start timestamp and the `git_commit` it loaded. Create it with an **exclusive create** that fails if the file already exists (`set -C; > _state/.lock` in shell, or `open(..., 'x')`) — the failure *is* the signal. If it already exists, another run is in flight: report its contents and abort before doing anything. Record the loaded `git_commit`/`timestamp` as the claim token too.
2. **Re-check before writing anything (before Step 5).** Confirm `_state/.lock` still contains your own claim, and re-read `_state/analysis.json` to confirm `git_commit` and `timestamp` still match the token. Either mismatch means another run interfered — abort **before** dispatching any analysis agent, so no report is written and nothing is corrupted. This is the cheap place to lose a race.
3. **Re-check before writing state (Step 8).** As described above.
4. **Release the lock** on success *and* on every abort path, including the Step 2 empty-diff exit. A lock left behind blocks all future updates, so treat removal as mandatory cleanup rather than a final step that might be skipped.

**A read-only claim cannot detect an in-flight run — only a finished one.** If the claim were merely the values read at Step 1, two runs starting within the same window would both read identical values, both pass the pre-Step-5 check, and both write reports; the loser would then abort at Step 8 having already overwritten the winner's artifacts. That is precisely the corruption this section exists to prevent, so the claim must leave a mark other runs can see.

**If a stale lock blocks a legitimate run** — a previous run was killed — the recovery is to confirm no update is running, delete `_state/.lock`, and re-run. The torn-report detection below will repair whatever the killed run left half-written.

**Detecting a torn or damaged carry-forward.** A report's `source-commit` frontmatter is the repair signal. During Step 3, for every module the state says is unchanged, check its report at `module_index[name].report`:

| What you find | Meaning | Action |
|---------------|---------|--------|
| `source-commit` matches the module's stored `source_commit` | Healthy | Carry forward |
| `source-commit` disagrees | A previous run was interrupted between Step 5 and Step 8 | Mark **affected**, re-analyze |
| The file is **missing**, empty, or has no frontmatter | A crashed write, a manual deletion, or a partial checkout | Mark **affected**, re-analyze |
| An **anchored** `<!-- c2d:sN -->` marker is missing or appears more than once — `grep -cE '^<!-- c2d:s[1-7] -->$'` ≠ 7 | An interrupted Pass 2, a Pass 1 that never got its §7, or a report whose prose collided with the format | Mark **affected**, re-analyze |

All four checks are frontmatter and marker greps — one line per module, no section bodies. **Anchor the marker grep** (`^<!-- c2d:s[1-7] -->$`, never a bare `<!-- c2d:s` substring): a report that documents the marker scheme mentions markers in its prose, and a loose count over-reports, condemning a healthy report as damaged and re-analyzing the module for nothing. See `output-structure.md` "The anchored marker pattern". Carrying forward a report that is absent or inconsistent is worse than re-analyzing it: nothing downstream would detect the dead path, and the vault would keep claiming an analysis it does not have.

---

## Scoping Verification

Verification checks two things: every `[[wikilink]]` resolves to an existing file, and every file has complete frontmatter. On a baseline generate run, that means the whole vault — every file is new.

### What counts as a wikilink — exclude code before matching

**A `[[…]]` token inside a code fence or an inline code span is not a link.** Obsidian does not resolve it, and neither may verification. Before matching, strip:

1. **Fenced blocks** — ```` ``` ```` and `~~~` — **after removing any leading blockquote prefix (`> `)**. This is not an edge case: `obsidian-templates.md` §7 *mandates* Code Review Notes as `> [!warning]` callouts, so their fences are written as ```` > ```bash ````, and in any vault documenting shell code every code block is a fence nested inside a blockquote. A fence detector that requires the backticks at the very start of the line never toggles on these, and the whole block is treated as prose.
2. **Inline code spans**, including multi-backtick spans (`` `x` ``, ``` ``x`` ``` ). Docs about this pipeline quote link syntax constantly.

Then match links as `(?<!!)\[\[([^\]|#]+)` and resolve the captured title.

**Why this is load-bearing.** Bash's test syntax is `[[ ... ]]` — identical to a wikilink. On a live run of this pipeline against its own repository, a vault of 132 wikilink-shaped tokens contained **18** bash conditionals in blockquoted fences and **10** inline-code quotations: 21% of all tokens, none of them links, every one of them resolving to nothing. A verifier that skipped this step would have reported 28 broken links against a vault whose 104 real links all resolved — and the natural response to a 28-link failure is to "fix" documents that were correct.

The failure is asymmetric and favours precision here: a false positive triggers edits to good files, while the real breakage this check exists to catch — a renamed or deleted target — still surfaces, because those links live in prose, not in code blocks.

**Do not "solve" this by asking writers to avoid `[[` in code.** The code being documented is not the vault's to change, and a doc that cannot quote `[[ -z "$REPO" ]]` cannot document a shell script.

On an **update**, a full-vault sweep re-reads files that provably cannot have changed. Only two sets can newly break:

| Set | Why it can break | How to collect it |
|-----|------------------|-------------------|
| Files written this run | New or rewritten content can contain a bad link or malformed frontmatter | The generation step already knows exactly which files it wrote — including the relinked docs |
| Files linking to a **removed** title | An unchanged file's link breaks when its target is deleted or renamed | Only when a module was deleted or renamed: sweep the vault with the pattern below |

<a id="the-removed-title-sweep-pattern"></a>
**The sweep pattern must cover every wikilink form, not just the bare one:**

```
!?\[\[<removed title>([#|][^\]]*)?\]\]
```

A bare `grep '\[\[<removed title>\]\]'` misses four forms Obsidian treats as links to the same note, and each one dangles just as badly:

| Form | Example |
|------|---------|
| Aliased | `[[Scheduler\|the scheduler]]` |
| Section | `[[Scheduler#Public API]]` |
| Block reference | `[[Scheduler#^a1b2c3]]` |
| Embed | `![[Scheduler]]` |

The aliased form is the one that matters most in practice: prose links are written aliased far more often than bare, precisely because a raw title rarely reads well mid-sentence. A sweep that misses it reports **clean** on a vault whose most natural-sounding links are all broken.

Match the title itself literally — escape regex metacharacters in it — and match it case-insensitively only if the vault's filesystem is case-insensitive, as macOS's default is. The same pattern is what Step 7 uses to build the relink set, so the two must stay identical: a link form the sweep can find but the relink set cannot is a guaranteed dangling link, reported and never repaired.

On a deletion the second sweep should come back **clean**, because Step 7 regenerated the relink set specifically to drop those links. A hit here means a dangling link survived — report it as a failure of the relink step, not just as a broken link.

If no file was deleted or renamed, the second set is empty and verification covers only what was written. Report the scope in the summary — "verified 4 files written this run; no deletions, so no inbound-link sweep needed" — so a narrow check is never mistaken for a full one.

**Do not narrow further than this.** In particular, do not skip verification because "the agent that wrote the file was careful" — the whole point is that generation is non-deterministic. And when in doubt about whether a rename occurred, run the full sweep; it is Haiku and a missed broken link is worse than a redundant read.
