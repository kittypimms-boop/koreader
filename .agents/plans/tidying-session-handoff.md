# Handoff — docs tidying + colour-artifact correction session

**Status: HANDOFF, work paused mid-plan. Nothing in flight; both repos
committed and pushed. Next actions are listed at the bottom and have not
been started.**

Written so a fresh agent can resume after this chat is compacted. Assumes
no memory of the session that produced it.

---

## Where to go first

1. `plugins/fastnote.koplugin/AGENTS.md` — repo index.
2. `.agents/planning/post-v1-roadmap-handoff.md` — **the forward plan.** All
   the workstreams (W0…W6) live there with full detail. This file does not
   duplicate it; it records what changed this session and what to do next.
3. This file, for session state and the traps below.

---

## Open PRs

Both branches are `claude/fastnote-plugin-tidying-g61utv`. Pushing to either
updates its PR — do not open new ones.

| Repo | PR | Contents |
|---|---|---|
| kittypimms-boop/koreader | [#22](https://github.com/kittypimms-boop/koreader/pull/22) | 12 commits — one code change, the rest docs |
| kittypimms-boop/agent-purrcy | [#8](https://github.com/kittypimms-boop/agent-purrcy/pull/8) | 3 commits, net 1 file: `koreader-plugin/SKILL.md` |

**koreader's own convention is commit-direct-to-`master`, no PRs**
(ADR-007). PR #22 exists only because the session mandated a branch. Merging
it or fast-forwarding `master` and closing it are both fine; just don't let
it read as the repo switching to a PR flow.

**purrcy#8 history wrinkle:** an auto-memory section is added in `84974e5`
and removed in `ba5c550`. Net diff is clean; squash-merge collapses it. Only
worth rebasing if that repo merges with commits preserved.

---

## What landed

**Code (one change only):** live colour ink promoted out of "experimental".
`canvas_utils.auto_live_color_refresh` — which *overwrote* the user's flag on
every colour pick, silently undoing a manual "off" — was replaced by
`canvas_utils.live_color_applies`, a suppression gate inside
`_useLiveColorRefresh`. Black ink and dark mode now suppress live colour
without destroying the preference, so a black-ink detour costs no menu round
trip. Menu label gained a third state, `on (paused)`.

**Docs — structural:**
- `CLAUDE.md` twins converted from OS symlinks to one-line `@AGENTS.md`
  import files, via `claude_compat_sync.py` (purrcy repo). Repo now reports
  clean under that tool.
- Plugin AGENTS.md: File Map and Architecture sections **deleted** (67
  lines) and replaced by a short directory-roles table plus
  `.agents/notes/code-layout.md`, a new lazy-loaded topic holding the data
  flow, invariants, and negative-space traps.
- `agents.instructions.md` decision-tree item 1 rewritten: it used to
  *mandate* the File Map its own opening principle forbids. Now requires
  navigation hints at grep altitude and forbids file-by-file maps.
- `.agents/scratch/` added (gitignored) — the ephemeral working-notes tier.
- `eink-refresh.instructions.md` **moved** to
  `.github/skills/waveform-experimentation/references/eink-refresh-rules.md`
  and indexed from that SKILL.md. It was scoped to `drawingcanvas.lua`, so
  it loaded on every edit to a 2000-line file for rules that only matter to
  refresh work.
- `lua.instructions.md` gained two sections synced from purrcy: accidental
  globals, and Lua patterns ≠ regex.

**Docs — the colour correction (the substantive one):** see next section.

**Upstreamed to purrcy:** the `paintRect` colour footgun now leads the
`koreader-plugin` skill's E-Ink section, which previously recommended
`"fast"` during pen strokes (broken on colour hardware), `"flash"` on
pen-up, named the wrong SoC, and conflated raw `/dev/fb0` with
`Screen:refreshUI`.

---

## The colour artifact — the thing most likely to mislead you

Commit `9e7d8b1` (2026-07-15) fixed `canvas_utils.drawLine` to use
`paintRectRGB32` instead of `paintRect`. `paintRect` calls
`value:getColor8()` before writing any pixel **even into an RGB32 buffer**,
so every stroke was greyscale before the refresh layer ever saw it.

**Every colour experiment before that date was run on greyscale pixels.**
The mechanism findings survive (waveform map, promotion counter, gate chain,
A2's 1-bit behaviour, DU/32bpp bug, all timing results). What does not
survive is a set of *design decisions made because colour appeared missing*
— chiefly `live_ink_style = "solid"`.

A full audit of which claims are artifact-dependent is folded into
**W0.5** of the roadmap, including the complete list of code that exists
only to serve solid ink, and the four docs still carrying uncorrected
artifact-era claims. Read W0.5 before touching anything colour-related.

**W0.6** is separate and was found in the same audit:
`avoid_flashing_ui` silently downgrades a regioned `"partial"` to `"ui"`
(`uimanager.lua` ~1137). The tighten pass is exactly a regioned
`"partial"`+dither, so if that setting is on, the tighten pass cannot
produce colour *today*. Nobody has checked whether it's on. Source-confirmed,
independent of the artifact, never acted on.

---

## Decisions made this session — settled, don't re-litigate

| Decision | Choice |
|---|---|
| Emulator display over SSH | VNC on a virtual display |
| Folder storage | Real filesystem subdirectories (against the analysis' recommendation — risks and mitigations are written up in W4) |
| OCR milestone 1 | Cheap proof-of-concept: rasterize → existing Tesseract |
| Launch with 2+ notebooks | Resume last notebook + page |
| Finger-draw latency | **Cheap fix first** (`ges.start_pos` backfill), raw-touch path queued for device |
| Device access | Occasional — batch all on-device work into one session |
| AGENTS.md line-count guidance | **Left as-is** (400/500). Anthropic's 200 was judged conservative; line count is a poor proxy for tokens |
| Auto memory | **Not documented anywhere.** Optional, often disabled, machine-local — conventions must not depend on it. Removed from both repos |

---

## Next actions, not started

**Headless batch (no device needed):**
1. Finger-draw backfill — seed the stroke from `ges.start_pos` instead of
   the first pan position. ~2 lines, but note the chrome-strip guard checks
   `y`, not `gsy`: a touch starting in the chrome strip and panning into the
   canvas would draw a line from the chrome. That guard is most of the work.
2. Resume-on-launch — `main.lua:onOpenFnoteCanvas`'s `count >= 2` branch
   never resumes. Extract the restore helper the `count == 1` branch already
   uses (see W2 for the fallback rule: any unresolvable path → loading menu).
3. Shell quoting in `model/library.lua` / `model/notebook.lua` — prerequisite
   for folders, currently latent because all paths are machine-generated.
4. Correction banners on the four uncorrected colour docs listed in W0.5.

**One batched device session:**
1. Check `avoid_flashing_ui` (W0.6) — five minutes, potentially significant.
2. Colour matrix (W0.5): is `live_ink_style="solid"` still needed; is
   `live_color_refresh` still muted; does the tighten delay still earn itself.
3. `evtest` on the digitizer — decides whether the raw-touch finger path is
   viable, and whether `ABS_MT_TOOL_TYPE`/`MT_TOOL_PALM` is being reported
   (see W5; `touchdev.lua` doesn't parse that axis at all).

**Awaiting a user answer:** whether to split the icons work — recents row +
thumbnails against today's flat layout first (both work without folders),
with the collapsible tree deferred until folders land. This reorders W3/W4
as currently written in the roadmap.

---

## Traps a fresh agent will hit

- **`busted` must come from the distro**: `sudo apt install lua-busted`.
  `luarocks install busted` pulls dependencies from GitHub tarballs and dies
  behind a proxy.
- **`./kodev` needs `base/` initialised** — the submodule is empty in a
  fresh clone and carries the whole native toolchain.
- **Two `.agents/` directories exist.** The canonical one is at repo root.
  The plugin-local one holds an `adr-006` that is *not* the repo-root
  ADR-006 — different decisions, same number.
- **`plugins/fastnote.koplugin/dev-plan-v2.md` must stay byte-identical** to
  `.agents/planning/fastnote-dev-plan-v2.md`. `diff` them after touching
  either.
- **Test gate**: `cd plugins/fastnote.koplugin && busted spec/` — 272
  passing at handoff time.

**Two claims this session got wrong before verifying** — both worth
repeating as a method note, because the same failure mode is what caused the
colour churn in the first place:

1. The colour artifact was attributed to a user setting
   (`Screen:isColorEnabled()`) before checking `git log`. It was a code bug.
   The history had the answer in one commit message.
2. purrcy's `creating-project-agents` skill was reported as having stale
   symlink guidance. The **repo** copy is correct; the stale copy was the
   globally-installed one at `/root/.claude/skills/`. Check which copy
   you're reading.

Verify against the source of truth before writing a conclusion down —
written-down conclusions get trusted later, and a wrong one is more
expensive than no note at all.
