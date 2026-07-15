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

**Status: IMPLEMENTED (proposed fix only, per "keep it simple"), needs
on-device confirmation.** `onDrawStrokeEnd` was deliberately left
untouched — closing the stroke in `onDrawStroke`'s chrome-strip early
return is sufficient on its own: `StrokeBuffer:penUp()` is a safe no-op
with no open stroke, and `onDrawStrokeEnd`'s own `if self._stroke_x and
self._stroke_y then ...` guard already skips drawing once those are
nil'd, so a later `onDrawStrokeEnd` call for the same aborted gesture
can't produce the spurious segment. Revisit `onDrawStrokeEnd` only if
this turns out not to be sufficient on device.

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

### Revisited (2026-07): the fix above was real but only covered a narrower case

**Status: root cause re-identified; fix below IMPLEMENTED, needs
on-device confirmation.**

On-device retest after the chrome-strip fix above landed: the maintainer
still saw "existing drawn lines suddenly gain a new line leading to a
single point," now "particularly when hamburger menu is opened" and
"maybe related to color changes" — i.e. triggered by *interacting with
the menu* (e.g. picking a color), not just the tap that opens it.

**Confirmed first: `StrokeBuffer:repaintTo` cannot be the mechanism.**
It iterates `self.strokes` and calls `s:paintTo(bb, override)` on each
independently — no code path connects two separate strokes together
during a repaint. So "existing lines gain a connecting line" has to mean
one single stroke has a genuinely bad point appended to its own data,
which then gets drawn (crossing visually through other strokes on the
page, creating the appearance of multiple lines all connecting to one
point) whenever that stroke is next repainted (e.g. by the dark-mode/
color-pick repaint, or the menu's own screen refresh) — not a rendering
bug, a **data** bug.

**Root cause: `_pollPen` (and `_pollTouch`) never pause while a
canvas-owned dialog is on top of the canvas.** Both read directly from
the input device via FFI, independent of which KOReader widget currently
has UI focus — unlike gesture-based taps (`onDrawStroke`/`onMenuTap`/
etc.), which KOReader's own gesture detector correctly routes to the
topmost widget. So tapping a button *inside* an open dialog (the
hamburger menu, the quick menu, a color swatch, a SpinWidget) is a real
physical screen touch that `_pollPen`'s scheduled poll loop still reads
and feeds into `self._stroke_buf`/`self._bb` as if it were a draw point
on the canvas underneath — exactly explaining "particularly when the
menu is open" (any interaction with it involves touching the screen) and
"maybe related to color changes" (picking a color is precisely such a
touch). The earlier chrome-strip fix only closed the gap for the
*opening* tap on the hamburger icon itself (a narrower, real, still-valid
instance of the same category); it did nothing for touches on the
dialog's own contents once it's already open.

**Fix: a single `self._dialog_open` suspend flag, checked at the top of
`_pollPen`/`_pollTouch`.** While true, raw pen/touch events are not
processed as drawing/erasing input (any already-open stroke is
defensively closed the same way the chrome-strip fix does, so resuming
after the dialog closes starts fresh). Set true right before every
canvas-owned dialog's `UIManager:show(...)`; set false reliably on close
regardless of *how* it closes (a specific button, tap-outside, back key)
by hooking each dialog's own universal close lifecycle rather than each
button individually:

- **`InfoMessage`** already fires `dismiss_callback` from its own
  `onCloseWidget` on every close path — add the flag-clear call inside
  the existing `dismiss_callback` (or add one where none existed).
- **`SpinWidget`** already fires `close_callback` from its own
  `onCloseWidget` the same way — add `close_callback = function() self:_dialogClosed() end`.
- **`ButtonDialogTitle`/`ButtonDialog`** (same class, the latter is
  re-exported as the former) has its **own** `onCloseWidget` that fires a
  `"flashui"` refresh on close — there is no `close_callback`-style hook
  to compose with. Directly overriding `onCloseWidget` in the instance's
  constructor table would **shadow and lose that refresh**, a real (if
  minor) visual regression. Fix: override it but call the base
  implementation from inside:
  ```lua
  onCloseWidget = function(dialog_self)
      self:_dialogClosed()
      ButtonDialogTitle.onCloseWidget(dialog_self)
  end,
  ```

Dialog call sites needing the flag (`grep -n "UIManager:show(" drawingcanvas.lua`):
`onMenuTap`'s `menu`; the hamburger menu's own "Contact Sensitivity"
`SpinWidget`; `_showQuickMenu`'s `self._quick_menu` and its own
"Contact Sensitivity" `SpinWidget`; `onPageNumberTap`'s "Go to page"
`SpinWidget`; `_runColorSelfTest`'s `InfoMessage`;
`_confirmSelfTestDismiss`'s `dialog`; `_confirmClearPage`'s `confirm`;
Bug 2's "two blank pages" `InfoMessage`. The proactive color-rendering-off
`InfoMessage` shown once at `init()` is lower priority (fires before the
user has typically started interacting) but cheap to cover too, for
consistency.

**Scope note:** this guard only applies to `_pollPen`/`_pollTouch` (the
raw FFI paths) — the gesture handlers (`onDrawStroke`/`onMenuTap`/etc.)
don't need it, since KOReader's own gesture detector already routes taps
to the topmost widget correctly; that's *why* this bug is specific to the
raw input paths and doesn't affect finger-draw-via-gesture at all. Not
unit-testable (FFI + widget lifecycle glue) — validate on device:
draw something, open the hamburger menu, pick a different color, confirm
no spurious line appears; repeat via the quick menu and the page picker.

---

## Bug 2: stop auto-advancing after 2 consecutive empty pages

**Status: IMPLEMENTED, needs on-device confirmation.**

**Ask:** pressing "next page" repeatedly (e.g. accidental physical button
mashing) currently creates blank page after blank page with no limit.
Want it to stop after 2 empty pages in a row, "without adding a ton of
complexity."

**What shipped (design refined from the original proposal below during
implementation):** a running numeric streak counter turned out to have a
real staleness bug — if the user draws something on the page that
triggered the block, a counter last updated at navigation time wouldn't
know that, and would keep blocking even though the current page is no
longer blank. Switched to two booleans instead, both evaluated live at
each navigation attempt:

- New pure function in `lib/canvas_utils.lua`, spec-first (4 cases):
  `canvas_utils.should_block_forward_nav(prev_page_was_blank,
  current_page_is_blank)` → `prev_page_was_blank and current_page_is_blank`.
- `DrawingCanvas` gains `self._prev_page_was_blank` (instance state,
  nil/false initially).
- `_navigatePage(delta)`, forward case: compute `current_page_is_blank =
  #self._stroke_buf.strokes == 0` fresh (reflects any drawing done since
  arriving); if `should_block_forward_nav(self._prev_page_was_blank,
  current_page_is_blank)`, show an `InfoMessage` and return without
  calling `on_page_forward`/creating a page. Otherwise set
  `self._prev_page_was_blank = current_page_is_blank` (capturing the
  outgoing page's state at the moment of leaving) and proceed.
- Backward navigation always sets `self._prev_page_was_blank = false` —
  reviewing older pages isn't the "accidentally went too far forward"
  scenario this guards against.
- No new config flag for the threshold — hardcoded as the boolean-AND of
  two consecutive pages, matching "without a ton of complexity."
- No override gesture — if the user wants a 3rd blank page, drawing
  something (even a small mark) on the current blank page immediately
  un-blocks the next forward press, or the notebook browser can add pages
  directly.
- `busted spec/`: 267/0 (4 new cases). Needs on-device confirmation: two
  blank-page forward presses show the message and don't create a 3rd
  page; drawing on the blocking page then pressing forward again works
  normally; backward navigation is never blocked.

---

## Ask 1: page picker — tap the page-number readout, type a page to jump to

**Status: IMPLEMENTED, needs on-device confirmation.**

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

**What shipped:** matches the proposed design above, with
`_navigatePage`'s common tail extracted into a shared
`_applyPageNavigation(new_idx, new_count, new_path)` used by both
`_navigatePage` (±1) and the new `_navigateToPage(idx)` (arbitrary jump).
`_navigateToPage` no-ops if `idx == self.page_index` and always clears
the Bug-2 blank-streak guard (`self._prev_page_was_blank = false`),
matching backward navigation's treatment — a deliberate jump isn't the
"accidentally over-advanced" scenario that guard exists for.
`on_page_jump` in `main.lua` clamps to `[1, nb:pageCount()]` (defensive —
the `SpinWidget`'s own `value_min`/`value_max` already constrain the
input) and deliberately does **not** extend the notebook the way
`on_page_forward` does; the picker only jumps within existing pages.
`busted spec/`: unchanged at 267/0 (all new code is widget/gesture glue
and a `main.lua` callback — not unit-tested per this repo's convention).
Needs on-device confirmation: tapping the page-number readout opens the
picker; entering a page number jumps there; the notebook auto-saves
before jumping (via `_autoSave()`, same as `_navigatePage`); rotation
doesn't misplace the tap zone.

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

## Ask 3: auto-toggle `live_color_refresh` from color/dark-mode choices

**Status: IMPLEMENTED, needs on-device confirmation. All five items in
this plan are now implemented.**

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

**What shipped:** matches the proposed design. Rather than a
`_makeColorButton` closure factory, extracted the common side effect
(not the button-building) into a shared `DrawingCanvas:_selectColor(hex)`
method — sets `self._current_color`, fires `on_color_change`, and calls
`canvas_utils.auto_live_color_refresh(hex, self._dark_mode)` — called
from both `color_btn` callbacks after their respective close logic, and
from `_toggleDarkMode` after `self._dark_mode` flips. This keeps the two
menus' differing close mechanisms (a local `close()` closure vs.
`self._quick_menu`) untouched while guaranteeing the auto-toggle rule
can't drift between the two color pickers. `fastnote.conf.example`'s
`live_color_refresh` doc comment updated to describe the auto-toggle and
clarify the config value is only the canvas-open starting state. `busted
spec/`: 271/0 (4 new cases). Needs on-device confirmation: picking a
non-black color turns on live color ink; picking black turns it off;
entering dark mode turns it off regardless of the selected color; the
manual hamburger-menu toggle still works as an override afterward.

**Documentation note requested by the maintainer — done:** confirmed on
device — painting in dark mode with a color (e.g. blue), with
`live_color_refresh` off, then switching to light mode, correctly shows
the true stored color. This is the existing dark-mode-is-a-display-only-
transform design (`.agents/notes/stroke-color-invariant.md`,
`_rebuildDisplayFromStrokes`'s `override = self._dark_mode and
Blitbuffer.COLOR_WHITE or nil`) working as intended, now that the
`paintRectRGB32` fix means color actually reaches the screen at all. A
"Confirmed on device (2026-07)" section was added to
`stroke-color-invariant.md` recording this.
