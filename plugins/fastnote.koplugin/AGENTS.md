# AGENTS.md — fastnote.koplugin

Read this before changing any code in this directory.

**This file is an index, not a reference manual.** It tells you what exists
and where — not how it works or why it was built that way. Every linked file
below is self-contained; open it only when your task touches that topic.
Don't duplicate linked content back into this file when editing it.

**Editing this file or adding to `.agents/`?** Read
`.github/skills/agents-md-authoring/SKILL.md` (repo root) first — it has the
decision tree for where new content goes and the checklist this file is
held to.

---

## What This Plugin Does

`fastnote` is a KOReader plugin for the **Kobo Libra Colour** that provides a
full-screen hand-drawn note-taking canvas: multi-page notebooks, Wacom EMR
pen input with pressure and hardware eraser detection, palm rejection, dark
mode, a 6-color ink palette, undo/redo, and SVG-based page storage.

**Target hardware:** Kobo Libra Colour (`KoboMonza`, MTK SoC, Kaleido 3
color E-ink). Pen: Kobo Stylus 2 (Wacom EMR, pen + eraser tips). Digitizer:
Elan combo chip on `/dev/input/event1` — handles pen **and** capacitive
touch in the same device node via MT protocol.

---

## Where design decisions live

All paths below are relative to the **repo root** (`.agents/` is not inside
this plugin directory):

- **`.agents/planning/post-v1-roadmap-handoff.md`** — what happens next:
  six workstreams (emulator, finger latency, resume, thumbnails, folders,
  hardware input, OCR), the decisions already settled, and sequencing.
  Start here if you're picking up new work.
- **`.agents/planning/fastnote-dev-plan-v2.md`** — canonical design doc:
  storage layout, coordinate translation formula, palm rejection algorithm,
  stage-by-stage build plan, open questions. Read before implementing
  anything non-trivial.
- **`.agents/ADRs/`** — one file per settled architectural decision
  (storage format, dual input path, undo scope, notebook layout, workflow).
  Check before re-opening a question that's already been decided.
- **`.agents/notes/`** — topic references for specific gotcha-prone areas
  of the code (see "Topics" table below).
- **`.agents/plans/`** — chunk-level implementation plans and handoffs,
  mostly historical; each opens with a `**Status:**` line.
- **`.agents/scratch/`** — gitignored. Your working notes for the session
  you're in. Write here freely instead of leaving half-finished thinking in
  a tracked file; promote anything durable before you finish.
**A second, plugin-local `.agents/` also exists**, at
`plugins/fastnote.koplugin/.agents/` — note the different root. It holds two
files, both historical:

- `planning/next-stages-plan.md` — an older phase plan, largely superseded;
  read the status banner at its top before trusting any of it.
- `ADRs/adr-006-stage12-color-develop.md` — **numbered ADR-006, but it is
  not the repo-root ADR-006.** The root one is the UUID directory layout;
  this one is Stage 12's colour model and deferred develop refresh. Two
  unrelated decisions share a number across the two directories. Check
  which root you're under before citing "ADR-006".

New content goes in the **repo-root** `.agents/`, not this one.

---

## Workflow

**No pull requests. Commit directly to `master` and push.** Why:
`.agents/ADRs/ADR-007-direct-to-master-no-prs.md`.
Local `busted spec/` is the test gate (run from this directory).
The macOS CI workflow (`.github/workflows/build.yml`) is manual-trigger only.

---

## Current State

**Feature complete for daily use; the work now is tidying, not building.**
Core drawing, palm rejection, SVG persistence, notebook browser, eraser,
undo/redo, dark mode, the 6-color palette, and live color ink are all
implemented and passing `busted spec/`. Live color is confirmed working on
device and no longer carries an "experimental" label. Stage 13 (optional
polish — thumbnails, PDF export) remains unstarted. For the stage-by-stage
breakdown of what each stage covers, see
`.agents/planning/fastnote-dev-plan-v2.md` (a design doc — it carries no
per-stage status markers; this section is where status lives).

**Known open issue, partially fixed:** finger drawing registers late on each
contact. The stroke no longer *starts in the wrong place* — it is back-filled
to the real touch-down point — but ink still appears late, because the wait
itself is KOReader's pan-classification threshold and is untouched. The pen
path is unaffected. Unverified on device. See
`.agents/notes/finger-draw-input-latency.md`.

**Known hardware quirk:** the Elan combo chip handles pen and touch on the
**same** device node (`event1`), not separate nodes as the original design
doc assumed. If `TouchDev.find()` fails, the canvas still works — palm
rejection is simply disabled.

---

## Finding your way around

`ls` tells you what files exist; this section only points at the
non-obvious. Directory roles:

| Directory | Holds | Testable? |
|---|---|---|
| `lib/` | Pure Lua — no KOReader dependency, which is why it's unit-testable | `busted` |
| `model/` | Notebook and library data model, plus app-wide persisted state | `busted` |
| `input/` | FFI raw-evdev readers | **No** — device only |
| `ui/` | Only the notebook browser; the rest of the UI is in `drawingcanvas.lua` | emulator |

