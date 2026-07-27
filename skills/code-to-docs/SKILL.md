---
name: code-to-docs
description: Use when generating documentation from a codebase, creating architecture docs, building an Obsidian vault from code, or when someone asks to document or explain a project's structure
---

## Overview

Analyze a codebase and produce an Obsidian-native documentation vault containing architecture diagrams, API references, and teaching-focused explanations written at three audience levels: beginner (language constructs explained), intermediate (patterns and integration), and advanced (failure modes, concurrency, edge cases). Output is ready to open directly in Obsidian with working wikilinks, Mermaid diagrams, and Dataview queries.

### Related Skills

| Skill | Purpose |
|-------|---------|
| `code-to-docs:code-to-docs-update` | Incremental update — re-analyze only modules with changes since last run |
| `code-to-docs:code-to-docs-digest` | Load existing vault context into the conversation (read-only) |
| `code-to-docs:code-to-docs-hooks` | Install/remove automation hooks for the generate-digest-update lifecycle |

## Invocation

```
Skill(skill: "code-to-docs:code-to-docs", args: "<path> [--mode quick|full] [--output <path>]")
```

- `<path>` — codebase root (required)
- `--mode` — `quick` (default) or `full`
- `--output` — vault output path (default: `./docs-vault/` relative to codebase)

**Quick mode:** Architecture overview, module inventory, API reference, codebase health assessment, index pages — all at three audience levels. (Both modes produce all three levels; `full` adds whole directories, not depth per module. See `../code-to-docs-references/obsidian-templates.md` §2.)

**Full mode:** Everything in quick, plus design patterns, onboarding guides, cross-cutting concerns, tutorial walkthroughs.

---

## Model Tiers

This skill uses three model tiers to balance cost and quality. Select tier based on the task's cognitive demand.

| Tier | Model | Use For |
|------|-------|---------|
| **Extract** | Haiku | Code extraction, mechanical generation, data transforms, verification |
| **Write** | Sonnet | Narrative writing, pedagogical content, health report assembly |
| **Reason** | Opus | Issue identification, cross-module synthesis, architectural judgment |

**Conditional escalation:** Use Opus for cross-module synthesis only when the codebase has 5+ modules or the dependency graph contains cycles or bidirectional dependencies. For simpler codebases (1-4 modules, tree-shaped dependencies), Sonnet handles synthesis adequately.

**Conditional escalation for issues:** Use Opus for Limitations & Improvements analysis when a module's complexity is rated High, when the module exceeds 1000 LOC, when it involves concurrency or shared mutable state, or when its primary language is a shell language. Use Sonnet for Low/Medium complexity modules. The Pass 1 extraction agent reports the judgment conditions as an `escalate` flag in its receipt, but **do not take that flag at face value**: recompute `escalate OR loc > 1000 OR complexity == "high" OR language ∈ {bash, sh, zsh, shell, powershell}` from the receipt's own fields. The three objective conditions are already in the receipt, and on live runs a Haiku agent returned `loc: 1682` with `escalate: false`, and rated a shell module that splices paths into interpolated program text `escalate: false, complexity: low`. Only the subjective concurrency judgment needs trusting — and only to *add* escalation.

---

## Pass Pointers, Not Payloads

**An agent prompt carries paths and small structured data — never the text of a file that exists on disk.** The orchestrator runs at Opus, so a pasted payload is charged twice: once as Opus output tokens retyping it, and again in the receiving agent's context.

Two conventions make this work, and they apply to every phase:

- **Agents write artifacts and return receipts.** An agent that produces a document writes it to its destination and returns a short structured summary — never the document itself, which would land in the orchestrator's context whether needed there or not.
- **Phase 1 leaves durable artifacts to point at:** `_state/modules/<slug>.md` (one seven-section report per module) and `_state/synthesis.md` (cross-module facts in five fixed sections). Phase 2 agents read these by path, addressing sections by their `<!-- c2d:sN -->` / `<!-- c2d:yN -->` markers — never by heading text, since report prose quotes heading names.

See `../code-to-docs-references/output-structure.md` "The Reference-Passing Rule" for the reference table and "Analysis Artifacts" for the file formats.

---

## Execution

### Phase 1: Intake & Analysis

Read `../code-to-docs-references/analysis-guide.md` for detailed instructions.

