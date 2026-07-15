# Post-color-fix followups: 2 bugs + 3 feature asks

**Status: PLANNED, NOT STARTED.** Written after the `paintRectRGB32` color
fix landed and was confirmed working on device. Covers everything raised
in the same conversation: two bugs found during normal use, and three
feature requests. Each item below has its own investigation findings and
proposed design — nothing has been implemented yet per the "just look
things over and plan" instruction this was written under.

Suggested execution order (independent items; do in any order, but this
is a sensible one — quick wins and safety fixes first):

1. Bug 1 (spurious line) — safety/correctness fix, no new surface area.
2. Bug 2 (stop after 2 empty pages) — safety fix, small and self-contained.
3. Ask 2 (secondary button → quick menu) — small wiring change, reuses
   an existing dialog.
4. Ask 1 (page picker) — small, self-contained new feature.
5. Ask 3 (auto live-color-refresh) — small, but touches color/dark-mode
   interaction, worth doing after the others are settled and re-verified
   on device.

---

## Bug 1: finger-draw + hamburger tap draws a spurious line to the screen edge

**Symptom (reported):** with `finger_draw` on, drawing then tapping the
hamburger menu icon causes existing lines to appear to sprout "a line
connecting the edges to a single point at the edge of the screen."

**Investigation:** `self.ges_events.DrawStroke`/`DrawStrokeEnd`
(`drawingcanvas.lua` ~390-395) are registered with `range = self.dimen`
— the **entire canvas, including the chrome strip** — not just the
drawing area below it. `onDrawStroke` (~882) bails out early when
`y < CHROME_HEIGHT`:

```lua
if y < CHROME_HEIGHT then return end
```

Unlike the raw-evdev chrome-strip handler in `_pollPen` (~1450), which
explicitly calls `self._stroke_buf:penUp()` before returning, this early
return does **not** close the current stroke. `onDrawStrokeEnd` (~941)
doesn't check `CHROME_HEIGHT` at all — it always draws a final segment
from the stroke's last known point to wherever the gesture ended:

```lua
if self._stroke_x and self._stroke_y then
    self._stroke_buf:penMove(x, y, DEFAULT_LINE_WIDTH)
    self:_drawSegment(self._stroke_x, self._stroke_y, x, y, DEFAULT_LINE_WIDTH)
end
```

