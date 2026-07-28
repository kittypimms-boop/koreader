---
applyTo: "**/AGENTS.md,**/.agents/**"
paths:
  - "**/AGENTS.md"
  - "**/.agents/**"
description: "Content rules for AGENTS.md files and .agents/ docs — index-not-manual principle and where new content goes."
---

# AGENTS.md and .agents/ conventions

Mindset and content rules for this repo's agent-facing documentation —
applies automatically whenever you're editing an `AGENTS.md` file or
anything under a `.agents/` directory. For the step-by-step editing
checklist, ADR/note templates, and the periodic audit procedure, see
`.github/skills/agents-md-authoring/SKILL.md` instead — this file is
principles, that skill is process. Don't restate one in the other.

---

## The core principle

**AGENTS.md is an index, not a reference manual.** It answers "what exists
and where is it handled" — never "how it works" or "why it was built that
way." If you're about to write more than one sentence explaining a
decision, a gotcha, or a piece of behavior inside AGENTS.md, stop — that
content belongs in a linked file instead, loaded only when the topic is
relevant to the task at hand.

This isn't a style preference. An AGENTS.md padded with implementation
detail misleads a reading agent into treating tangential topics as
relevant to whatever it's actually doing, and costs context on every read
regardless of relevance — the opposite of what an index is for.

Every linked detail file must be **self-contained**: a reader who opens
only that one file, with no other context, can act on it correctly.

---

## Decision tree: where does new content go?

Ask this in order — stop at the first match:

1. **"Where is X handled?" (a location, not an explanation)**
   → A navigation hint, written at an altitude that survives a refactor:
   name the directory and the symbol to grep for, not the exact path.
   "Pen events: `input/pendev.lua` feeds `lib/pen_statemachine.lua` — grep
   `_pollPen`" ages well; "`drawingcanvas.lua` line 1740" is stale by the
   end of the session.

   **Do not write a file-by-file map.** A listing of every file with a
   description of each is the single most drift-prone thing an AGENTS.md can
   contain: it re-states what `ls` already shows, and every rename, split,
   or new module silently falsifies it. This repo has shipped phantom
   entries (`ui/colorpicker.lua`, `ui/chrome.lua`, `input/buttondev.lua`, a
   `state.lua`) that were listed as real files while the functionality lived
   inline elsewhere — and, more recently, a config-key list that lost a key.
   Both were the map going stale, not an author being careless.

   Anthropic's own guidance agrees: "file-by-file descriptions of the
   codebase" is on the exclude list for context files, and `/doctor`'s trim
   check strips directory layouts and architecture overviews on the grounds
   that Claude can derive them from the code, keeping "pitfalls, rationale,
   and conventions that differ from tool defaults."

   What survives the cut, and belongs in AGENTS.md: the **negative space**
   ("there is no `ui/colorpicker.lua`; that's inline in
   `drawingcanvas.lua`"), directory *roles* rather than file inventories,
   and invariants. Anything longer than that goes in a `notes/` topic file
   and gets a Topics-table row — `notes/code-layout.md` is the worked
   example.

   **Discoverability test, for any listing you're still tempted to write:**
   a single cheap `ls` already proves a file exists, so existence alone
   earns no line. Every entry must carry something the listing wouldn't
   show — a contract, a constraint, or a non-obvious relationship to
   another file. If most entries would be self-evident from their names,
   replace the whole list with one sentence naming the entry point.

2. **A settled architectural decision — this approach over that, and why**
   → New ADR: `.agents/ADRs/ADR-NNN-slug.md`.

3. **A gotcha or invariant scoped to one code area, that causes silent
   misbehavior (not a crash) if violated**
   → New note: `.agents/notes/<topic>.md`, linked from AGENTS.md's Topics
   table.

4. **A multi-step plan, phase breakdown, or research writeup for upcoming
   or in-progress work**
   → `.agents/planning/` (design docs, research, roadmaps) or
   `.agents/plans/` (chunk-level implementation plans and handoffs, each
   opening with a `**Status:**` line). Not linked from AGENTS.md's Topics
   table unless it's a primary reference like the dev plan — most planning
   docs are found by scanning the directory, not indexed individually.

   > **`planning/` vs `plans/` is a genuinely confusing pair of names.**
   > The distinction is scope and lifecycle, not subject: `planning/` holds
   > durable documents about *what we're building and why* (the dev plan,
   > research writeups, the post-v1 roadmap); `plans/` holds a record of
   > *how one specific chunk of work got done*, and every file there carries
   > a Status line. If you're unsure, ask whether the document will still be
   > read a year from now for its content (`planning/`) or only as history
   > (`plans/`).

