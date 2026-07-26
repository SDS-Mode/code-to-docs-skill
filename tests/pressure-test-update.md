# Pressure Test: Incremental Update Discipline

## Objective

Verify that `code-to-docs:code-to-docs-update` touches **only what changed**. The design intent is that an unchanged module costs nothing: its analysis report already sits on disk at a path recorded in `module_index`, so carrying it forward is a no-op rather than a read.

This test therefore checks *absences* as much as outputs — what the skill did **not** read, and what it did **not** re-derive. Those are the properties the cost of an update actually depends on.

Two scenarios:

- **Scenario A** — a normal v2 incremental run
- **Scenario B** — a v1 vault migrating in place

---

## Scenario A: v2 Incremental Run

### Setup

1. Pick a codebase with **5+ modules** and generate a baseline:
   ```
   /code-to-docs:code-to-docs <path> --output /tmp/upd-vault
   ```
2. Record the baseline for later comparison:
   ```bash
   cd /tmp/upd-vault
   cp _state/analysis.json /tmp/baseline-state.json
   md5sum Modules/*.md _state/modules/*.md | sort > /tmp/baseline-hashes.txt
   ```
3. In the codebase, make a change confined to **exactly one module** — edit a function body in one file. Do **not** add imports, do not add files, do not touch other modules.
4. Commit it. The stored `git_commit` must remain reachable.
5. Run the update:
   ```
   /code-to-docs:code-to-docs-update <path> --output /tmp/upd-vault
   ```

### Checkpoint A.1 — No Re-Survey

The single largest hidden cost in the pre-artifact design was re-deriving module roots. It must not happen.

- [ ] The transcript shows **no** `Glob` over the whole codebase (e.g. `**/*.ts`)
- [ ] The transcript shows **no** read of `README.md` or the package manifest
- [ ] The transcript shows **no** module-identification reasoning ("identifying modules…", listing top-level directories)
- [ ] Module-to-file mapping is done by lookup against `files_analyzed` / `module_index`
- [ ] Any `files_analyzed` value that is an **array** (a file owned by two modules sharing a root) marks **all** its owners affected when that file changes — not just the first
- [ ] Module names in the new state are **identical** to the baseline — no renames, no re-slugging:
      `diff <(jq -S '.modules' /tmp/baseline-state.json) <(jq -S '.modules' _state/analysis.json)`

### Checkpoint A.2 — Only the Affected Module Is Read

- [ ] Exactly **one** module is reported as affected, and it is the one that changed
- [ ] The transcript shows source-file reads **only** under the affected module's root
- [ ] **No** `_state/modules/<slug>.md` is read for an unaffected module
- [ ] **No** `Modules/{Name}.md` is read for an unaffected module
- [ ] The orchestrator does not read the affected module's own report either — Pass 2 reads it via the path in its prompt

### Checkpoint A.3 — Unchanged Artifacts Are Byte-Identical

```bash
cd /tmp/upd-vault && md5sum Modules/*.md _state/modules/*.md | sort > /tmp/after-hashes.txt
diff /tmp/baseline-hashes.txt /tmp/after-hashes.txt
```

- [ ] Only the affected module's `Modules/{Name}.md` and `_state/modules/<slug>.md` differ
- [ ] Every other module doc is byte-identical (not merely equivalent — regenerating identical-looking prose is still a cost)
- [ ] Every other module report is byte-identical, **including its frontmatter**

### Checkpoint A.4 — Staleness Tracking Survives

```bash
jq -r '.module_index | to_entries[] | "\(.key)\t\(.value.analyzed_at)\t\(.value.source_commit)"' _state/analysis.json
```

- [ ] The affected module's `analyzed_at` and `source_commit` advanced to this run / new HEAD
- [ ] Every unaffected module's `analyzed_at` and `source_commit` are **unchanged** from the baseline
- [ ] Top-level `git_commit` equals the new HEAD
- [ ] `schema_version` is still `2`

A carried-forward module whose `analyzed_at` silently advances is a failure: it claims analysis that did not happen and destroys the ability to tell how stale that report is.

