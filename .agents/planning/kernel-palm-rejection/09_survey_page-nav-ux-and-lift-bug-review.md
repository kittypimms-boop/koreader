# Page navigation UX/UI plan and finger-lift jump review

**Date:** 2026-11-20

Condensed from the Opus planner's report on one-tap page navigation and the finger-lift jump. Line numbers in the planner's report are against repo HEAD `62174e7dd`; the working branch is about five lines further along after the proximity fixes. I have not re-checked its citations except the ones noted as confirmed.

## Verdict

1. My analysis blamed `ges.pos` too narrowly. On the Kobo with `finger_draw` on, up to three input paths write into one shared `self._stroke_buf.current`: the gesture path, the raw touch path and the pen state machine path. Most likely a non-gesture path appends points to, or commits, the finger's stroke.
2. A raw (0,0) reading cannot produce a "central point": every zero or garbage coordinate maps to a screen corner, under KOReader's hook and under the plugin's own digitizer mapping alike. The one mechanism that points toward the middle is the raw touch path drawing untranslated digitizer coordinates, which is a 90 degree rotation about a point near the screen centre.
3. Ignoring `ges.pos` in `onDrawStrokeEnd` is safe (it loses at most one frame of travel) but fixes only one hypothesis.
4. Fix the shared-buffer design first with an owner tag on the stroke buffer, then stop feeding finger touch events into the pen state machine on the combo chip, and instrument before shipping either.
5. Page navigation: prev/next tap zones on each side of the page number, which still opens the jump dialog. A pure `lib/page_nav.lua` plus small canvas changes. Page turns should repaint with a partial refresh, not a full one, and must reset per-stroke state.

## Page navigation

**UX versus UI.** UX is the user's goal and what can go wrong: flip one page while writing without losing concentration, with a paper-notebook model (left back, right forward, the number is "where am I / jump"), plus edge cases (page 1, the last page, blank pages, a turn mid-stroke, a failed save, rapid taps, lost undo). UI is what is drawn and where you tap: zone geometry, glyphs, disabled look, waveform, feedback, landscape and right-to-left layout. They interlock: "next on the last page creates a page" needs a "+" cue, "a mistap must be cheap" sets dead gutters beside the exit button, and "casual" rules out a full flash on every turn.

**Facts in the code.** The chrome strip is 75 px tall (6.35 mm at 300 dpi), exit and menu are 80 px wide each, and the page-number tap zone spans the whole middle and opens a spin dialog. Hardware page keys already call the navigation function with plus or minus one. Forward navigation past the end creates a page, and is blocked after two blank pages. Double-tap is disabled, so taps fire on lift. Tap-bounce is off by default.

**Candidates.** A: prev and next zones either side of a fixed-width number zone, number still opens the jump dialog (recommended). B: left and right halves of the middle with no glyphs (fallback). C: long-press the number for the dialog, tap for next (hold takes 500 ms, not discoverable, no back). D: swipe in the chrome (the strip is too short and fights the drawing guard). E: hardware buttons only (today).

**Targets.** 300 dpi is 11.81 px per mm. The strip is below a comfortable 9 mm minimum, and hit-slop cannot extend downward because taps there become ink. Proposed: a number zone 300 px wide, 40 px dead gutters beside exit and menu, and the arrows take the rest (about 372 px each in portrait, about 580 px in landscape). Growing the strip to 106 px (9 mm) would hide ink already drawn in that band; that is a user decision.

**Never leave ink from a chrome tap.** The pen raw path and the gesture path already guard the chrome; the raw touch path has no chrome guard and does not translate coordinates. All chrome handlers must return true, including disabled taps, and the zone ranges must be disjoint.

