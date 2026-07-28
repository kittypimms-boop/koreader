# Code layout and data flow

Applies to: all of `plugins/fastnote.koplugin/`
See also: `ADRs/ADR-002-strokebuffer-as-source-of-truth.md`,
`ADRs/ADR-003-dual-path-raw-evdev-plus-gesture-fallback.md`,
`notes/input-path-architecture.md`

Load this when you need to know **how the pieces fit together** or **where a
concern lives**. A directory listing already tells you what files exist —
this file only records what a listing can't.

---

## The rule

Two invariants. Violating either reintroduces a bug that has already been
found and fixed once:

- **BlitBuffer is a display cache, never the source of truth.** StrokeBuffer
  is authoritative; the display buffer is rebuilt by replaying it. See
  ADR-002.
- **`use_raw_input = Device:isKobo()` selects gesture vs. raw-evdev input,
  and both paths must keep working.** A change that only fixes one path is
  half a change. See ADR-003 and `notes/input-path-architecture.md`.

## Data flow

```
main.lua
    └── UIManager:show(DrawingCanvas)
            └── drawingcanvas.lua (InputContainer)
                    ├── BlitBuffer (display cache — rebuilt from StrokeBuffer)
                    ├── StrokeBuffer (source of truth for stroke data)
                    ├── input/ (raw evdev, on device only)
                    │       ├── pendev.lua    → pen_statemachine → {down/move/up/hover}
                    │       └── touchdev.lua  → MT slot events
                    └── lib/palmreject.lua → filters touch through a pen-proximity gate
```

Raw pen bytes never reach the canvas directly — `pendev` feeds
`pen_statemachine`, which is what emits the high-level events the canvas
acts on. Touch takes the parallel route through `palmreject`. If you're
chasing an input bug, find which of those three stages drops the event
before reading `drawingcanvas.lua`.

## Negative space — things that are NOT where you'd expect

- **There is no `ui/colorpicker.lua`, no `ui/chrome.lua`, no
  `input/buttondev.lua`, and no `state.lua`.** The menu, chrome strip,
  orientation handling and both color pickers all live inside
  `drawingcanvas.lua`. Earlier revisions of this repo's own docs listed those
  files as real; they never existed. `ui/` contains only the notebook
  browser.
- **`lib/` is not a grab-bag** — everything in it is pure Lua with no
  KOReader dependency, which is exactly why it is unit-testable. The one
  exception is `Stroke:paintTo`, which needs a BlitBuffer.
- **`input/` is FFI and cannot be unit-tested at all.** Validate on device.
  Everything under `spec/` runs headless; there is no spec for `input/`, and
  that's deliberate, not an oversight.
- **`plugins/fastnote.koplugin/dev-plan-v2.md` is a convenience copy** of
  `.agents/planning/fastnote-dev-plan-v2.md`. They must stay byte-identical
  — `diff` them whenever either is touched.

## Where to check when touching this area

- Adding a module to `lib/` or `model/`? It needs a `spec/` sibling — see
  `.github/skills/test-driven-development/SKILL.md`.
- Adding a config key? `lib/config.lua` `DEFAULTS` is the authoritative list;
  `fastnote.conf.example` documents the same keys and must be updated with
  it.
- Adding a UI surface? Check whether it belongs inside `drawingcanvas.lua`
  with the rest of the chrome before creating a new `ui/` file.
