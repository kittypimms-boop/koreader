# DrawingCanvas widget-lifecycle gotchas

Applies to: `plugins/fastnote.koplugin/drawingcanvas.lua`

Three unrelated InputContainer/UIManager landmines that silently break the
canvas if violated. None of these produce a Lua error — they produce subtle
runtime misbehavior (dead gesture zones, rotation loops) that's hard to
trace back to the cause.

---

## `self.dimen` — in-place mutation only

`GestureRange` objects inside `self.ges_events` hold a **direct reference**
to the `self.dimen` table created at `init()`. Assigning a new table to
`self.dimen` (e.g. `self.dimen = Geom:new{...}`) silently detaches all
existing gesture zones from the widget's actual dimensions — taps stop
registering with no error.

**Rule:** always mutate `self.dimen.w` / `self.dimen.h` / etc. in place.
Never reassign `self.dimen` itself after `init()`.

## Orientation lock / re-lock

`drawingcanvas.lua` stores `self._rotation_mode` (the locked mode). On
`onSetRotationMode(event)`, if the incoming mode differs from
`self._rotation_mode`, the canvas calls `Screen:setRotationMode(self._rotation_mode)`
to re-lock — overriding whatever triggered the rotation (e.g. gyroscope).

No loop guard is needed: the re-lock call itself fires a second
`onSetRotationMode` event, but that event's incoming mode now equals
`self._rotation_mode`, so the `if` is false and recursion stops after one
extra hop.

## Gesture zone registration timing

Touch zones (`DrawStroke`/`DrawStrokeEnd`, chrome taps) must be registered
in `init()` — **not** in `onShow`. They are always registered regardless of
`use_raw_input`/`finger_draw`; the handlers themselves check those flags at
runtime and return early. This lets `finger_draw` be toggled live from the
menu without re-registering zones (which would require closing and
reopening the canvas).

## Chrome strip zones come from one layout

The five chrome taps (exit, previous page, page number, next page, menu) are
laid out by `lib/page_nav.lua` `chrome_layout`, through
`DrawingCanvas:_chromeLayout()` and `_updateGestureZones()`. `init()` and
`_reinitAtRotation()` both call `_updateGestureZones()`, so a zone never needs
its geometry written down a second time.

- The zones are disjoint, with 40 px dead gutters beside exit and menu, so a tap
  that misses an arrow cannot hit the expensive neighbours. Do not give any
  chrome handler an overlapping range: `ges_events` iteration order is not
  defined, so an overlap would be ambiguous.
- On a width too narrow for usable arrows, `chrome_layout` returns no `prev` or
  `next` and `_setTapZone` removes those two ges_events.
- `_setTapZone` mutates existing ranges in place (the `self.dimen` mutation
  rule above); it does not replace the range objects.
- Every chrome handler returns `true`, including a tap on a disabled arrow, so a
  chrome tap is consumed and never falls through to drawing.
- `CHROME_HEIGHT` is 106 px (9 mm at 300 dpi). The pen, raw touch and gesture
  guards all read the constant.

## Page turns reset state and repaint partially

Every page change (arrows, hardware keys, jump dialog, insert, delete) goes
through `_saveBeforeTurn()` then `_applyPageNavigation()`.

- `_saveBeforeTurn()` closes a stroke in progress, cancels the colour-settle
  (tighten) timer, then saves. If the save fails the turn is abandoned with a
  message, because continuing replaces the stroke buffer and loses the page.
- `_applyPageNavigation()` resets all per-stroke tracking before swapping the
  buffer, so the first point on the new page never connects to the old page's
  last point.
- The repaint uses `PAGE_TURN_REFRESH` (`"partial"`): no flash, ghosting is
  cleared, colour is kept. Do not use `"fast"` or `"a2"` for page content.
- A dirty page is saved even when it is now empty, so erasing a page's last
  stroke overwrites the old SVG instead of letting it come back.