1. Survey the codebase — entry points, config files, directory structure
2. Identify independent modules, recording each one's name, slug, and root paths — these become durable wikilink and lookup identities in `module_index`. Roots are a **list** and may be shared between modules; file-level ownership in `files_analyzed` is what distinguishes them
3. Dispatch parallel analysis agents (MUST parallelize if 3+ modules):
   - **Haiku agents** extract sections 1-6 (architecture, API, patterns, dependencies, complexity, key files), **write them to `_state/modules/<slug>.md`**, and return a receipt (report path, purpose, roots, complexity, LOC, `file_count`, deps, `escalate` flag — **not** the file list, which goes in the report's `files:` frontmatter)
   - **Sonnet or Opus agents** then produce section 7 (limitations & improvements). Each is given the **path** to its module's report, reads it itself, **appends** section 7 to that same file, and returns structured issue records. Tier comes from `escalate_final` = `escalate OR loc > 1000 OR complexity == "high" OR language ∈ {bash, sh, zsh, shell, powershell}`, recomputed from the receipt — never the raw flag alone.
4. Synthesize from the receipts (not the reports) into a dependency graph and architecture narrative — **Sonnet agent** for ≤4 tree-shaped modules, **Opus agent** for 5+ modules or complex dependency graphs — and write `_state/synthesis.md` plus a receipt carrying `architecture_type` and `system_patterns`
5. Write `_state/analysis.json` from the receipts (Haiku agent — mechanical data transform)

### Phase 2: Documentation Generation

Read `../code-to-docs-references/obsidian-templates.md` for formatting rules. Read `../code-to-docs-references/output-structure.md` for vault layout and the authoritative Phase 2 dispatch table, whose Input column specifies **what to pass by reference** for each output.

**Before dispatching:** Check if `obsidian` CLI is available (`which obsidian`). If yes, use `obsidian create` with `silent` flag for note creation. If no, use direct file writes. See `../code-to-docs-references/output-structure.md` "Obsidian CLI Integration" for details.

Dispatch in parallel where possible:

1. **Sonnet agent**: `Architecture/System Overview.md` — reads `_state/synthesis.md` §§ Architecture Narrative, Architecture Type, System-Wide Patterns
2. **Haiku agents** (parallel): `Architecture/System Map.canvas`, `Architecture/Dependency Map.md`, `Health/Health Summary.md` (severity charts), `Documentation.base`, `Index.md` — mechanical transforms over the dependency graph, `module_index`, and issue counts, all compact enough to pass inline
3. **Sonnet agents** (parallel, one per module): `Modules/{Name}.md` — each is given the **path** to its module's `_state/modules/<slug>.md` plus the `module_index` name→purpose pairs (inline, one line each) for wikilink context
4. **Sonnet agent**: `Health/Limitations.md` and `Health/Code Review.md` — issue records inline plus the report paths whose § Limitations & Improvements supplies the before/after snippets. `Health/Health Summary.md` is a mechanical chart transform — it is a **Haiku** task in step 2, per the authoritative Phase 2 dispatch table in `output-structure.md`, not a Sonnet task.
5. (Full mode) **Sonnet agents**: `Patterns/`, `Onboarding/`, `Cross-Cutting/` — each reads the `_state/synthesis.md` sections named in the dispatch table, plus report paths for the modules involved

### Phase 3: Verification & Output

#### Phase 3 Dispatch Table

| Agent | Model | Input | Output | Condition |
|-------|-------|-------|--------|-----------|
| Verification | **haiku** | vault file list (generate) / files written + inbound links to deletions (update) | broken links + frontmatter report | always |

1. **Haiku agent**: Verify every `[[wikilink]]` resolves to an existing generated file, verify every file has complete frontmatter. On a baseline generate this is the whole vault; on an update it is scoped per `../code-to-docs-references/analysis-guide.md` "Scoping Verification"
2. Report: file count, module count, mode, broken links (if any)

---

## Red Flags

1. Reading files >500 lines without grep-filtering first
2. Analyzing 3+ independent modules sequentially instead of in parallel
3. Reading `node_modules/`, `vendor/`, `.git/`, or build output
4. Generating PNG/SVG instead of Mermaid inline
5. Skipping wikilink verification in Phase 3
6. Documenting third-party dependencies instead of project code
7. Fabricating design rationale — say "Rationale not documented" instead
8. Fabricating code issues — only report limitations/bugs/improvements that are evidently present in the code
9. Using Opus for extraction or mechanical tasks — Haiku handles these; Opus is reserved for issue analysis on complex modules and cross-module synthesis on large codebases
10. Issue analysis agents re-reading entire modules — they get a report **path** and should only read source files to verify specific concerns
11. Dispatching an agent without setting the `model` parameter to match the dispatch table for that phase
12. Setting a custom `fontFamily` in a Mermaid `%%{init}%%` directive — it clips every diagram label on GitHub's renderer; omit it (see `../code-to-docs-references/obsidian-templates.md` §5)
13. **Pasting into an agent prompt any payload the agent could read from disk** — pass the path and name the section instead
14. **A Pass 1 agent returning its full report** instead of writing `_state/modules/<slug>.md` and returning a receipt
15. **Handing an agent "the full synthesis"** — synthesis lives in `_state/synthesis.md`; pass the path and the sections needed
16. Re-deriving a Pass 2 tier by reading the report's prose instead of recomputing `escalate_final` from the receipt's fields
17. Reading back a file an agent just wrote in order to verify it — completeness is checked by counting `<!-- c2d:sN -->` markers and by the Phase 3 verification agent
18. **Addressing an artifact section by its heading text** instead of its `<!-- c2d:sN -->` marker — report prose quotes heading names, so heading counts give false passes
19. **Matching a marker as a bare substring** instead of anchored to a whole line (`^<!-- c2d:s[1-7] -->$`) — report prose quotes marker strings too, so a loose count over-reports and condemns a healthy report as damaged
20. **Taking a Pass 1 receipt's `escalate` at face value** — recompute `escalate_final` from the receipt's own fields; extraction runs at the cheapest tier and should not be the sole arbiter of arithmetic, nor of whether shell code is security-sensitive
21. **Accepting `deps` entries that are not exact module names** — file paths, directory names, or external commands there become phantom nodes in the dependency graph and broken wikilinks in the Canvas
22. **Analyzing a directory that is itself a generated vault** — check for `_state/analysis.json` or `generated-by: code-to-docs` frontmatter and exclude it, or the skill will document its own output as source
23. **Verifying wikilinks without first stripping code fences and inline code spans** — bash's test syntax is `[[ ... ]]`, and the mandated `> [!warning]` callout style nests fences inside blockquotes, writing them as ```` > ```bash ````, so a fence detector that requires the backticks at the very start of the line never toggles. On a live run this made 21% of all `[[…]]` tokens false positives (see `../code-to-docs-references/analysis-guide.md` "What counts as a wikilink")

---

## Rationalization Traps

| Thought | Reality |
|---------|---------|
| "This codebase is small enough to read sequentially" | If 3+ modules exist, parallelize. The rule is about modules, not LOC. |
| "I'll add frontmatter later" | Generate it with the file. Every file, every time. |
| "The advanced section is the same as intermediate" | You missed edge cases, concurrency, or failure modes. Re-analyze. |
| "This module is too simple for three levels" | Beginner still explains language constructs. Advanced still covers failure modes. Write all three. |
| "I'll just read the whole file, it's not that big" | If it's over 500 lines, grep first. No exceptions. |
| "This code is fine, no issues to report" | Every codebase has limitations. If you found none, you didn't look hard enough — re-examine error handling, concurrency, and abstraction boundaries. |
| "I'll skip the code examples in the review" | Before/after snippets are the core educational value. Always include them for bugs and improvements. |
| "I'll use Opus for everything to be safe" | Opus costs 10-15x more than Haiku. Use the cheapest model that meets the task's cognitive demand. Check the model selection tables. |
| "This module is simple, I'll skip Pass 2" | Every module gets an issue analysis pass. Simple modules get Sonnet; the pass may report "None identified" — that's a valid outcome. |
| "I'll just handle this inline instead of dispatching an agent" | The orchestrator runs at Opus. If the dispatch table says Haiku or Sonnet, dispatch an agent — doing the work inline costs 10-15x more. |
| "A nicer `fontFamily` will make the diagrams look more polished" | It clips every label on GitHub — GitHub measures width in its default font but renders with yours. Never set `fontFamily` in a Mermaid init directive. |
| "It's easier to paste the report than to explain where the file is" | The paste costs two copies of the report, one of them Opus output tokens. The path costs ~20 tokens. |
| "I need to see all the module reports to synthesize" | You have the receipts — names, roots, complexity, deps. Read a report only where the cross-module narrative depends on that module's internals. |
| "I'll have the agent return the report so I can check it before passing it on" | That return lands in your context at Opus, then again in the next prompt. Trust the receipt; Phase 3 verifies. |
| "The report is short, pasting it is harmless" | Multiply by every module and every Phase 2 agent that needs it. The rule is what keeps that multiplication from happening. |
| "I'll re-read the module's Complexity section to decide whether Pass 2 needs Opus" | The receipt carries `escalate`, `loc` and `complexity` — recompute from those three. Never read the prose, and never trust `escalate` alone. |
| "The report has all seven headings, so it's complete" | Count markers. A module documenting this schema quotes the heading names, which on the first live run produced twelve headings and a §7 that existed before Pass 2 ran. |
| "This repo already has a docs vault, that saves me some work" | It is your own output. Analyzing it invents modules out of generated Markdown. Exclude any directory containing `_state/analysis.json`. |
