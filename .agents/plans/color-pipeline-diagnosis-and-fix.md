# Plan: color pipeline diagnosis + fix (fastnote)

**Status: EXECUTED (C1/C2/C3 done); Phase D device results are in — the
investigation continues in `.agents/plans/grayscale-ink-and-eraser-handoff.md`
(key finding: all gates pass and Screen.bb is BBRGB32, so the grayscale
conversion is plugin-side, not a KOReader gate).**

> ## ⚠️ Correction (2026-07): every color symptom below was measured on grayscale pixels
>
> Until commit `9e7d8b1` (2026-07), `lib/canvas_utils.lua`'s `drawLine`
> painted through `BlitBuffer:paintRect`, which unconditionally calls
> `value:getColor8()` before writing any pixel — **even into a genuine
> `TYPE_BBRGB32` buffer**. Every stroke and every self-test bar in this
> plan was downconverted to luminance before the refresh layer ever saw
> it, so ink was grayscale regardless of waveform, gate state, or buffer
> type. (Different hues produce different luminance values, which is why
> the self-test showed *distinguishable* gray shades rather than one flat
> gray — that looked like partial color reaching the panel, and it was
> not.) The fix switched `drawLine` and `_runColorSelfTest`'s bar loop to
> `paintRectRGB32`.
>
> **This document is the sole written justification for
> `live_ink_style = "solid"`, and that justification rests on the
> artifact.** Specifically suspect:
>
> - **Root cause 3** — "A2 thresholds colored ink to sparse dots." A2 *is*
>   1-bit (that much is confirmed and survives), but what it was
>   thresholding was luminance-converted pixels, not colored ink. The
>   observed faint dotted line is not evidence about how A2 renders color.
> - **Task C2** in full — `live_ink_style`, the "draw black, bloom color"
>   design, its `"solid"` default, `canvas_utils.live_ink_mode()`, the
>   `_display_diverged` flag, and the tighten-time
>   `_rebuildDisplayFromStrokes()` call. All of it exists to hide a
>   symptom that may no longer exist. Do not treat the default as settled.
> - **Phase D steps 3, 4 and 5** — "bars gray → KOReader gate broken",
>   "still no color on the refresh", "muted live color". Each of those
>   outcomes was guaranteed by the paint bug, so the decision tree would
>   have sent a reader chasing gates that were fine. The steps are still
>   worth running; their *interpretations* need re-deriving post-fix.
>
> **What survives untouched** — real, independently caused, and never the
> reason color was missing: root cause 1 (stale deployment, confirmed from
> git history), root cause 2's underlying mechanism (the color gate chain
> and the 8bpp/CFA trap are real KOReader behavior), all of Task C1's
> tooling and gate logging, the C1 deviation note on
> `Screen:getHWNightmode()`, Task C3's two review findings, and every
> timing result — the ~300–500 ms per-segment GLRC16 cost and the
> mid-stroke pen lockout included.
>
> Re-validation is tracked in `.agents/planning/post-v1-roadmap-handoff.md`
> → **W0.5 — Re-validate the colour findings**. None of it can be settled
> off-device. Nothing below has been deleted: it is the record of what was
> tried, and the retraction trail is why the next person won't repeat it.

## What prompted this (device report, 2026-07)

On hardware (Kobo Libra Colour), drawing in light mode produces a **very
faint, dotted line**; the same stroke in dark mode looks solid; after
pen-up the stroke's region refreshes and gets "more visible" — but **no
ink color has ever appeared, with any picker color, live or after the
refresh**.

## Root-cause analysis (supervising session, 2026-07 — read before executing)

Three stacked causes, in order of certainty:

1. **The device is running stale code (CONFIRMED from git history).**
   `master` has not moved since PR #11. PR #12 was merged with the wrong
   base branch (`claude/review-agents-docs-E7gb0`, not `master`), so
   *none* of this session's work — and none of the pre-session fixes
   `acd89a1` (revert live drawing to A2) and `597d0aa` (tighten bbox +
   `self.dithered` widget flag) — is on `master`. A device deployed from
   `master` runs the **per-segment `"partial"`+dither live path** that
   `.agents/plans/color-drawing-fix-and-menu-access.md` documents as
   broken (300–500 ms per segment → fragmented/faint lines; counts toward
   UIManager flash promotion). The faint/chunky live line is explained by
   this alone. **Fix: land the current branch on `master` (PR base must
   be `master`) and redeploy the plugin to the device.**
