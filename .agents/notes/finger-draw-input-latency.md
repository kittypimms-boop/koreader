# Finger-draw first-contact latency

Applies to: `plugins/fastnote.koplugin/drawingcanvas.lua`
(`onDrawStroke`, `onDrawStrokeEnd`, `_pollTouch`, the `ges_events.DrawStroke`
registration), `plugins/fastnote.koplugin/input/touchdev.lua`
See also: `ADRs/ADR-003-dual-path-raw-evdev-plus-gesture-fallback.md`,
`notes/input-path-architecture.md`

**Status: open.** Reported on device; root cause below is analysis, not yet
confirmed by an on-device trace. Do the "which path is drawing" check first.

---

## The symptom

With `finger_draw` on, the first few millimetres of every finger stroke are
missing: ink starts late and short of where the finger actually landed. It is
most damaging when lifting between words — each new touchdown loses its
opening, which is exactly the part that carries letter shape, so handwriting
becomes hard to read. Drawing with the pen has no such delay.

## Why the pen is unaffected

The pen runs the raw evdev path. `_pollPen` calls `StrokeBuffer:penDown` on
the first frame that reports contact, at the real contact coordinates — no
classification step sits between the hardware event and the first stroke
point.

## Root cause (gesture path)

`ges_events.DrawStroke` is registered as a `"pan"` gesture. KOReader's
`GestureDetector` does not classify a contact as a pan until it has travelled
`PAN_THRESHOLD` from `initial_tev` (`frontend/device/gesturedetector.lua`,
`GestureDetector:init` — `screen:scaleByDPI(35)`, which on `KoboMonza`'s
300 dpi panel scales to substantially more than 35 raw pixels; measure the
actual value on device before quoting one). Until that distance is crossed
the contact is still a tap/hold candidate, so nothing is drawn.

Then a second, independent loss: when the first pan finally arrives,
`onDrawStroke` seeds the stroke from `ges.pos` — the position *after* the
threshold was crossed. `ges.start_pos` is read, but only to detect that a new
gesture began; it is never used as the stroke's first point. So the travel
that the threshold consumed is discarded rather than back-filled.

The delay and the discarded prefix compound: the user sees ink appear late
*and* starting in the wrong place.

## Which path is actually drawing — check this first

With `finger_draw` on and `use_raw_input` true, **both** the raw `_pollTouch`
loop and the gesture path are live — neither gates the other. `_pollTouch`'s
`"down"` branch calls `penDown` immediately with no threshold, so if
`TouchDev.find()` is succeeding on this unit the latency above should not be
observable. The reported symptom therefore points at the gesture path being
the one drawing finger strokes here (consistent with the Elan combo-chip
quirk in the plugin's AGENTS.md). Confirm with the debug input log before
fixing the wrong path.

Related risk to check in the same pass: if both paths ever are live at once,
every finger stroke is recorded into `StrokeBuffer` twice.

## Candidate fixes, cheapest first

1. **Back-fill from `ges.start_pos`.** Seed the stroke at `start_pos` instead
   of the first pan position. Small, local, no core changes — recovers the
   discarded prefix so the stroke has the right shape from touchdown. Does
   not remove the wait: ink still appears late, just correctly.
2. **Make raw touch the finger-draw path.** Get `TouchDev.find()` working on
   the combo chip, then gate the gesture path off whenever `_touchdev` is
   open. Removes both losses; needs the double-record guard above.
3. **Lower `PAN_THRESHOLD` for the canvas.** `GestureDetector` has no
   per-widget override, so this means patching core, and it would degrade
   tap/hold discrimination inside the canvas. Last resort.
4. **`TOUCH_POLL_INTERVAL` 0.016 → 0.008** (match `PEN_POLL_INTERVAL`).
   Worth ~8 ms; only meaningful once 1 or 2 has landed.

## Where to check when touching this area

- `onDrawStroke` — the `ges.start_pos` / `self._stroke_x` seeding block.
- The `ges_events.DrawStroke` / `DrawStrokeEnd` registration in `init`.
- `_pollTouch`'s `"down"` branch and its `self.finger_draw` guard.
- `input/touchdev.lua` `TouchDev.find()` — its `ABS=` bitmask parsing.
- Verify on device. The emulator's gesture timing and DPI scaling differ, so
  a fix that looks right under `./kodev run` proves nothing about feel.