### Checkpoint A.5 — Cross-Module Outputs Are Gated, and Use References

The scenario change is a function-body edit: no new imports, no new files. So `graph_changed` and `purposes_changed` are both false, and the architecture projections should be **skipped**.

- [ ] `Architecture/Dependency Map.md` and `System Map.canvas` were **not** regenerated (dependency graph unchanged) and are byte-identical
- [ ] `Architecture/System Overview.md` was **not** regenerated (graph, purposes, **and patterns** all unchanged) and is byte-identical
- [ ] Cross-check the patterns gate: `jq -r '.system_patterns[]' _state/analysis.json` is unchanged from the baseline. If it moved, System Overview **must** have regenerated — a skip here would be the unsound-gate failure
- [ ] The skip was **reported**, naming the unchanged signal — e.g. `"skipped System Overview, Dependency Map, System Map (dependency graph and module purposes unchanged)"`
- [ ] `Health/` regenerated **iff** the merged issue set changed **or** the re-analyzed module has any issues (its §7 prose was rewritten)
- [ ] `Documentation.base` was **not** regenerated (module set and purposes unchanged)
- [ ] `Index.md` regenerated (Haiku template fill, keeps the timestamp honest)

For whatever *did* regenerate, references still apply:

- [ ] The System Overview agent's prompt (if dispatched) names `_state/synthesis.md` sections — it does **not** contain the narrative text or any module report
- [ ] Dependency Map and Canvas agents (if dispatched) receive the graph inline and are **Haiku**
- [ ] Health writers receive issue records inline plus report **paths** for the modules they cover
- [ ] `_state/synthesis.md` was rewritten **without reading the previous one** — unchanged modules' purposes come from `module_index`, which Step 1 already loaded

Now force the other branch: add an import from one module to another, commit, re-run.

- [ ] `graph_changed` is true, so Dependency Map, Canvas, and System Overview **all** regenerate
- [ ] Mode auto-selects **full** (new cross-module import — a dependency-structure change)

### Checkpoint A.6 — Issue Carry-Forward

- [ ] Issues in unaffected modules are still present with `status: "open"`
- [ ] An issue in the affected module whose file/lines the diff did **not** touch is still `open`
- [ ] An issue is marked `resolved` only if the diff touched its recorded `file` (and overlapped `lines` when recorded)
- [ ] A new `sessions` entry of type `update` was appended, with `modules_affected` listing exactly the one module

### Checkpoint A.7 — Mode Selection

- [ ] Mode auto-selected **quick** (change confined to one existing module, no new imports)
- [ ] The mode was decided *before* re-analysis, from the diff and state — not after
- [ ] The selection was reported to the user, e.g. `"Update mode: quick (1 of 6 modules affected)"`

### Checkpoint A.8 — Empty Diff Short-Circuit

Re-run the update immediately, with no further changes:

- [ ] Reports "No changes since last documentation run"
- [ ] Writes **nothing** — `analysis.json` `timestamp` is unchanged, no session entry appended
- [ ] Dispatches zero analysis agents

### Checkpoint A.9 — Verification Is Scoped

- [ ] Verification covers the files written this run, not the whole vault
- [ ] With no deletions or renames, **no** inbound-link sweep was performed
- [ ] The reported scope is explicit — e.g. `"verified 4 files written this run; no deletions, so no inbound-link sweep needed"`
- [ ] Frontmatter and wikilinks in the files that *were* written are still fully checked

### Checkpoint A.10 — Concurrency Guard Covers the Whole Run

- [ ] The claim (`git_commit` + `timestamp`) is recorded at Step 1
- [ ] It is re-checked **before Step 5 writes any report**, not only at Step 8
- [ ] Simulate a race: after the update starts but before it writes reports, modify `_state/analysis.json`'s `timestamp` externally. The run must abort **before** any `_state/modules/*.md` is written — check their mtimes are unchanged
- [ ] Simulate a torn run: hand-edit one module's report `source-commit` to disagree with state, then run update. That module is treated as **affected** and re-analyzed rather than carried forward
- [ ] Simulate a damaged carry-forward three ways — **delete** an unchanged module's report, **truncate** one so it loses its `<!-- c2d:s7 -->` marker, and **blank** one's frontmatter. Each must be detected and re-analyzed, not silently carried forward