**Boundaries.** Page 1: the back arrow is drawn grey and a tap does nothing. Last page with ink: the forward arrow becomes "+" and creates a page, with no confirmation. Last page blank: draw "+" disabled (simpler than today's "one blank page then blocked"; open question).

**Save before switching.** The autosave has no error handling, and navigation continues even if the save fails, after which the page is lost: make it return a status and abort the turn on failure. Separately, a page erased to empty is never saved, so the old strokes come back after a round trip; fix that in its own commit.

**Undo.** Undo history ends at a page boundary (ADR-005), and one-tap flipping will lose it more often. Keep the ADR and note the consequence, or revisit it (open question).

**Rapid taps:** queue them; do not coalesce. Coalescing creates a window where the number shows page N+2 while the content is still N and ink lands on the wrong page.

**Turning mid-stroke.** The page-turn function resets none of the per-stroke tracking, so the first point on the new page connects to the old page's last point, and the old page's tighten timer fires on the new page. Fix: share one reset helper with the dialog-open path and call it, plus the tighten cancel, at the start of the page turn.

**Waveform.** A turn currently calls a full refresh twice. Use one partial refresh (GLRC16 with dithering: no flash, ghosting cleared, colour kept); KOReader still promotes every sixth partial to a full refresh. Keep the mode a single constant so it can be tuned on the device. Do not use the fast or A2 modes for content (colour would be lost).

**Feedback and indicator.** The number change is the feedback; no pressed-state flash. Keep "3 / 12" but measure its real width instead of assuming 13 px per character, and pass new strings through gettext (the canvas has none yet; one handler parameter named `_` shadows it and must be renamed `__`). When the UI is mirrored for right-to-left, swap the prev and next zones; hardware keys stay as they are.

**Wireframe (portrait, 1264 px):** `| x |gut| < (prev ~372) | 3 / 12 (300) | (next ~372) > |gut| menu |`. On the last page the right arrow becomes "+"; on page 1 the left arrow is grey. Landscape widens the arrow zones to about 580 px each.

**Implementation plan (test-first).** A new pure `lib/page_nav.lua` with specs: `chrome_layout` (disjoint zones, minimum target width, fixed number zone, gutters, mirrored swap, degrade to number-only on narrow widths), `hit_test` (gutters give nil, half-open bounds, below the chrome gives nil), `arrow_state` (page 1 disables back, middle page next, last page with ink create, last page blank disabled), and `format_indicator` (clamped). Canvas changes: constants, the two new tap zones, handlers, paint, zone updates on rotation, and the page-turn reset and refresh mode, plus save-failure handling. `main.lua` and the notebook model stay unchanged. Commits: spec and lib; state reset, tighten cancel and refresh mode (this also fixes the hardware-key path); zones, handlers and paint; docs. The empty-page save fix is its own commit. Busted covers `lib/`; the emulator covers zones, rotation, glyphs and the guards; the device is needed for GLRC16 versus flash, the feel of taps on the strip, the raw-path chrome guard and the hardware keys.

**Risks.** The 6.35 mm strip height is the binding constraint. GLRC16 ghosting on dense pages. Noticed but out of scope: new page files are named by page count and can collide after a delete, and meta-write failures are not handled.

## Finger-lift jump

**Structural fact.** The stroke buffer has one `current` shared by the pen poll, the touch poll and the gesture handlers. Any path's move extends another path's stroke and any path's up commits it. The ADR claim that the paths are mutually exclusive does not hold on the Kobo with `finger_draw` on.

**Hypotheses, ranked.**
- **H-A (high): finger events corrupt the pen path.** Until the first pen tool-type event of the session, finger `BTN_TOUCH` passes into the pen state machine, and legacy `ABS_X/Y/PRESSURE` (if the chip emits pointer emulation, unverified) always passes. The state machine then emits moves, the pen poll draws them into the shared stroke without a pressure check, and at the finger lift `BTN_TOUCH=0` produces an up that commits the gesture's stroke. The point added is the digitizer mapping of the raw values, which with unset values is the lower-left corner. A second variant, pen lift with the pressure drop and the slot release in the same frame, is closed by the proximity fix. Signature: the end point is a corner or the last pen position, the bad geometry is saved, and the log shows pen-tool down or move events while drawing with a finger.
- **H-B (high if the touch device is open, otherwise impossible): the raw touch path draws untranslated coordinates.** It applies no axis swap or mirror and has no chrome guard, which is a 90 degree rotation about a point near the screen centre. Its down replaces the gesture's open stroke and its moves interleave rotated points. Ranked below H-A because, if live, ink in the lower part of the page would also show a visible rotated ghost copy. Risk in my branch: fixing proximity makes this path live more often.
- **H-C (medium): the final gesture segment goes to a bogus lift-frame position (my original theory).** KOReader writes legacy `ABS_X/ABS_Y` into the current slot, and pointer emulation reports the oldest remaining contact, so a lifting slot can inherit another contact's coordinates. If H-A or H-B already committed the stroke, the move is display-only and the colour tighten rebuild about 2.5 s later erases it, which separates the cases.
- **H-D (low):** zero or garbage digitizer values give edges or corners, never the centre.
- **H-E (low for this symptom):** stale tracking after a page turn or rotation.

**Not sources of a lift point:** the touch and pen `up` handlers add no point, the dirty-rect math only widens a refresh rectangle, and menu and tap handlers add none. Also noticed: with `finger_draw` on, pen contacts also produce KOReader pan gestures, so pen strokes are processed by both the raw path and the gesture path.

**Is ignoring `ges.pos` correct?** Yes for the gesture path (the lift frame normally carries no new position; at most about 1 to 2 mm is lost). If dropped, also drop the bounding-box expansion. Better: keep the release point only if it is inside the drawable area and within about 24 px of the last point, otherwise drop it and log a JUMP line, which doubles as the evidence collector. It does not fix H-A or H-B.

**On-device capture.** The current log has raw lines for every event on the pen device (which, if the nodes are shared, includes finger slots) and decoded pen events. It lacks gesture events, touch device events, palm decisions, stroke buffer operations, and usable timestamps (seconds only, with synchronous writes). Add: gesture lines, touch lines, stroke-buffer trace lines with an owner tag and a JUMP line when consecutive points are more than about 120 px apart, millisecond timestamps, an in-memory ring of the last 3 raw frames dumped on every pan release and every jump, and one-off lines at canvas open (touch and pen device paths and whether they share a node, axis ranges, whether the legacy axis bit is advertised, every change of the has-pen flag). What proves what: pen-tool down or move while drawing with a finger proves H-A; touch lines plus a stroke-buffer down with owner touch partway through a gesture stroke proves H-B; a pan release whose position differs from the previous pan, with a legacy `ABS_X` in the last raw frame, proves H-C.

**Test plan.** Stroke buffer owner tag (moves and ups from a different owner are no-ops; an unset owner matches anything, so existing specs stay green); pure `release_point` and `is_jump` helpers in the canvas utilities; a pure rule for when legacy single-touch events are allowed (not when the device advertises the tool-type axis, so the combo chip ignores them from the first event); a pure raw-touch-to-screen mapping with specs per rotation, if the touch device is kept. One more contract change: `release_pen` from a hover must emit an event that starts the palm blackout. (Done in the working branch after this report: the new "leave" event.)

## Questions for the user

1. When the bad line appears, does it stay? After about 3 seconds (the colour settle), or after leaving the page and coming back: still there or gone? Gone means display-only (H-C); still there means it is saved in the page (H-A or H-B).
2. Where exactly does it end: the screen centre, a corner (lower-left?), or where you last wrote with the pen? Does it happen before you have used the pen at all since opening the canvas?
3. Does KOReader's `crash.log` contain "FastNote canvas: touch + palm rejection enabled:" and with which input device? Do you ever see a faint rotated duplicate of your finger strokes?
4. May the top strip grow from about 6 mm to about 9 mm (anything drawn in that band would be hidden)? Should a forward tap on a blank last page do nothing, or keep the "one blank page allowed" rule?
5. One-tap flipping will drop undo history more often. Is that acceptable, or should each page keep its undo history across flips?
