# AGENTS.md — `.agents/`

Index of this directory. **Everything here is about `fastnote.koplugin`**,
even though the directory sits at the repo root (see
`.github/instructions/agents.instructions.md` for why).

**Editing anything in here?** That instructions file applies automatically
and carries the rules — index-not-manual, the decision tree for where new
content goes, and why ADRs don't get rewritten. The step-by-step checklist
and templates are in `.github/skills/agents-md-authoring/SKILL.md`.

Start at `plugins/fastnote.koplugin/AGENTS.md` if you're new to the repo —
it's the real entry point and its Topics table routes into the files below.

---

## Layout

| Directory | Holds | Lifecycle |
|-----------|-------|-----------|
| `ADRs/` | One settled architectural decision per file | Historical record — append to Consequences, never rewrite Decision |
| `notes/` | Topic references for gotcha-prone code areas | Living — update in place when the implementation changes |
| `planning/` | Design docs, research writeups, roadmaps | Living while the work is open |
| `plans/` | Chunk-level implementation plans | Mostly historical; kept as a record of how things got built |

## Where to start, by task

| If you're… | Read |
|---|---|
| Picking up the next phase of work | `planning/post-v1-roadmap-handoff.md` — six workstreams, decisions already made, sequencing |
| Implementing anything non-trivial | `planning/fastnote-dev-plan-v2.md` — canonical design doc (storage, coordinate translation, palm rejection, stages) |
| About to re-open a settled question | `ADRs/` — check before arguing |
| Debugging a specific area | The Topics table in `plugins/fastnote.koplugin/AGENTS.md`, which maps code areas to `notes/` files |
| Looking into OCR | `planning/fastnote-ocr-landscape-research.md` — landscape snapshot, already done, don't redo it |

## Two things that bite

- **`planning/fastnote-dev-plan-v2.md` has a convenience copy** at
  `plugins/fastnote.koplugin/dev-plan-v2.md`. They must stay byte-identical
  — `diff` them whenever either is touched.
- **A second, mostly superseded `.agents/` exists** at
  `plugins/fastnote.koplugin/.agents/`. New content goes here, at the repo
  root, unless there's a specific reason otherwise.