2. **A KOReader-level color gate is probably off (LIKELY — device check
   required).** "Never color, not even once, not even after a
   GLRC16-class refresh" is the signature of the color gate chain being
   broken, not a waveform bug. See the "color gate chain and the 8bpp
   trap" section of `.agents/notes/waveform-refresh-research.md`: if the
   user ever turned *Screen → Color rendering* off, KOReader boots the
   framebuffer at **8bpp with CFA skipped** — grayscale everything,
   unfixable from plugin code. Task C1 builds the tooling to confirm or
   rule this out in one tap.
3. **A2 thresholds colored ink to sparse dots (CONFIRMED behavior of a
   1-bit waveform).** Once the device runs current code (A2 live +
   tighten), light-luminance ink will still draw as a faint dotted line
   live (solid color only appearing on the tighten). That's physics, but
   it's bad UX. Task C2 gives live strokes a solid appearance the way the
   stock Kobo notebook does.

   > **⚠️ Correction (2026-07) — this is the cause that did not survive.**
   > Until commit `9e7d8b1`, `canvas_utils.drawLine` painted via
   > `BlitBuffer:paintRect`, which calls `value:getColor8()` before writing
   > any pixel even into an RGB32 buffer — so what A2 was thresholding was
   > already luminance, never color. A2's 1-bit behavior is real and
   > stands; "A2 thresholds *colored* ink to sparse dots" was never
   > actually observed and remains unproven. Task C2 below is built
   > entirely on this premise. Re-validation: W0.5 in
   > `.agents/planning/post-v1-roadmap-handoff.md`.

## Required reading before touching code

1. `plugins/fastnote.koplugin/AGENTS.md` — entry point, invariants.
2. `.github/instructions/lua.instructions.md` — Lua rules.
3. `.github/instructions/eink-refresh.instructions.md` — refresh rules.
4. `.agents/notes/waveform-refresh-research.md` — especially the
   2026-07 "color gate chain" and "1-bit dither correction" sections.
5. `.github/skills/test-driven-development/SKILL.md` — spec-first for lib/.

## Ground rules for executing agents

- Work on the current branch. **No `git commit`, no `git push`, no PRs.**
  The supervising session reviews, commits, pushes.
- Test gate: `cd plugins/fastnote.koplugin && busted spec/` must end
  0 failures / 0 errors (baseline at handoff: 232 successes).
- No device here: widget/refresh behavior is code-reviewed only; anything
  visual must be safe-by-construction (additive UI, config-gated
  behavior changes with the old behavior reachable).
- Documentation rides with the change (documentation-as-code skill):
  conf example, waveform note design table, this plan's checkboxes,
  AGENTS.md File Map for new files.
- After each task, check its Acceptance boxes in this file.

---

## Task C1 — color self-test + gate diagnostics (in-plugin)

Goal: a one-tap, on-device answer to "is the color pipeline intact at the
KOReader level, independent of drawing code?"

1. **Menu item "Color self-test"** in the canvas hamburger menu
   (`onMenuTap`, `drawingcanvas.lua`):
   - Paint a test pattern into `self._bb` over a centered rect: one solid
     bar per PALETTE color, plus a black and a white reference bar.
   - Refresh that rect with `"full"` + dither=true via
     `UIManager:setDirty` (→ GCC16 on an intact pipeline — the
     highest-fidelity color mode; a flash is fine here).
   - Show an InfoMessage summarizing the gate values (see 2) so the user
     sees numbers next to the bars.
   - On dismiss (or immediately after the InfoMessage), restore the page
     with `_repaintAll()`.
   - Interpretation for the user (put it in the InfoMessage text):
     bars in color → pipeline intact, any remaining issue is plugin-side;
     bars gray → KOReader-level gate broken (usually the color_rendering
     setting / 8bpp trap) — no plugin change can help until that's fixed.