5. **Ephemeral working notes for the session you're in right now**
   → `.agents/scratch/` — gitignored, free-form, no conventions. Dead ends
   explored, half-formed theories, output you're mid-way through reading.
   Write here freely rather than littering the repo root or, worse, adding
   half-finished thinking to a tracked file.

   Everything else in `.agents/` is tracked and reviewed; `scratch/` is the
   one place that isn't. When a scratch note turns out to be durable,
   promote it: a gotcha becomes a `notes/` topic, a settled choice becomes
   an ADR, an unfinished piece of work becomes a `plans/` handoff with a
   Status line. Don't leave durable findings in `scratch/` — nobody else
   will ever see them.

6. **A convention that applies repo-wide, not scoped to `.agents/` or one
   feature area**
   → mindset/conventions go in a sibling `.github/instructions/<topic>.instructions.md`
   (applies automatically via `applyTo`, same mechanism as this file);
   step-by-step workflow, tools, and templates go in
   `.github/skills/<topic>/SKILL.md` (invoked explicitly for a task). This
   file plus `.github/skills/agents-md-authoring/SKILL.md` is the reference
   example of that split — mirror it rather than mixing both kinds of
   content into one file.

7. **Current status / stage completion**
   → One line in AGENTS.md's "Current State", pointing to the planning doc
   for the full breakdown. Never a full stage table or checklist in
   AGENTS.md itself — those go stale fast and belong in the planning doc,
   which is expected to be edited as phases complete.

If nothing above fits, it probably doesn't belong in `.agents/` at all —
consider whether it's just a code comment, or genuinely not worth writing
down.

---

## ADRs are historical records

Once an ADR's Status is Accepted, its Decision text is a record of what was
decided and why at the time — not a living document. If reality later
diverges from what an ADR describes (a planned file that got folded into
another module, an approach later superseded), add a short note to its
Consequences section. Don't silently edit the original Decision text to
match implementation drift — that erases the history the ADR exists to
preserve.

---

## This repo's specific layout (don't rediscover this)

- **Two `.agents/` directories exist.** The canonical one is at the **repo
  root** (`/koreader/.agents/`), even though its contents are almost
  entirely about the fastnote plugin. There's also a smaller, mostly
  superseded `plugins/fastnote.koplugin/.agents/planning/` — new content
  goes in the repo-root one unless there's a specific reason to use the
  plugin-local one.
- **State paths as repo-root-relative when the AGENTS.md itself isn't at
  repo root.** `plugins/fastnote.koplugin/AGENTS.md` references
  `.agents/ADRs/...` — a relative link from that file's own directory
  would resolve wrong. Say so explicitly ("relative to the repo root")
  rather than relying on the reader to guess.
- **`plugins/fastnote.koplugin/dev-plan-v2.md` is a convenience copy** of
  `.agents/planning/fastnote-dev-plan-v2.md` (repo root). They must stay
  byte-identical — `diff` them whenever either is touched.
- **Root `AGENTS.md` stays minimal and routes to the plugin's AGENTS.md
  fast.** Nearly all active work happens inside the plugin, not at repo
  root.
