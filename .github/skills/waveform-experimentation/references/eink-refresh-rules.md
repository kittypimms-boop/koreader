# E-ink refresh conventions (drawing canvas, Kobo Libra Colour)

Hard rules for any code that paints strokes or requests screen refreshes.
Each was learned from a real on-device failure — the history and evidence
live in `.agents/notes/waveform-refresh-research.md` (repo root). For the
procedure to test a refresh/waveform change on device, see the `SKILL.md`
alongside this file.

> **This was a `.github/instructions/` file until it moved here.** It was
> scoped `applyTo: plugins/fastnote.koplugin/drawingcanvas.lua`, which
> loaded it on *every* edit to that file — menus, page navigation,
> orientation, input handling — when it only matters for refresh and paint
> code. Wrong mechanism: these are rules you need when doing one specific
> kind of work, which is a skill reference, not an always-on path-scoped
> convention.

---

## Never use `"partial"` per segment during live drawing

UIManager promotes *any* `"partial"` refresh to a full flashing refresh
after `FULL_REFRESH_COUNT` refreshes (default 6, `frontend/ui/uimanager.lua`
~line 513). At drawing rates that means a screen flash within the first
stroke, locking out the pen mid-line. `"partial"` (+dither) is correct only
for one-shot full-quality repaints: `_repaintAll` and the tighten pass.
`"ui"`, `"fast"`, and `"a2"` do not count toward the promotion.

## Never use `"fast"` (DU) on color hardware at 32bpp

On KoboMonza, DU at 32bpp hits a driver CFA working-buffer bug: strokes are
invisible or corrupted in light mode. Non-color (8bpp) devices are fine
with `"fast"`. Per-device waveform mappings differ — never assume a mode
name means the same thing on another Kobo.

## Ink not in colour? Check what's being painted before how it's refreshed

**Never use `BlitBuffer:paintRect` for anything that carries hue.** It is
documented to take a luminance value and it means it — it calls
`value:getColor8()` before writing any pixel, **even into a genuine
`TYPE_BBRGB32` buffer**, so a `ColorRGB32` arrives as R=G=B grey.
`paintRectRGB32` is the type-aware sibling: full colour on RGB32/RGB16,
correct degradation on BB8/BB8A. It is a safe unconditional replacement.

This single call cost this repo an entire investigation. The refresh layer
was proven sound repeatedly — a correct GCC16 waveform was even captured on
device — and each proof was read as "so the problem is elsewhere in the
refresh layer." Nothing was in colour because the pixels were greyscale
before the refresh ever saw them. **A correctly-requested waveform proves
the refresh layer works; it says nothing about whether the data handed to
it has any colour in it.** See `.agents/notes/waveform-refresh-research.md`
→ "paintRect vs. paintRectRGB32".

## `"a2"` is 1-bit black/white — grayscale live ink is expected

A 1-bit waveform cannot show colour during the live stroke; true colour
arrives via the deferred tighten pass (GLRC16). Do not "fix" grey live ink
by switching the live waveform to a colour mode — the colour modes are
hundreds of ms per update and unusable at pen polling rates.

**The 1-bit fact is solid. The workaround built on it is not.**
`live_ink_style = "solid"` exists because colour ink appeared as a faint,
sparse dither under A2 — but that was luminance-converted pixels being
thresholded, measured before the `paintRect` fix. Whether the workaround is
still needed is an open question, not a settled constraint.

## Kaleido color is reached only by dither promotion

`"partial"`+dither → GLRC16; `"full"`+dither → GCC16. Nothing else
produces a color-processed (CFA) update. The promotion additionally
requires `self.dithered = true` on the widget (set when color hw present),
`Screen.hw_dithering`, and `Screen:isColorEnabled()` — if color stops
appearing on the tighten pass, check those three gates first.

## Direct `Screen:refresh*` calls bypass UIManager entirely

`Screen:refreshUI/refreshFast/...` hit the framebuffer directly: no paint
queue, no widget repaint, no flash-promotion counter. That makes them the
sanctioned escape hatch for high-frequency live refreshes (the technique
pencil.koplugin uses for live color — see
`.agents/planning/pencil-koplugin-research.md`). Anything painted this way
must still be recorded in StrokeBuffer — the framebuffer is never the
source of truth (ADR-002).

## The tighten delay is device-tuned — don't lower it casually

`COLOR_TIGHTEN_DELAY` was tuned on hardware: shorter delays fire the GLRC16
pass between the strokes of normal handwriting, locking out the pen
mid-word. Any change to it needs the multi-stroke writing test in the
waveform-experimentation skill's matrix.