2. **Gate logging**: at canvas init AND in the self-test message, log/show:
   - `Screen.bb:getType()` vs `Blitbuffer.TYPE_BBRGB32` (the definitive
     8bpp-trap tell: BB8 means the trap is sprung),
   - `Screen:isColorEnabled()`, `Device:hasKaleidoWfm()`,
     `Screen.hw_dithering`, `Screen.night_mode`,
   - the plugin's own `_has_color_hw`.
   (Some init logging already exists from the Fix E work — extend, don't
   duplicate.)
3. **Proactive warning**: on canvas open, if `_has_color_hw` is true but
   `Screen:isColorEnabled()` is false, show a one-per-session InfoMessage:
   color rendering is disabled in KOReader settings; ink will stay
   grayscale; enable *top menu → gear → Screen → Color rendering* and
   restart KOReader.

Acceptance (C1):

- [x] `busted spec/` green (no change expected to lib/ unless a pure
      helper is extracted — spec it if so). No lib/ change was needed —
      all C1 logic lives in `drawingcanvas.lua` (KOReader-runtime-only,
      not spec-covered, per the plugin's own AGENTS.md). 232 successes /
      0 failures / 0 errors, same as baseline.
- [x] Self-test menu row present; InfoMessage lists every gate above with
      a one-line "bars gray means / bars colored means" explanation.
      "Color self-test" row added to `onMenuTap`'s menu (new Row 7b);
      `_runColorSelfTest()` paints the reference bars + fires `"full"`
      + dither=true, then shows an InfoMessage with `_colorGateLogLine()`
      (all six gate values) plus the two interpretation lines from the
      plan text, verbatim in spirit.
- [x] Warning fires only when color hw + isColorEnabled()==false, once
      per canvas open. Implemented in `init()` right after the gate
      snapshot is built; fires at most once because `init()` runs exactly
      once per `DrawingCanvas` instance (`_reinitAtRotation` reuses the
      instance for rotation and never calls `init()` again — verified by
      reading it).
- [x] No behavior change to drawing paths whatsoever. No edits touched
      `_drawSegment`, `_refreshRect`, `_scheduleTighten`,
      `_expandTightenRect`, `_liveColorRefresh`, `_flushLiveRefresh`,
      `paintTo`, or any input/poll code — diff is additive only (two new
      requires-worth of code: gate snapshot/log helpers, the self-test
      method, one menu row, one warning block in `init()`).

Deviation note: the plan named `Screen.night_mode` as a gate to log: no
such field exists anywhere in `frontend/` (grepped `frontend/device/`,
`frontend/ui/uimanager.lua`). The real per-device equivalent on this
hardware is `Screen:getHWNightmode()` (`frontend/device/kobo/device.lua`
~line 723, defined only under `if self:isMTK() then`, which KoboMonza
satisfies) — a HW inversion getter with no backing field, guarded with
`Screen.getHWNightmode and Screen:getHWNightmode()` the same way the
existing code already guards `Device.hasKaleidoWfm`. Substituted this for
the gate snapshot's `hw_night_mode` value; noted here per the task's
instruction to record any gate-API substitution.

## Task C2 — solid live ink under A2 ("draw black, bloom color")

Goal: match the stock Kobo notebook's behavior — live strokes appear as
**solid near-black ink** regardless of chosen color; the tighten pass then
reveals the true color.

> **⚠️ Correction (2026-07): the symptom this task works around was an
> artifact, so the whole task is suspect — but it shipped and is still the
> live default.** Until commit `9e7d8b1`, `canvas_utils.drawLine` painted
> through `BlitBuffer:paintRect`, which calls `value:getColor8()` before
> writing any pixel even into an RGB32 buffer. Live ink was therefore
> grayscale before A2 ever touched it, so "colored ink looks faint and
> dotted live" describes the paint bug, not A2. Everything below —
> `live_ink_style` and its `"solid"` default, `canvas_utils.live_ink_mode()`
> (including its `tighten_enabled` parameter), the `_display_diverged`
> flag, `_rebuildDisplayFromStrokes()` in the tighten closure, the
> `spec/canvas_utils_spec.lua` `live_ink_mode` block, and the symptom prose
> in `fastnote.conf.example` — exists to serve that premise, and lives or
> dies as one unit. Nothing here has been reverted; it is correct as
> *implemented*, just possibly unnecessary. Whether it is still needed is
> W0.5's highest-value question in
> `.agents/planning/post-v1-roadmap-handoff.md` — device-only, do not
> settle it by reading code.

Design:

- New config key `live_ink_style` in `lib/config.lua` (+ conf example):
  - `"solid"` (default): on color hardware, live segments are painted
    into the **display buffer** (`self._bb`) in solid black (dark mode:
    white — i.e., today's dark-mode behavior is already "solid"), while
    the stroke's true color continues to be recorded in StrokeBuffer
    (ADR-002: StrokeBuffer is the source of truth — this change makes the
    display cache *deliberately* diverge from true color between pen-up
    and tighten).
  - `"color"`: today's behavior (paint true color into `_bb`; A2 shows it
    as 1-bit dither).
- The tighten pass must now **repaint before refreshing**: rebuild
  `self._bb` from StrokeBuffer with true colors (same op `_repaintAll`
  does, *without* its setDirty) and then fire the existing
  `"partial"`+dither refresh over the accumulated rect. After the tighten,
  `_bb` and StrokeBuffer agree again.
- Everything that already rebuilds `_bb` from StrokeBuffer (`_repaintAll`,
  `loadPage`, undo/redo, dark-mode toggle, rotation) is automatically
  consistent — verify, don't assume.
- **Interaction with `live_color_refresh` (the direct-refreshUI
  experiment):** that path exists precisely to show true color live, so
  when `_useLiveColorRefresh()` is true, `live_ink_style` must be treated
  as `"color"` (solid-black would defeat the experiment). Precedence:
  live_color_refresh > live_ink_style.
- Dark mode: unchanged (ink already forced white).
- Mono hardware: unchanged (`live_ink_style` is a color-hw concept; black
  ink is already what mono devices draw).

Acceptance (C2):

- [x] `busted spec/` green; config specs for `live_ink_style` (default,
      file override, explicit-"color" survives merge). 241 successes /
      0 failures / 0 errors (232 baseline + 9 new: 6 in
      `spec/canvas_utils_spec.lua`'s new `live_ink_mode` describe block,
      3 in `spec/config_spec.lua`).
- [x] Live segment paint color decision is in a pure, spec-tested helper
      (e.g. in `lib/canvas_utils.lua`): given (style, dark_mode,
      has_color_hw, live_color_refresh_active) → display ink decision.
      `lib/canvas_utils.lua`'s `live_ink_mode(style, dark_mode,
      has_color_hw, live_color_refresh_active)` returns `"solid"` |
      `"true_color"`; written spec-first (red confirmed before
      implementing).
- [x] Tighten repaints `_bb` from StrokeBuffer before its refresh; the
      repaint is skipped when nothing diverged (style=="color" or no
      solid-ink segments drawn since the last rebuild).
      `drawingcanvas.lua`'s `_scheduleTighten` fired closure calls the new
      `_rebuildDisplayFromStrokes()` helper only `if
      self._display_diverged`; `_drawSegment` sets that flag true only
      when `live_ink_mode` returns `"solid"`. `_rebuildDisplayFromStrokes`
      (shared by `_repaintAll` and `loadPage`, so undo/redo/erase/
      rotation/dark-mode-toggle/clear-page/loadPage all stay consistent
      automatically) always clears the flag.
- [x] `fastnote.conf.example` documents `live_ink_style` with the
      user-visible symptom each value produces.
- [x] Waveform note's design table updated (live segment row: display
      ink vs stored ink). Also added a short "Task C2, implemented" note
      under the 2026-07 A2-dither correction section.

## Task C3 — review pass

Independent review of the combined C1+C2 diff, same rules as the previous
plan's review: hunt correctness bugs, default-path regressions, and
interactions (self-test vs pending tighten/live rects; solid-ink vs
eraser/undo/dark-mode/rotation; `live_color_refresh` precedence). Report
findings; supervising session applies fixes.

**Result (2026-07): no blockers; two should-fixes found and applied.**

1. (Found by the supervising session during C2 review.) Solid live ink
   with `tighten_enabled = false` would stay black forever — nothing ever
   repaints the true color. `live_ink_mode` now takes `tighten_enabled`
   and forces true-color when it's explicitly false.
2. (Found by the independent reviewer.) `_runColorSelfTest` didn't cancel
   a pending tighten; one firing mid-diagnostic would rebuild `_bb` and
   wipe the reference bars while the user was reading them — in exactly
   the "just drew something faint, immediately ran the self-test" flow.
   The self-test now calls `_cancelTighten()` before painting.

Traced clean by the reviewer: mono hardware, dark mode, style `"color"`
(byte-identical to pre-C2), `live_color_refresh` precedence, eraser/undo/
dark-mode-toggle/page-navigation interactions, `_display_diverged`
lifecycle, and spec quality (all new specs fail if their logic is
reverted). Noted as intentional: solid ink also applies to the
touch/gesture drawing paths — the A2 dither is a property of the refresh
mode, not the input path.

---

## Phase D — on-device decision tree (maintainer; cannot be done here)

> **⚠️ Correction (2026-07): this decision tree was written before the
> paint bug was known, and its color branches lead nowhere.** Until commit
> `9e7d8b1`, `canvas_utils.drawLine` and `_runColorSelfTest`'s bar loop
> both painted through `BlitBuffer:paintRect`, which calls
> `value:getColor8()` before writing any pixel even into an RGB32 buffer —
> so no color could reach the panel by any route. Concretely, in the steps
> below:
>
> - **Step 3** — the self-test bars were *always* going to be gray, so
>   "bars gray → KOReader-level gate still broken" is a guaranteed false
>   positive. It would have sent the maintainer back to step 2 to recheck a
>   color-rendering gate that was already fine.
> - **Step 4** — "solid black live but still no color on the refresh" was
>   the certain outcome, and it is not evidence about
>   `isColorEnabled`/`hw_dithering`/Kaleido.
> - **Step 5** — "muted live color" from `live_color_refresh` was measured
>   under the same artifact.
>
> Steps 1 and 2 are still correct and worth doing (stale deployment and the
> 8bpp/CFA trap are both real). Run the tree again post-fix rather than
> trusting any result recorded against it; re-validation is tracked at
> `.agents/planning/post-v1-roadmap-handoff.md` → W0.5.

1. **Fix the deployment first**: merge the current branch into `master`
   (PR base = `master` — PR #12's mistake was base =
   `claude/review-agents-docs-E7gb0`), redeploy the plugin directory to
   the device, restart KOReader. Sanity check: the deployed
   `drawingcanvas.lua` contains `"a2"` in `_refreshRect` (A2 live), not
   `"partial"` — if it doesn't, the device is still on stale code.
2. **Check the color gate**: *top menu → gear → Screen → Color
   rendering* must be checked; if you change it, restart. Confirm
   `crash.log` says "Switching fb bitdepth to 32bpp". (If it says 8bpp
   to disable CFA — that was the whole bug.)
3. **Run the Color self-test** (C1) from the canvas menu:
   - Bars gray → KOReader-level gate still broken; recheck step 2, then
     report the gate values from the InfoMessage back into this plan.
   - Bars colored → pipeline intact; continue.
4. **Draw with red ink in light mode**: live line should be solid black
   (C2); ~2.5 s after pen-up the line's region refreshes and turns red.
   - Solid black live but still no color on the refresh → report the
     init-log gate values (isColorEnabled/hw_dithering/Kaleido) — that
     combination is then the next investigation target.
5. Optional: toggle "Live color ink (experimental)" and compare — muted
   live color instead of solid black, same color bloom on the tighten.
6. Record all results in this file and in the waveform note's fact-check
   tables (that's what keeps the research honest).
