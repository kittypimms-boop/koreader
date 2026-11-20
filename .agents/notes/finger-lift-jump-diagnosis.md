# Finger-lift jump: what to capture and how to read it

Applies to: `plugins/fastnote.koplugin/drawingcanvas.lua` (`onDrawStroke`,
`onDrawStrokeEnd`, `_pollPen`, `_pollTouch`, `_makeStrokeTrace`),
`lib/strokebuffer.lua` (owner tag), `lib/eventlog.lua`, `input/pendev.lua`,
`input/touchdev.lua`
See also: `notes/finger-draw-input-latency.md`, `notes/input-path-architecture.md`

**Status: open. Instrumentation is in; the cause is not confirmed on a device.**

## The symptom

Drawing with a finger (`finger_draw` on), sometimes when the finger lifts the
line ends as if the finger had moved to one other point (reported as "a central
point"), instead of ending where the finger lifted.

## Why it is hard to pin from the code

On a Kobo with `finger_draw` on, three input paths can write into the one
`StrokeBuffer.current`: the pen state machine (`_pollPen`), the raw touch reader
(`_pollTouch`), and KOReader's gesture path (`onDrawStroke` / `onDrawStrokeEnd`).
Any path's move extends another path's stroke and any path's up commits it.
A raw `(0, 0)` or garbage coordinate maps to a screen corner on every path, never
the centre, so "moved to 0,0" does not explain a central end point by itself.

## Hypotheses, and the log lines that settle each

| Id | Hypothesis | What the log shows if true |
|---|---|---|
| H-A | Finger events leak into the pen state machine (finger `BTN_TOUCH`, legacy `ABS_X/Y`) and the pen path draws or commits the finger's stroke | `DEC down` or `DEC move` with `tool=pen` while drawing with a finger; `SB move owner=pen open=gesture` |
| H-B | The raw touch reader draws untranslated digitizer coordinates (a 90 degree rotation about a point near the centre) | `TCH` lines present; `SB down owner=touch open=gesture ... replaces-open-stroke` partway through a stroke; a faint rotated copy of finger strokes on the page |
| H-C | The final gesture segment goes to a wrong lift-frame position | `GES pan_release pos=` differs from the previous `GES pan pos=` by a lot, with a legacy `ABS_X` in the last `RAW` frame |
| H-D | Zero or garbage digitizer values | `RAW` `ABS_MT_POSITION_*` of 0 in the last frame before the lift |

Quick separator: wait about 3 seconds (the colour settle rebuilds the display from
the stored strokes), or leave the page and come back. If the bad end segment is
gone, it was display-only (H-C). If it is still there, it was saved into the page
(H-A or H-B).

## How to capture

1. Open a notebook, hamburger menu, turn **Debug log: on**.
2. Turn **Finger draw: on**. Draw with a finger until the bad end appears. Try it
   once before touching the pen in the session and once after.
3. Turn the log off. The log is `<koreader data dir>/fastnote/input.log`.
4. Note on paper: did the bad segment stay after 3 seconds, and where did it end
   (centre, a corner, the last pen position)?

## Log line reference

Every line starts with a monotonic millisecond timestamp, then a tag.

| Tag | Source | Fields |
|---|---|---|
| `RAW` | every event on the pen device (the shared node, so finger slots are included) | type, code, value |
| `DEC` | decoded pen events | `down`/`move`/`up`/`hover`/`leave`, tool, x y p |
| `TCH` | raw touch reader events | `down`/`move`/`up`, slot, id, x, y, major, accepted or rejected by palm rejection |
| `GES` | gesture path | `pan` (pos, start, last stroke point) and `pan_release` (pos, last stroke point) |
| `SB` | stroke buffer | an operation by a different owner than the open stroke's, a down that replaces an open stroke, and `JUMP` for a step over 120 px inside one stroke |
| `INFO` | once, when logging starts | which input device paths are open, whether pen and touch share a node, `use_raw_input`, `finger_draw` |

## The owner tag

`StrokeBuffer` operations carry an owner (`"pen"`, `"touch"`, `"gesture"`). By
default the tag is only reported to the trace, and behavior is unchanged. Setting
`StrokeBuffer.enforce_owner = true` (or on an instance) isolates owners: another
owner's move and up are ignored, and another owner's down commits the open stroke
instead of discarding it. Do not turn enforcement on by default until the capture
says which path is interfering; it can change what gets saved when two paths record
the same finger.

## Known gap

`_pollTouch` has no chrome-strip guard and does not translate coordinates into
screen space (KOReader's Kobo input hook swaps axes and mirrors Y for `KoboMonza`
on the gesture path only). If H-B is confirmed, that reader needs both.
