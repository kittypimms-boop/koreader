---
name: agents-md-authoring
description: Provides the checklist, ADR/topic-note templates, and periodic audit procedure for creating or editing AGENTS.md, ADRs, or .agents/ notes and plans in this repo. Use when creating or editing any AGENTS.md file (repo-root or plugins/fastnote.koplugin), adding an ADR or topic note, writing a planning/phase doc under .agents/planning/ or .agents/plans/, or auditing this repo's docs for staleness.
---

# Authoring AGENTS.md and .agents/ docs in this repo — workflow

This skill is the **process**: the checklist to run before finishing an
edit, templates for new ADRs and notes, and the periodic audit procedure.

For the **principles** governing what content belongs where — the
index-not-manual rule, the decision tree for where new content goes, ADRs
as historical records, and this repo's `.agents/` layout — see
`.github/instructions/agents.instructions.md`, which applies automatically
whenever you touch an `AGENTS.md` file or anything under `.agents/`. Read
that first if you haven't already; this skill assumes it.

---

## Checklist for every AGENTS.md edit

- [ ] No inline code examples — link to the instructions/notes file instead.
- [ ] No paragraph-plus explaining *why* — one clause, then a link.
- [ ] **No file-by-file map.** If you're about to list every file with a
      description of each, stop — see `agents.instructions.md` decision-tree
      item 1. Directory *roles*, negative space, and invariants stay;
      inventories go to a `notes/` topic. (This repo has shipped phantom
      entries before: `ui/colorpicker.lua`, `ui/chrome.lua`,
      `input/buttondev.lua`, and a `state.lua` were all listed as real files
      when the functionality was inline elsewhere or never built.)
- [ ] Every path mentioned anywhere in the file **actually exists** — verify
      with `ls`/`find` before writing the line.
- [ ] No hardcoded volatile numbers (test counts, "as of" dates, stage
      counts) that will silently drift. Say "run `busted spec/`" instead of
      "187 tests"; say "see the planning doc for current stage status"
      instead of embedding a stage table.
- [ ] Any claim about what's implemented/not-implemented is checked against
      the actual code in this pass, not copied from the previous AGENTS.md
      revision. Docs drift; code doesn't lie.
- [ ] If a linked note file's underlying implementation changed, update the
      note file — not AGENTS.md. AGENTS.md's line for that topic should stay
      a stable one-liner across many implementation changes underneath it.

---

## ADR template

```markdown
# ADR-NNN: <short decision title>

**Status:** Accepted
**Date:** YYYY-MM (Stage N, if applicable)

## Context

<the problem and the constraint that forced a choice>

## Decision

<what was chosen, concretely — include the actual format/algorithm/structure
if that's the substance of the decision>

## Alternatives Considered

- **<chosen option>** — why it fits the constraints.
- **<rejected option>** — Why NOT: <the specific reason — cost, complexity,
  incompatibility, a failure it would have caused>.
- **<rejected option>** — Why NOT: <specific reason>.

## Consequences

- <what this makes easy>
- <what this makes hard, or a tradeoff accepted>
- <a landmine or non-obvious follow-on effect, if any>
```

**The "Why NOT" lines are the highest-value part of an ADR** and the part
most often skipped. Without them a future agent confidently re-proposes an
option that was already investigated and rejected, and the only way to find
that out is to re-do the investigation. One sentence per rejected option is
enough.

ADR-001 through ADR-007 predate this section and use Context / Decision /
Consequences only — that's expected, not drift. Don't retrofit an
Alternatives section onto them by guessing at reasoning that wasn't
recorded; ADRs are historical records (see `agents.instructions.md`). Use
the full template for ADR-008 onward.

Use the next sequential ADR number. Remember ADRs are historical records
once Accepted — see `agents.instructions.md` for that rule before editing
an existing one.

---

## Topic note template (`.agents/notes/<topic>.md`)

```markdown
# <Topic name>

Applies to: <file path(s)>
See also: <related ADR/note, if any>

---

## The rule

<the invariant or gotcha, stated as a rule — one paragraph>

## Why this matters

<what breaks if violated — concrete, ideally referencing a real incident>

## Where to check when touching this area

<a short list of specific functions/call sites to verify>
```

Keep notes scoped to one topic. If a note grows past ~80 lines or starts
covering two unrelated gotchas, split it — the whole point is that an agent
loads only what's relevant to its current task.

---

## Periodic audit procedure

Run this whenever asked to "review the docs" or before a large refactor
that will touch many files referenced in AGENTS.md:

1. For every path mentioned in an AGENTS.md — Topics table, navigation
   hints, prose — confirm the file exists (`ls`/`find`). Remove or correct
   any that don't. Check the `notes/` topic files the same way; a stale path
   there misleads just as effectively.
2. For every "not started" / "not implemented" / "planned" claim, grep the
   actual code to confirm it's still true.
3. Diff any "convenience copy" files against their canonical source.
4. Check ADRs for implementation drift (a referenced file/function that no
   longer exists or was renamed) — add a Consequences addendum, don't
   rewrite the Decision.
5. Check `.agents/notes/` files for descriptions of behavior that has since
   shipped or changed — update the note in place.