Two invariants that, if violated, reintroduce already-fixed bugs:

- **BlitBuffer is a display cache, never the source of truth** — StrokeBuffer
  is authoritative (ADR-002).
- **`use_raw_input = Device:isKobo()` picks gesture vs. raw evdev, and both
  paths must keep working** (ADR-003).

**For the data flow, the negative-space traps, and where each concern
actually lives, load `.agents/notes/code-layout.md`** — that's the file to
read before hunting for something in this directory.

---

## Development Loop

```bash
cd /path/to/koreader && ./kodev run        # SDL emulator — most work happens here
cd plugins/fastnote.koplugin && busted spec/   # unit tests, ~2s
```

**If `busted` is missing, install it from the distro, not LuaRocks:**
`sudo apt install lua-busted` (Debian/Ubuntu). `luarocks install busted`
pulls its dependencies from GitHub tarballs, which fails outright behind a
proxy or an offline network — a dead end that costs a while to diagnose.

**If `./kodev` fails immediately**, the `base/` submodule is probably not
initialised — it carries the entire native toolchain. `git submodule update
--init --recursive`. Full emulator setup, including running it headless over
SSH and the DPI flag that matters: `.agents/planning/post-v1-roadmap-handoff.md`
→ W0.

The emulator has no `/dev/input/eventX`, no `EVIOCGABS`, no E-ink waveform
modes — it renders widgets/BlitBuffer/gestures only. Raw input and refresh
behavior require on-device testing (`evtest` for event inspection; crash
log at `<onboard>/.adds/koreader/crash.log`).

**Before adding or fixing anything in `lib/`, `model/`, or `spec/`:** read
`.github/skills/test-driven-development/SKILL.md` (repo root) — it covers
when to write the spec first in this codebase and when the raw-evdev /
widget code genuinely can't be unit-tested.

---

## Coding Conventions

- **Lua dialect:** LuaJIT / Lua 5.1 — see `.github/instructions/lua.instructions.md`
  (repo root) for the full rules and the bugs each rule prevents.
- Read the Lua instructions file before writing anything — it covers the `_`
  vs `__` gettext gotcha and other rules that have already caused real bugs
  in this codebase.
- **Documentation changes ride with the code change that needs them** — see
  `.github/skills/documentation-as-code/SKILL.md` (repo root) for what moves
  together (doc comments, ADRs, config examples, the `.agents/notes/` topic
  covering the area you changed).
- **E-ink refresh / waveform changes:** hard rules in
  `.github/skills/waveform-experimentation/references/eink-refresh-rules.md`; on-device test
  procedure in `.github/skills/waveform-experimentation/SKILL.md` (both
  repo root).

---

## Topics

Deep-dive references for specific areas. Load the one relevant to your task;
skip the rest.

| Topic | What it covers | File (repo root `.agents/`) |
|-------|-----------------|------------------------------|
| Code layout / data flow | How the pieces connect, and what is deliberately not where you'd expect | `notes/code-layout.md` |
| Color / dark mode | Canonical hex storage invariant, why dark mode must be display-only | `notes/stroke-color-invariant.md` |
| E-ink refresh / waveforms | Kaleido color waveform modes, A2-live + deferred GLRC16 tighten-pass design | `notes/waveform-refresh-research.md` |
| Input path architecture | Gesture vs. raw-evdev, per-flag scope, hardware eraser detection | `notes/input-path-architecture.md` |
| Finger-draw latency (open) | Why finger strokes lose their opening millimetres, and the candidate fixes | `notes/finger-draw-input-latency.md` |
| Finger-lift jump (open) | Hypotheses for a stroke ending at the wrong point when a finger lifts, the debug-log capture steps, and which log line proves which cause | `notes/finger-lift-jump-diagnosis.md` |
| Canvas widget lifecycle | `self.dimen` mutation rule, orientation re-lock, gesture zone timing | `notes/canvas-widget-gotchas.md` |
| Known tech debt | Deferred cleanup items and their resolutions | `notes/tech-debt.md` |
| Storage format | SVG + embedded JSON metadata | `ADRs/ADR-001-svg-with-embedded-json-metadata.md` |
| Source of truth | StrokeBuffer vs. BlitBuffer | `ADRs/ADR-002-strokebuffer-as-source-of-truth.md` |
| Dual input path | Why raw evdev + gesture fallback both exist | `ADRs/ADR-003-dual-path-raw-evdev-plus-gesture-fallback.md` |
| Hover suppression | Pressure-based BTN_TOUCH synthesis | `ADRs/ADR-004-pressure-based-btn-touch-synthesis.md` |
| Undo scope | Why undo is per-page | `ADRs/ADR-005-per-page-undo-stack.md` |
| Notebook storage layout | UUID directory layout | `ADRs/ADR-006-uuid-directory-layout-for-notebooks.md` |
| Commit-to-master workflow | Why this repo runs without pull requests | `ADRs/ADR-007-direct-to-master-no-prs.md` |
| Coordinate translation | Rotation-aware raw-to-screen mapping formula | `planning/fastnote-dev-plan-v2.md` → "Coordinate translation" |
