# Handoff: spurious "vertex line" bug (still open) + round status

**Status: OPEN, unresolved after three fix attempts, but two more
concrete real gaps were fixed in Round 4 (see bottom of this doc). Written
for continuity across a chat compression — self-contained, read this
first. The body below (Rounds 1-3) is kept as-written for the evidence
trail; read the "Round 4" section at the end for current state.**

Branch: `claude/pencil-color-drawing-perf-3jztxr` (PR #12). All work
described below is committed and pushed. `busted spec/` (run from
`plugins/fastnote.koplugin/`) is green throughout — every fix in this
round touches FFI/widget/gesture glue with no unit-testable pure-function
surface, so "tests pass" only confirms no syntax/regression damage, not
correctness. Everything here needs on-device confirmation.

---

## Quick orientation: what this round was

Starting point: the long-running "no color ever renders" investigation
(separate handoff docs, now closed — see `.agents/plans/
grayscale-ink-and-eraser-handoff.md` and `.agents/notes/
waveform-refresh-research.md`'s "paintRect vs. paintRectRGB32" section)
found and fixed the actual root cause: `BlitBuffer:paintRect` silently
discards color, and the plugin's own drawing code was calling it instead
of `paintRectRGB32`. **Color now works, confirmed on device.**

With color working, the maintainer requested a batch of follow-ups,
tracked in `.agents/plans/post-color-fix-followups.md`:

1. Finger-draw + hamburger-tap spurious line ("vertex" bug) — **the
   subject of this doc, still open**
2. Stop forward page navigation after 2 consecutive blank pages
3. Page picker (tap "n / N" to jump to a page)
4. Pen side button opens the quick menu (colors + sensitivity)
5. Auto-toggle `live_color_refresh` from color picks / dark mode

## Confirmed working on device (maintainer's own words)

- **Ask 5 (auto color-mode switching): works.**
- **Item 2 (page-turning stopped after blanks): works, "great!"**
- **Item 3 (page jumping): works, "so that's great too!"**

No further action needed on these three unless new issues surface.
`fastnote.conf.example`, `.agents/notes/stroke-color-invariant.md`, and
the plan doc were all updated alongside the code — see git log on the
branch for the individual commits (one per item, all titled clearly).

**Item 4 (side button → quick menu) has not been explicitly confirmed or
denied by the maintainer in the messages covering this round** — worth
asking about specifically, since it's a plausible (if unconfirmed)
contributor to the bug below if the maintainer has been using it.

## Still open: the "vertex line" bug

### Symptom (current wording, most recent report)

Existing drawn lines/letters spontaneously gain an extra line segment
running to a single common point — originally described as being at
"the edge of the screen," most recently as "the lower left 'origin'."
The extra segment makes it look like multiple separate strokes are all
"attached" to one point, though (see Analysis below) that's very likely
a visual illusion, not literal shared geometry.

### Evidence timeline (read in order — each round's fix address real,
### confirmed findings, but evidently not the whole bug)

**Round 1 (original report):** "when I 'finger draw' then click on the
hamburger menu icon, all the existing lines get a line connecting the
edges to a single point at the edge of the screen." Root cause found:
`onDrawStroke`'s chrome-strip early return (`if y < CHROME_HEIGHT then
return end`) didn't close the in-progress stroke, unlike the raw-pen
path's equivalent check. `onDrawStrokeEnd` doesn't check `CHROME_HEIGHT`
at all, so a gesture release inside the chrome strip (e.g. a hamburger
tap that also registers as a trivial pan+pan_release — common touchscreen
jitter) drew a final segment from the stroke's stale last point to
wherever the gesture ended. **Fixed**: chrome-strip early return now
closes the stroke first (`drawingcanvas.lua`, `onDrawStroke`, commit
`49b345d`). Maintainer confirmed page-turning and color-mode fixes
worked, but reported the vertex bug **still happening**.

**Round 2 (re-investigation):** Confirmed structurally that
`StrokeBuffer:repaintTo` (`lib/strokebuffer.lua`) **cannot** be the
mechanism — it paints each committed stroke independently
(`s:paintTo(bb, override)` per stroke, in a plain loop); there is no code
path that connects two separate strokes' geometry together during a
repaint. So the bug is not a rendering artifact of existing data; it has
to be a genuinely new bad paint operation happening somewhere.
Hypothesis at the time: `_pollPen`/`_pollTouch` (raw FFI input, reads the
device directly, independent of which KOReader widget has UI focus) never
paused while a canvas-owned dialog (hamburger menu, quick menu, self-test,
any `SpinWidget`, etc.) was on top — so a physical tap on a button
*inside* an open dialog was still being read as a draw/erase point on the
canvas underneath. **Fixed**: a `self._dialog_open` flag, checked at the
top of `_pollPen`'s and `_pollTouch`'s draw-handling branches, toggled via
`_dialogOpened()`/`_dialogClosed()` wired to every dialog's own close
lifecycle (commit `0f0d1db`, see that commit message for the full list of
~9 dialog call sites covered, and the `ButtonDialogTitle`-vs-`InfoMessage`-
vs-`SpinWidget` hook mechanics). This was real, verified-correct
engineering — but per the maintainer's next report, **still not the whole
bug**.

**Round 3 (current — latest evidence, most specific yet):**

> "vertex issue is still a problem -- as best I can tell, it seems like
> it's switching between experimental mode or otherwise through the
> hamburger menu may be causing the problem to trigger? I started out
> drawing in 'black' and when I switched to color, the black letters I'd
> drawn all got 'vertex lines' to the lower left 'origin'. switching
> between different colors, the color text was unaffected. switching
> black to 'black' didn't seem to do anything at first... but switching
> back and forth again (perhaps triggered by menu opening, maybe not, hard
> to say) eventually all color and black text had the vertex lines
> 'attached'."

Key new facts, precisely:
1. Drew black text first (`live_color_refresh` off — the default).
2. Switched to a color via the hamburger menu. Ask 5's new auto-toggle
   (`canvas_utils.auto_live_color_refresh`, `drawingcanvas.lua`'s
   `_selectColor`) flips `self.live_color_refresh` from `false` to `true`
   on this exact action (first non-black pick). **The already-drawn black
   text got corrupted at this point.**
3. Switching between different (non-black) colors afterward: no further
   corruption ("color text was unaffected"). `live_color_refresh` stays
   `true` → `true` across these picks — no flip.
4. Switching back to black: flips `live_color_refresh` `true` → `false`.
   "Didn't seem to do anything at first."
5. Repeating black ↔ color switches: eventually **all** text (color and
   black) ended up with vertex lines.

### Analysis

**The correlation is with `live_color_refresh` *changing value*, not
with "any menu interaction" generically.** This reframes Round 2's fix:
that fix is very likely still correct and worth keeping, but it targeted
a different, also-real bug (raw input leaking through while a dialog is
open) than the one actually producing this specific, reproducible
pattern. The new evidence points somewhere in the "draw black, bloom
color" system (Task C2 — see `.agents/plans/
color-pipeline-diagnosis-and-fix.md` for its original design, and
`canvas_utils.live_ink_mode` / `_drawSegment` / `_liveColorRefresh` /
`_flushLiveRefresh` / `self._display_diverged` / the tighten pass in
`drawingcanvas.lua`), which is now being exercised in a way it never was
before this round: **`live_color_refresh` used to be effectively static
for a whole session** (set once at canvas-open from config, or rarely
hand-toggled once via the hamburger menu's own manual row). Ask 5 makes
it flip on *every color pick*, which is new, routine, repeated, mid-
session territory this flag's surrounding code was never exercised
against.

**Important structural fact, confirmed by reading `lib/strokebuffer.lua`
directly:** `penDown`/`penMove`/`penUp` only ever touch `self.current`
(the single, currently in-progress stroke). Once a stroke is committed
into `self.strokes` via `penUp`, **nothing in this codebase ever mutates
it again.** So "existing lines gain a connecting line" cannot mean an old
`Stroke.pts` array is being edited — it has to mean either (a) a brand
new, small, spurious stroke is being committed whose start point happens
to coincide with (or is very close to) an old stroke's endpoint, visually
reading as "attached," or (b) a stray paint operation lands directly in
`self._bb` without ever going through `StrokeBuffer` at all (in which
case it would persist visually until the next full repaint, but not be
present in the saved SVG — genuinely worth checking: does the corruption
survive closing and reopening the page? Nobody has checked this yet).

**A concrete, verified, NOT-yet-fixed gap found while preparing this
handoff:** `onDrawStroke`/`onDrawStrokeEnd` (the finger-draw gesture
path) never received the `self._dialog_open` guard that Round 2 added to
`_pollPen`/`_pollTouch`. Confirmed by reading the current code — no
`_dialog_open` check exists in either function as of this commit. If
`finger_draw` is enabled, this path is *still* exposed to exactly the
Round-2-diagnosed failure mode (a tap on a dialog's own contents
misread as a draw gesture on the canvas underneath) — and unlike the
original hamburger-*icon* tap (caught by the existing `y < CHROME_HEIGHT`
check), a tap on a **color swatch inside the open menu** is nowhere near
the chrome strip (`ButtonDialogTitle` dialogs render centered on screen),
so the existing chrome-strip guard in `onDrawStroke` would not catch it
either. This is consistent with corruption being tied to *interacting
with the menu's color buttons specifically* — exactly the new evidence.
**This is the leading hypothesis and the most concrete, actionable next
step**, but it has NOT been implemented or tested — the maintainer asked
for a handoff doc instead of another live fix attempt at this point in
the conversation, so no code was changed for this finding.

**Open question that would help disambiguate:** is `finger_draw` actually
enabled on the maintainer's device right now? If off, `onDrawStroke`/
`onDrawStrokeEnd` return immediately on every call and can't be the
cause — the gap above would be a real but *inactive* bug, and the actual
mechanism would have to be something else entirely (worth re-examining
`_liveColorRefresh`/`_flushLiveRefresh`'s `self._live_pending_rect` /
`self._live_refresh_last` state for staleness across a `live_color_refresh`
value flip — half-formed hypothesis, not yet investigated in code, flagged
here only as the next place to look if the gesture-path theory doesn't
pan out).

### Recommended next steps, in order

1. **Ask the maintainer:** is `finger_draw` on or off? Does the
   corruption survive closing and reopening the notebook page (tests
   whether it's in the saved SVG data or purely a display-buffer
   artifact)? Is item 4 (side button → quick menu) being used, and could
   *that* have been the interaction in play rather than the hamburger
   menu specifically?
2. If `finger_draw` is on: extend the exact same `_dialog_open` guard
   pattern from `_pollPen`/`_pollTouch` (see commit `0f0d1db`) to
   `onDrawStroke` and `onDrawStrokeEnd`. This is a small, well-understood
   change following an already-established pattern — should be quick.
3. If that doesn't fully resolve it (or `finger_draw` is off): capture
   ground truth instead of theorizing further. `debug_input_log` is fully
   wired (ADR-006, confirmed working end-to-end this session) — enable it
   (Tools → More tools → Developer options → "Enable debug logging" +
   "Enable verbose debug logging", **then restart KOReader** — the
   restart is required, see the gotcha section in `.agents/notes/
   waveform-refresh-research.md`), then reproduce: draw black text, open
   the hamburger menu, tap a color. Pull `<datadir>/fastnote/input.log`
   (the plugin's own RAW+DEC event log, distinct from `crash.log`) and
   look for what raw events arrive during the color-tap, and whether a
   `DEC down`/`DEC move` pair with an unexpected `x`/`y` appears right
   around the color selection.
4. Consider instrumenting `_drawSegment` and/or `StrokeBuffer:penDown`
   with a temporary `logger.dbg` breadcrumb printing `x0,y0,x1,y1` (or
   inspecting the saved SVG's raw point data for the corrupted stroke)
   the next time corruption is caught fresh, to nail down definitively
   whether it's a new spurious stroke (per the structural analysis above,
   the most likely explanation) versus something else not yet considered.

### Files most relevant to this investigation

- `plugins/fastnote.koplugin/drawingcanvas.lua` — `onDrawStroke`,
  `onDrawStrokeEnd`, `_pollPen`, `_pollTouch`, `_dialogOpened`/
  `_dialogClosed`, `_selectColor`, `_drawSegment`, `_liveColorRefresh`,
  `_flushLiveRefresh`, `_scheduleTighten`, `_rebuildDisplayFromStrokes`.
- `plugins/fastnote.koplugin/lib/canvas_utils.lua` —
  `live_ink_mode`, `auto_live_color_refresh`, `drawLine`.
- `plugins/fastnote.koplugin/lib/strokebuffer.lua` — confirms
  `repaintTo` cannot connect strokes; `penDown`/`penMove`/`penUp` only
  ever touch `.current`.
- `.agents/plans/post-color-fix-followups.md` — the full plan doc for
  this round; has a "Bug 1 revisited" section with Round 2's write-up in
  more detail than summarized here.

---

## Required reading for whoever picks this up

In order:

1. This file (you just read it).
2. `plugins/fastnote.koplugin/AGENTS.md` (repo root `AGENTS.md` routes
   here) — plugin architecture, invariants, file map.
3. `.agents/plans/post-color-fix-followups.md` — full detail on all 5
   items this round, including the "Bug 1 revisited" write-up.
4. `.agents/notes/input-path-architecture.md` — gesture vs. raw-evdev
   paths, why both exist (ADR-003).
5. `.agents/notes/stroke-color-invariant.md` — the dark-mode/color
   storage invariant, now with a confirmed-on-device addendum.
6. Only if pursuing the `live_color_refresh`-toggle hypothesis:
   `.agents/plans/color-pipeline-diagnosis-and-fix.md` — Task C2's
   original "draw black, bloom color" design.

## Current branch state (as of Round 3 / original writing)

`claude/pencil-color-drawing-perf-3jztxr`, all commits pushed. Recent
commits, newest first: `0f0d1db` (dialog-suspend fix, Round 2 of this
bug), `0e2b999` (Ask 5, auto color-toggle), `1ed0306` (page picker),
`cf44a28` (blank-page nav guard), `249fe7d` (side-button quick menu),
`49b345d` (Round 1 of this bug, chrome-strip stroke-close),
`9e7d8b1` (the `paintRectRGB32` color fix that closed out the prior
investigation). `busted spec/`: 271 successes / 0 failures.

---

## Round 4 (2026-07): two more real gaps fixed; corner-glitch hypothesis instrumented

Picking this up after the above was written: re-read `drawingcanvas.lua`,
`lib/strokebuffer.lua`, `lib/pen_statemachine.lua`, and `input/pendev.lua`
end to end looking specifically for what could produce a line to a fixed
"lower left origin" point, tied to `live_color_refresh` changing value.

**Found and fixed gap 1 — the "leading hypothesis" from the original
writeup above was correct and is now fixed.** `onDrawStroke`/
`onDrawStrokeEnd` now check `self._dialog_open` and return immediately,
exactly the change flagged above as "the most concrete, actionable next
step." Confirmed via code reading that the `DrawStroke`/`DrawStrokeEnd`
gesture zone really is `range = self.dimen` (whole canvas) and really
isn't gated by dialog stacking — KOReader's gesture detector routing
assumption from Round 2's "Scope note" doesn't hold for this specific
`ges_events` registration.

**Found and fixed gap 2 — new, not previously identified.**
`_dialogOpened()` set `self._dialog_open = true` but did nothing else;
the actual clearing of `_last_pen_x`/`_last_pen_y` happened *reactively*,
inside `_pollPen`'s own `down`/`move` branch, only when a pen event
arrived *while* the dialog was open. If the user's interaction with the
dialog doesn't involve the pen at all — the common case: pen was last
down mid-letter or just-lifted, then the user taps a menu button with a
**finger** — no pen event ever arrives during the dialog's lifetime to
trigger that reactive clear. `_last_pen_x`/`_last_pen_y` (correctly
pointing at wherever the pen last was — the end of the last letter
written) stay stale. The very next real pen-down, once the dialog closes
and writing resumes, sees `self._last_pen_x` non-nil and draws
`_drawSegment(stale_last_x, stale_last_y, new_x, new_y, lw)` — a real
line painted straight into `_bb`, connecting the end of the *previous*
letter to the start of the *next* one, **never recorded in
StrokeBuffer** (matches structural-analysis option (b) from the original
writeup above almost exactly: a stray paint operation bypassing
StrokeBuffer). Fixed by making `_dialogOpened()` itself eagerly close any
open stroke and clear all pen/touch/gesture tracking fields
synchronously, rather than waiting for a poll event that may never come.

**Not fixed, deliberately — a third, still-unconfirmed hypothesis.** The
"lower left origin" wording doesn't obviously follow from either gap
above (both would connect to wherever the pen/gesture *actually* was, not
to a fixed corner). `_digToScreen`'s existing `[0,1]` clamp — present
"in case of out-of-range values during fast movement" per its own comment
— maps a digitizer reading of `(nx=0, ny=0)` to screen point `(0, H-1)`
under `rotation_mode = 3` (this device's recommended default): the
bottom-left corner. A Wacom EMR proximity-in glitch reporting garbage/
zero coordinates on the first sample of a fresh contact is a known class
of hardware quirk, and would produce a genuine new short spurious stroke
(consistent with the "committed strokes are never mutated" structural
finding), correlated with menu use only because lifting-and-resetting the
pen around a menu interaction is exactly when such a glitch is most
likely — not because of `live_color_refresh` or dialogs per se. This
wasn't shipped as a fix because a coordinate-rejection heuristic without
confirming evidence risks silently rejecting legitimate strokes that
start near a screen edge — a worse failure mode than the bug itself.
Instead, the existing "FastNote pen down" `logger.dbg` line
(`_pollPen`, `drawingcanvas.lua`) now also logs raw `x`/`y`, computed
screen `sx`/`sy`, `raw_at_bound` (true if the raw reading is at the
digitizer's calibrated axis min/max — the glitch signature), and
`stale_last` (true if `_last_pen_x` was non-nil going into this down —
would indicate gap 2 above is *still* firing somehow even after the fix).

**If the bug recurs after this round:** enable `debug_input_log` (Tools →
More tools → Developer options → both debug-logging toggles, **then
restart KOReader** — see the restart gotcha in `.agents/notes/
waveform-refresh-research.md`), reproduce, and grep
`fastnote/input.log` for "FastNote pen down" lines around the corruption.
`raw_at_bound=true` confirms the corner-glitch hypothesis (next step:
reject/debounce a down sample at the calibrated boundary, carefully, with
a device test for genuine edge-of-screen strokes). `stale_last=true`
means gaps 1/2 above didn't fully close — re-check for a third code path
that reads/writes `_last_pen_x` without a `_dialog_open` check (grep
`_last_pen_x` in `drawingcanvas.lua`). Neither flag set means the
mechanism is something not yet considered — fall back to instrumenting
`Stroke:addPoint`/`StrokeBuffer:penDown` directly (recommended next step
4 from the original writeup above).

`busted spec/`: 271/0, unchanged (no `lib/` code touched this round).

### Current branch state (Round 4)

Branch `claude/pencil-color-drawing-perf-3jztxr`. Round 4's changes are
in `drawingcanvas.lua` only: `_dialogOpened()`'s eager reset, the
`_dialog_open` guard in `onDrawStroke`/`onDrawStrokeEnd`, and the
extended pen-down debug log line. Not yet committed as of this doc
update — see git log on the branch for the actual commit once pushed.
