# Stroke color invariant

Applies to: `plugins/fastnote.koplugin/drawingcanvas.lua`, `lib/stroke.lua`, `lib/strokebuffer.lua`

---

## The rule

`Stroke.color` is always a canonical `"#rrggbb"` hex string. `penDown()` is
always called with `self._current_color` (the hex string), **never** with
`self:_strokeColor()` (a Blitbuffer color object).

Dark mode is a **display-only transform**, applied at paint time:
- `_repaintAll()` passes `Blitbuffer.COLOR_WHITE` as `color_override` to
  `StrokeBuffer:repaintTo()` → `Stroke:paintTo()` when `self._dark_mode` is true.
- Stroke data on disk and in memory is never mutated for dark mode.

## Why this matters

Storing a Blitbuffer color *object* instead of the hex string breaks two
things at once (both were real bugs, fixed together):

1. **Dark mode drawing** — strokes drawn in dark mode would store the
   `COLOR_WHITE` object as `Stroke.color`. Nothing after that point ever
   converts it back correctly.
2. **SVG round-trip** — `Stroke:toTable()` serializes `self.color` directly
   into JSON. A non-string color produces invalid SVG; `colorFromString`
   fails on reload and silently falls back to black, but with different
   compositing than the live-drawn stroke — reloaded strokes look lighter
   than freshly drawn ones.

## Where to check when touching this area

- `_strokeColor()` (`drawingcanvas.lua`) — returns the **display** color
  (object), used only for live-buffer painting, never stored.
- All three `penDown()` call sites (gesture path, `_pollPen`, `_pollTouch`)
  must pass `self._current_color` (string), not `self:_strokeColor()`.
- `Stroke:paintTo(bb, color_override)` — `color_override` is the *only*
  legitimate place a Blitbuffer color object enters the paint path.

## Confirmed on device (2026-07)

After the `paintRectRGB32` color-rendering fix (see
`.agents/notes/waveform-refresh-research.md`), the maintainer confirmed
this invariant holds exactly as designed under a case that's easy to get
wrong: drawing in dark mode with a non-black color (e.g. blue), with
`live_color_refresh` off, then switching back to light mode correctly
shows the stroke's true stored color — not white, not black. This is
`Stroke.color` staying the canonical hex the whole time (dark mode never
touched it) plus `_rebuildDisplayFromStrokes` correctly passing `nil` as
`color_override` once back in light mode, letting each stroke's own
stored color render. Confirms there's no separate dark-mode-specific
color path to worry about when reasoning about Ask 3's
`auto_live_color_refresh` (`lib/canvas_utils.lua`) — it only decides
what's shown live, never what's stored.