Hypothesis: a tap on the hamburger icon (top-right, inside the chrome
strip) can be recognized by KOReader's gesture detector as a trivial
pan+pan_release (near-zero movement before release is common touchscreen
jitter) in addition to being recognized as a `tap` for `onMenuTap`. If
so: `onDrawStroke` fires first, sees `y < CHROME_HEIGHT`, and returns
without closing the open stroke; `onDrawStrokeEnd` then fires with the
release position (the hamburger icon's corner) and draws a segment from
the stroke's stale last point straight there — a diagonal line crossing
much of the page, giving the visual impression described. This matches
the symptom closely (a common point, at a screen edge) but has **not
been confirmed on device** — it's the leading hypothesis from reading the
code, not a certainty.

**Proposed fix:** make `onDrawStroke`'s chrome-strip early return close
the stroke the same way the raw-input path already does:

```lua
if y < CHROME_HEIGHT then
    if self._stroke_buf.current then
        self._stroke_buf:penUp()
        self._page_dirty = true
    end
    self._stroke_x, self._stroke_y = nil, nil
    self._ges_start_x, self._ges_start_y = nil, nil
    return
end
```

This is widget/gesture glue (not unit-testable per the TDD skill), so the
fix itself has no spec, but should be paired with an on-device test:
finger-draw a line that ends near the top of the drawing area, tap the
hamburger icon, confirm no spurious segment appears. If the hypothesis is
wrong (bug persists after this fix), the next step is capturing
`debug_input_log`/gesture debug output for the exact tap to see which
`ges_events` actually fire.

---

## Bug 2: stop auto-advancing after 2 consecutive empty pages

**Ask:** pressing "next page" repeatedly (e.g. accidental physical button
mashing) currently creates blank page after blank page with no limit.
Want it to stop after 2 empty pages in a row, "without adding a ton of
complexity."

**Investigation:** `DrawingCanvas:_navigatePage(delta)` (~1826) calls
`main.lua`'s `on_page_forward` callback (~104), which unconditionally
does `nb:addPage()` whenever `page_idx > nb:pageCount()` — no concept of
"is this page empty" exists anywhere today. `Notebook` (`model/notebook.lua`)
tracks no per-page stroke count. `DrawingCanvas:loadPage(path)` (~1675)
does populate `self._stroke_buf` from the SVG (or leaves it fresh/empty
if the file doesn't exist yet), so `#self._stroke_buf.strokes == 0` is a
free, already-available "is this page empty" check right after navigating
— no new file I/O needed.

**Proposed design (small, self-contained):**
- New pure function in `lib/canvas_utils.lua`, spec-first:
  `canvas_utils.should_block_forward_nav(blank_streak, max_blank_streak)`
  → boolean, or simpler, inline the threshold check directly in
  `_navigatePage` if a whole function feels like overkill for a
  two-line comparison — judgment call, lean toward the pure function
  for testability per the TDD skill, but keep it trivial.
- `DrawingCanvas` gains `self._blank_streak = 0` (instance state).
  In `_navigatePage(1)` (forward only): after `loadPage`, if
  `#self._stroke_buf.strokes == 0` increment `self._blank_streak`, else
  reset it to 0. Navigating backward always resets it to 0 (going back
  to re-examine pages shouldn't count against the forward streak).
- Before calling the forward callback: if `self._blank_streak >= 2`,
  don't advance — show a brief `InfoMessage` ("Already 2 blank pages —
  draw something or use the notebook browser to add more.") and return,
  instead of calling `cb()`/`addPage()` again.
- Deliberately no new config flag for the threshold — hardcode `2` as a
  named constant (`MAX_BLANK_PAGE_STREAK`), matching "without a ton of
  complexity." Revisit only if this turns out to be annoying in practice.
- No override gesture planned (e.g. "hold to force") — if the user
  genuinely wants a 3rd blank page, the notebook browser's existing
  "create new page" affordance (if one exists) or drawing something
  first (resetting the streak) covers it. Flag this trade-off for the
  maintainer to confirm is acceptable before building.

---

## Ask 1: page picker — tap the page-number readout, type a page to jump to

**Investigation:** the "n / N" text in the chrome strip is painted by
`_paintChrome` (~586) but has **no associated tap gesture zone** today —
only `ExitTap` (left) and `MenuTap` (right) exist in the chrome strip;
the center (where the page number sits) is dead space for input.
`_showQuickMenu`'s pressure row already uses `ui/widget/spinwidget`
(`SpinWidget`) for a numeric input popup (~845-861) — a directly reusable
pattern for "enter a page number."

**Proposed design:**
- New `self.ges_events.PageNumberTap` (`ges = "tap"`, range = a
  Geom covering the center chrome area between `CHROME_EXIT_W` and
  `self.dimen.w - CHROME_TOOLS_W`), registered alongside `ExitTap`/
  `MenuTap`, updated in `_updateGestureZones()` on rotation the same way
  `MenuTap`'s zone already is.
- New `DrawingCanvas:onPageNumberTap()` → shows a `SpinWidget` (value_min
  = 1, value_max = `self.page_count`, value = `self.page_index`,
  value_step = 1) titled "Go to page"; on confirm, computes the target
  page's path via a new small helper (needs a "jump to arbitrary page N"
  path — `_navigatePage` only does ±1 today, so this needs either a
  `_navigatePage(delta)` generalization or a new `_navigateToPage(idx)`
  that mirrors `_navigatePage`'s body but takes an absolute index and a
  new `on_page_jump` callback in `main.lua` (parallel to
  `on_page_forward`/`on_page_back`, computing the target path directly
  from `nb:pagePath(idx)` without the "extend notebook" logic
  `on_page_forward` has).
- Interacts with Bug 2: jumping via the picker should probably reset
  `self._blank_streak` too (it's a deliberate navigation, not
  accidental button mashing).

---

## Ask 2: pen secondary (side) button opens the quick menu

**Status: IMPLEMENTED, needs on-device confirmation.**

**Ask, refined after discussion:** double-tap (the quick menu's original
trigger) had reliability issues on device, so the side button is now the
**sole** trigger — not an addition alongside double-tap. Must fire
whenever the digitizer can sense the pen at all ("near" — proximity, not
requiring screen contact), and must be suppressed while a stroke is
actively being drawn.

**What shipped:**
- `input/pendev.lua`'s `side_button` branch (in the `BTN_STYLUS`/
  `BTN_STYLUS2` `EV_KEY` handler) now calls `cb({type = "side_button"})`
  on press (`ev == 1`) only — no release event is dispatched. Since
  `BTN_STYLUS`/`BTN_STYLUS2` travel over the EMR link, this already only
  fires when the pen is within proximity range, giving "near, not
  necessarily touching" for free — no separate proximity check needed.
- `drawingcanvas.lua`'s `_pollPen` poll callback gained an
  `ev.type == "side_button"` branch that calls `self:_showQuickMenu()`,
  gated on `not self._last_pen_x` — nil exactly when no pen stroke is in
  progress (the same flag the "up" branch already clears), so a press
  mid-stroke is a no-op.
- The double-tap trigger was removed entirely: `self.ges_events
  .QuickDoubleTap` registration and `DrawingCanvas:onQuickDoubleTap()`
  deleted (no other code referenced them). `_showQuickMenu()`'s doc
  comment updated to describe the new trigger and why the old one was
  removed.
- Not unit-testable (FFI input path + widget glue) — `busted spec/`
  stayed at 263/0 (no lib/ behavior changed). **Needs on-device
  confirmation**: side-button press with pen hovering (not touching)
  opens the menu; press while a stroke is in progress does nothing;
  double-tap no longer opens anything.

---

## Ask 3: auto-toggle `live_color_refresh` from color/dark-mode choices (future)

**Ask:** picking a non-black color should auto-enable
`live_color_refresh`; picking black should auto-disable it (not needed
for black-only ink); entering dark mode should force it off too (ink
always shows black in dark mode regardless of the flag, until switching
back to light mode).

**Investigation:** `live_color_refresh` (`drawingcanvas.lua` ~192) is a
plain instance flag, toggled only by one hamburger-menu row (~722-726).
Neither color-picker callback (`color_btn`, defined twice — hamburger
~643-647 and quick-menu ~822-826 — worth a shared-helper refactor while
touching this) nor `_toggleDarkMode` (~1744) touches it today.
`PALETTE[1]` is `{name = "Black", hex = "#000000"}` — a plain string
comparison identifies "black selected."

**Proposed design (when this gets picked up):**
- New pure function in `lib/canvas_utils.lua`, spec-first:
  `canvas_utils.auto_live_color_refresh(selected_hex, dark_mode)` →
  boolean, encoding: dark_mode → always `false`; `selected_hex ==
  "#000000"` → `false`; otherwise → `true`.
- Call it from both `color_btn` callbacks (after setting
  `self._current_color`) and from `_toggleDarkMode` (after flipping
  `self._dark_mode`), assigning the result to `self.live_color_refresh`.
- The manual hamburger-menu toggle stays available as an explicit
  override after the fact — auto-behavior only fires on the color-pick/
  dark-mode-toggle events themselves, consistent with how
  `live_color_refresh` already behaves as a plain session-only flag.
- **Worth reducing duplication while here:** the two `color_btn` closures
  are identical except for which `_quick_menu`/`menu` variable they close
  over — consider extracting a shared `_makeColorButton(entry, close_fn)`
  helper if this doesn't overcomplicate the diff.

**Documentation note requested by the maintainer, worth capturing
regardless of when the toggle behavior above ships:** confirmed on
device — painting in dark mode with a color (e.g. blue), with
`live_color_refresh` off, then switching to light mode, correctly shows
the true stored color. This is the existing dark-mode-is-a-display-only-
transform design (`.agents/notes/stroke-color-invariant.md`,
`_rebuildDisplayFromStrokes`'s `override = self._dark_mode and
Blitbuffer.COLOR_WHITE or nil`) working as intended, now that the
`paintRectRGB32` fix means color actually reaches the screen at all. Add
a short confirmed-behavior note to `stroke-color-invariant.md` when this
round's code changes are made, regardless of whether the auto-toggle
feature itself ships in the same pass.