### Checkpoint A.11 — Deleted Module Cleanup

Delete an entire module from the codebase, commit, and run update.

- [ ] Mode auto-selects **full**
- [ ] `Modules/{Name}.md` and `_state/modules/<slug>.md` are both **removed**
- [ ] The module is gone from `modules`, `module_index`, and `files_analyzed`
- [ ] Edges **pointing at** it are removed from other modules' `dependency_graph` lists
- [ ] Its issues are marked `resolved` **by the Step 6 merge**, not as an afterthought in Step 7 (deletion is positive evidence the code is gone)
- [ ] `Documentation.base` regenerated — the module set changed, so it must no longer list the deleted module

**The relink set** — this is the part that is easy to get wrong, because it is the one legitimate exception to "never regenerate an unchanged module's doc":

- [ ] Every module that depended on the deleted one had its `Modules/{Name}.md` **regenerated**, dropping the dangling `[[wikilink]]` from both its `dependencies:` frontmatter and its prose
- [ ] Those modules were **not** re-analyzed — no Pass 1 or Pass 2 agent ran for them, and their `_state/modules/<slug>.md` and `analyzed_at` are untouched
- [ ] The run summary distinguishes them from genuinely affected modules, e.g. `"Regenerated 2 docs to drop links to the removed Scheduler module (analysis unchanged, reports reused)."`
- [ ] `grep -r '\[\[Deleted Module\]\]' <vault>` returns **nothing** — the Step 9 sweep should come back clean because Step 7 already fixed the links. A hit is a relink-step failure, not merely a broken link
- [ ] Re-run update with no further changes: verification reports no broken links (i.e. the breakage was actually repaired, not just reported once and forgotten)
- [ ] Verification swept for inbound `[[wikilinks]]` to the removed title, and any that existed were reported

---

## Scenario B: v1 Vault Migration

### Setup

Build a v1 state file — no `schema_version`, no `module_index`, and `files_analyzed` values that are placeholders rather than slugs:

```bash
cp -r /tmp/upd-vault /tmp/v1-vault
cd /tmp/v1-vault
rm -rf _state/modules _state/synthesis.md
jq 'del(.schema_version) | del(.module_index)
    | .files_analyzed = (.files_analyzed | map_values("analyzed"))' \
   _state/analysis.json > tmp.json && mv tmp.json _state/analysis.json
```

Make a one-module change in the codebase, commit, then run:
```
/code-to-docs:code-to-docs-update <path> --output /tmp/v1-vault
```

### Checkpoint B.1 — Migrates Instead of Regenerating

- [ ] The skill detects v1 (absent `schema_version` / `module_index`) and says so, e.g. `"v1 state detected — backfilling module index and N reports (one-time, Haiku)."`
- [ ] It does **not** fall back to a full generate run
- [ ] It does **not** abort with a validation error — absent `schema_version` / `module_index` is not a validation failure

### Checkpoint B.2 — Backfill Is Haiku-Only

This is what makes migration cheaper than regeneration, so it is the checkpoint that matters most.

- [ ] Backfill agents are **all Haiku** — zero Sonnet or Opus agents dispatched for backfill, including the one that appends §7
- [ ] Section 7 for modules not being re-analyzed is recovered from the existing `issues` array, **not** by dispatching Pass 2
- [ ] The module that actually changed still gets a normal two-pass re-analysis (Pass 2 at the tier its receipt's `escalate` flag indicates)

### Checkpoint B.3 — Migration Output Is Valid v2

- [ ] `_state/modules/<slug>.md` now exists for **every** module, each with all seven `<!-- c2d:sN -->` markers exactly once — including `s7`, appended by the second Haiku agent from the v1 `issues` array
- [ ] `architecture_type` and `system_patterns` are populated in state (or `system_patterns` is empty, which must force a System Overview regeneration on the next run)
- [ ] The user was told that migrated modules' Health detail is limited until they are next re-analyzed
- [ ] `_state/synthesis.md` exists with all five `<!-- c2d:yN -->` markers
- [ ] `schema_version` is `2` and `module_index` has one entry per module with an existing `report` path
- [ ] Every `files_analyzed` value is now a slug present in `module_index` — no `"analyzed"` placeholders remain
- [ ] Module **names are unchanged** from the v1 state — the migration derived roots without redrawing boundaries
- [ ] Existing `issues` survived with their `status` values intact

### Checkpoint B.4 — Second Run Is Fast

Make another one-module change, commit, and run update again:

- [ ] No migration message this time (it is already v2)
- [ ] Behaves exactly as Scenario A — no re-survey, no unchanged-report reads

---

## Critical Violations

Any of these is a skill failure:

- [ ] **Re-surveys the codebase to re-derive module roots** — `module_index` is authoritative; a re-survey can redraw a boundary, rename a module, and break every inbound wikilink
- [ ] **Reads an unchanged module's report or generated doc** — carrying forward means leaving the file alone
- [ ] **Re-analyzes an unchanged module**
- [ ] **Advances a carried-forward module's `analyzed_at` / `source_commit`**
- [ ] **Falls back to full generation on a v1 vault** instead of migrating
- [ ] **Dispatches Sonnet or Opus for the v1 backfill**
- [ ] **Pastes a report or the full synthesis into any agent prompt**
- [ ] **Puts a module's file list in a receipt** rather than the report's `files:` frontmatter — the receipt must be a fixed small size regardless of module size
- [ ] **Reads the previous `_state/synthesis.md`** — purposes come from `module_index`
- [ ] **Marks an issue `resolved` without the diff having touched its file/lines** (deleting the whole module is the one exception)
- [ ] **Writes any report before re-checking the concurrency claim** — losing the race after Step 5 leaves reports beside another run's state
- [ ] **Carries forward a module whose report `source-commit` disagrees with state** — that is a torn previous run and must be re-analyzed
- [ ] **Leaves a deleted module's report or doc on disk**, or leaves dangling `dependency_graph` edges pointing at it
- [ ] **Regenerates a cross-module doc whose gating signal did not change**, or **skips one without reporting** which signal was unchanged
- [ ] **Deletes or regenerates unchanged module docs**

---

## Cost Comparison (Optional but Informative)

The point of this design is cost, so measure it rather than assuming it.

1. Stash the skill changes (`git stash`), run Scenario A against a fresh copy of the baseline vault, and record token usage.
2. Restore the changes, repeat against another fresh copy, and record again.
3. Compare **orchestrator output tokens** in particular — that is where pasted payloads and re-surveys land.

Record the observed numbers rather than asserting a target. Expected shape: a large reduction concentrated in the orchestrator, with per-module analysis cost roughly unchanged (the same modules still get the same two passes).

---

## Results Template

```
Date:
Codebase / module count:
Modules changed:

Scenario A — v2 incremental
  Mode auto-selected:              quick / full
  Modules re-analyzed:             __ of __
  Re-survey detected:              yes / no        (yes = FAIL)
  Unchanged reports read:          __             (>0 = FAIL)
  Unchanged docs byte-identical:   yes / no
  Carried-forward timestamps kept: yes / no        (no = FAIL)
  Issues carried / resolved:       __ / __
  Cross-module docs skipped:       ____           (and was it reported?)
  Verification scope:              written-only / full-vault
  Guard checked before Step 5:     yes / no        (no = FAIL)
  Receipt carried a file list:     yes / no        (yes = FAIL)

Scenario B — v1 migration
  Migration detected & reported:   yes / no
  Fell back to full generate:      yes / no        (yes = FAIL)
  Backfill agent tiers:            ____           (any non-Haiku = FAIL)
  Module names preserved:          yes / no        (no = FAIL)
  Valid v2 state after:            yes / no

Cost comparison (if run)
  Before — orchestrator output tokens:
  After  — orchestrator output tokens:

Critical violations:
Notes:
```
