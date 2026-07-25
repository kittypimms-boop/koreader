# Handoff: post-v1 roadmap for fastnote

**Status: PLANNING / HANDOFF (2026-07). Not started.**
**Audience: an agent picking this up cold, with no memory of the session
that produced it.**

fastnote reached daily-use quality: drawing, color, eraser, palm rejection,
undo/redo, notebooks, SVG persistence all work on device. This document
plans what comes after, across six workstreams.

**Read first:** `plugins/fastnote.koplugin/AGENTS.md` (index),
`.github/instructions/lua.instructions.md` (dialect rules — the `_` vs `__`
gettext trap has caused real crashes here),
`.github/skills/test-driven-development/SKILL.md` (when a spec comes first
in this repo and when it can't).

**Every "current state" claim below was verified against the code at the
time of writing.** If something contradicts what you find, trust the code
and correct this document.

---

## Decisions already made by the user

Answered during the planning session. **These are settled — implement them,
don't re-litigate them.** Where a decision went against the analysis, the
reasoning that lost is preserved in the relevant workstream so you know
which risks you're carrying, not so you can reopen the question.

| # | Decision | Chosen |
|---|---|---|
| D1 | Emulator display path over SSH | **VNC on a virtual display** (Xvfb/TigerVNC server-side) |
| D2 | Folder storage model | **Real filesystem subdirectories** — `notebooks/<folder>/<uuid>/` |
| D3 | OCR milestone 1 target | **Cheap proof-of-concept** — rasterize → the Tesseract already in koreader-base |
| D4 | Launch behavior with 2+ notebooks | **Resume last notebook + page**; browser stays reachable from the canvas menu |

---

## Suggested order, and why

```mermaid
graph LR
    W0[W0 Emulator] --> W1[W1 Finger latency]
    W0 --> W2[W2 Resume]
    W1 --> W3[W3 Thumbnails]
    W2 --> W3
    W3 --> W4[W4 Folders]
    W0 -.optional.-> W5[W5 Hardware input]
    W4 --> W6[W6 OCR]
```

- **W0 first** because everything after it is faster with a working
  emulator, and because W1 is reproducible in the emulator (see below).
- **W1 before the UI work** — it's the user's stated blocker on daily use,
  and it's already analysed in `.agents/notes/finger-draw-input-latency.md`.
- **W3 before W4** — thumbnails settle the browser's row-rendering approach,
  and W4 rebuilds that browser. Doing W4 first means building the folder UI
  twice.
- **W5 is a side quest**, safe to interleave anywhere; it must stay behind a
  flag and must not become a dependency of anything else.
- **W6 last** — largest, least certain, and its cheap first milestone
  depends on a ruled writing mode that doesn't exist yet.

---

## W0 — Emulator + dev loop

**Goal:** `./kodev run` working on the user's Ubuntu box, reachable from a
VS Code Remote-SSH session, at Libra Colour dimensions.

### Current state

`kodev` exists and is functional. `base/` (the `koreader-base` submodule) is
**not initialised** in this checkout — `ls base/` is empty. That submodule
carries the whole native toolchain, so nothing builds until it's fetched.

`kodev run -s=<preset>` has no Libra Colour preset. The presets stop at
`kobo-forma` (1440×1920 @300). Use explicit flags instead:

```bash
./kodev run -W=1264 -H=1680 -D=300
```

Those are the Libra Colour's real panel dimensions and DPI (`KoboMonza`,
`display_dpi = 300` in `frontend/device/kobo/device.lua`).

### Why the DPI flag matters more than it looks

`GestureDetector.PAN_THRESHOLD` is `screen:scaleByDPI(35)`
(`frontend/device/gesturedetector.lua`, `GestureDetector:init`). At
`-D=300` the emulator reproduces the same threshold the device uses — which
means **W1's finger-draw latency bug is reproducible in the emulator with a
mouse drag.** Run at the wrong DPI and the bug changes size or vanishes.

This is the single most valuable thing about getting W0 done first.

### Setup outline

Full step-by-step lives in the chat handoff that produced this doc; the
essentials:

1. `git submodule update --init --recursive` (or `./kodev fetchthirdparty`).
2. Ubuntu prerequisites — see `doc/Building.md` → "Debian/Ubuntu". Note
   KOReader now requires **SDL3 ≥ 3.2.12**; Ubuntu 24.04 LTS does not ship
   `libsdl3-0`, so either install the X11/Wayland `-dev` packages listed
   there and let the build compile SDL3 itself, or move to a release that
   packages it.
3. `./kodev build`, then `./kodev run -W=1264 -H=1680 -D=300`.
4. Display (D1 = VNC on a virtual display): run a VNC server on the Ubuntu
   box, point `DISPLAY` at it, launch `kodev run` inside that session, and
   connect with a VNC client from the workstation. The advantage over
   `ssh -X` that made this the choice: rendering happens server-side, so
   what you see reflects the emulator's real speed, and the session
   survives an SSH drop instead of taking the emulator down with it.
   VS Code Remote-SSH is then only doing what it's good at — editing and
   terminals — with the emulator window arriving over a separate channel.

### Pitfalls

- **The emulator cannot test what this plugin most needs testing.** No
  `/dev/input/eventX`, no `EVIOCGABS`, no E-ink waveform modes. It exercises
  the gesture path only (`use_raw_input = Device:isKobo()` → false). Every
  raw-evdev change and every refresh/waveform change still needs the device.
  See `.agents/notes/input-path-architecture.md`.
- Don't judge refresh behavior from the emulator — it has no A2, no GLRC16,
  no flash-promotion counter.
- If SDL3 gets built from source, that's a long first build. Budget for it.

### Possible follow-up

If the setup proves fiddly, it earns a
`.github/skills/emulator-dev-loop/SKILL.md` — it's a procedure, which per
`.github/instructions/doc-architecture.instructions.md` belongs in a skill,
not an instructions file.

---

## W1 — Finger-draw first-contact latency

Already analysed. **Do not re-derive it** — read
`.agents/notes/finger-draw-input-latency.md`, which has the root cause, the
"which input path is actually drawing" check to run first, and four ranked
candidate fixes.

Only additions since that note was written:

- W0 gives you emulator reproduction at `-D=300` (above).
- Fix candidate 1 (seed the stroke from `ges.start_pos` instead of the first
  pan position) is verifiable in the emulator. Candidate 2 (make raw touch
  the finger path) is not — it needs the device.

---

## W2 — Resume last notebook and page

**Goal:** reopening fastnote lands on the page you left.

### Current state — mostly built already

This is much closer to done than it appears:

- `model/library.lua` `readState()` / `writeState()` persist
  `state.last_notebook_uuid` and `state.last_page_index` to
  `<datadir>/fastnote/state.lua`.
- `main.lua` writes both in `on_save_callback`, `on_page_forward`,
  `on_page_back`, and `on_page_jump`.
- `main.lua:onOpenFnoteCanvas` restores them **when there is exactly one
  notebook**, and `_showBrowser` restores the page when the notebook you
  pick happens to be the last-used one.

**The actual gap is one branch:** with 2+ notebooks, `onOpenFnoteCanvas`
unconditionally shows the browser and never resumes.

### The change (D4: resume)

In `onOpenFnoteCanvas`'s `count >= 2` branch, look up
`lib:byUUID(state.last_notebook_uuid)`. Found → open it at the clamped
`last_page_index`. Not found → fall through to the browser as today.

The single-notebook branch's restore logic is the same three lines; extract
a helper rather than writing a third copy (the repo's rule: a second
copy-paste means it needs a name — see `lua.instructions.md`).

### Pitfalls

- **`writeState` only persists strings and numbers.** Booleans are silently
  dropped — that's why `dark_mode` is stored as `1`/`0`. If you add a
  boolean state key, encode it the same way or extend `writeState` (and
  spec it).
- **The stored page index can outlive its page.** Pages can be deleted;
  `last_page_index` is not updated when they are. The existing
  `math.max(1, math.min(idx, nb:pageCount()))` clamp is what makes this
  safe — preserve it in the new path.
- **The stored notebook can be gone entirely** (deleted from the browser).
  `byUUID` returns nil; handle it rather than indexing nil.
- **Don't strand the browser.** If launch always resumes, the only route to
  the browser is the canvas hamburger's existing `on_show_browser`. Verify
  that route works before shipping, or the user has no way to switch
  notebooks.

### Tests

`spec/library_spec.lua` already covers the state round-trip. Add: missing
uuid, uuid not present in library, page index beyond `pageCount`. The
`main.lua` routing itself is not unit-testable (KOReader runtime) — verify
in the emulator.

**Size: small.** A good first task to confirm the W0 loop works.

---

## W3 — Notebook thumbnails

**Goal:** the browser shows a visual preview per notebook.

### Current state

`model/notebook.lua:getThumbnailPath()` returns `<nb.dir>/thumb.png` and is
spec'd (`spec/notebook_spec.lua`). **Nothing ever writes that file.** The
hook is there; the generator is not.

### Prior art to read before designing anything

`plugins/coverbrowser.koplugin/` solves exactly this problem for books:
`mosaicmenu.lua` (grid of covers), `listmenu.lua` (list rows with
thumbnails), `bookinfomanager.lua` (thumbnail cache + invalidation). Read
these before inventing a layout. Reusing their menu subclasses may be
possible; at minimum steal the caching approach.

### Design decisions

1. **When to generate.** On page save (costs time during drawing), on canvas
   close, or lazily when the browser opens (first paint is slow). Suggested:
   on save of **page 1 only**, debounced — the browser only ever shows one
   thumbnail per notebook, so generating for other pages is wasted work.
2. **How to rasterize.** The canvas already renders strokes into a
   `BlitBuffer`; the thumbnail is a downscaled copy. Find the PNG writer
   KOReader's screenshot feature uses (in `koreader-base`, exposed through
   the frontend) rather than adding a dependency — confirm the exact call
   before planning around it.
3. **Invalidation.** A thumbnail whose page has changed is worse than none.
   Store the source page's mtime (or stroke count) alongside it and
   regenerate on mismatch.
4. **List vs grid.** Grid looks better; list is closer to what exists today
   (`ui/browser.lua` uses a plain `Menu`).

### Pitfalls

- **E-ink refresh cost.** A grid of images is a large-area update. Follow
  `.github/instructions/eink-refresh.instructions.md` — in particular, never
  per-item `"partial"` refreshes, which get promoted to a full flash after
  six.
- Dark mode: thumbnails are rendered from stroke data, and stroke color is
  canonical light-mode hex (`.agents/notes/stroke-color-invariant.md`). A
  thumbnail rendered in dark mode and cached will look wrong in light mode.
  Render thumbnails in one fixed mode, or key the cache by mode.
- Blank first pages produce blank thumbnails. Decide whether that's fine
  (it's honest) or whether to fall back to the first non-empty page.

---

## W4 — Folders / notebook organization

**Goal:** folders (later, sub-folders) containing notebooks; move notebooks
between them; rename/create/delete folders; user-chosen sort order.

This is the largest workstream, and **D2 chose the harder of the two storage
models**. Read "The shape of the chosen model" below before touching code —
most of the risk in this workstream is concentrated in that choice, and it
is all manageable if you handle it deliberately.

### Current state

- Storage is flat: `<datadir>/fastnote/notebooks/<uuid>/`, one dir per
  notebook, per `ADRs/ADR-006-uuid-directory-layout-for-notebooks.md`.
- `Library:_scan()` shells out to `io.popen("ls -1 ...")` over that one
  directory — a flat, single-level scan.
- Ordering exists in two places: `Library:_sortOrder()` (by `last_edited`)
  and `ui/browser.lua`'s `_sorted_nbs` (session-only `_sort_by`, name or
  recency). **They duplicate each other.** Resolve that while you're in
  here rather than adding a third ordering.
- `ui/browser.lua` is a flat `Menu` with a "+ New notebook" row, a sort
  toggle row, then one row per notebook. Long-press opens a
  rename/delete `ButtonDialogTitle`.

### The shape of the chosen model

D2: folders are **real directories**. Layout becomes:

```
<datadir>/fastnote/
  state.lua
  notebooks/
    nb_1748736123_001_004521/     ← unfiled (root level) — today's layout, still valid
    Work/
      .folder.lua                 ← folder metadata: display name, manual sort order
      nb_1748736140_002_881204/
      Projects/                   ← sub-folder, same rules, recursive
        .folder.lua
        nb_.../
```

What this buys, and why the user picked it: the library is legible over USB
or SSH. You can back it up with `rsync`, inspect it with `ls`, and rescue a
notebook with `cp` — no manifest to interpret. For a notes app holding
handwriting that exists nowhere else, that transparency is worth real
engineering cost.

Four consequences follow directly, and each has a mitigation you should
build in from the start rather than retrofit:

**1. Identity must stay the UUID; the path is derived.**
This is the load-bearing rule of the whole workstream. `Library:_scan()`
becomes recursive and builds a `uuid → absolute path` map. Every lookup goes
through that map. **Never persist a path anywhere** — not in `state.lua`,
not in folder metadata. `state.last_notebook_uuid` then survives any move or
rename for free, which is exactly what W2 depends on.

**2. A directory rename invalidates paths held by an open canvas.**
`DrawingCanvas` captures `load_path` / `_page_path` at open time. Rename an
ancestor folder while a canvas is open and its saves go to a path that no
longer exists. Two defences, cheap, use both:
   - Only offer folder operations from the browser, and confirm the canvas
     is actually closed when the browser is showing (check what
     `on_show_browser` does with the canvas — if it leaves it on the
     UIManager stack, that's the hazard).
   - On save, re-resolve `uuid → path` rather than trusting the captured
     one. This makes the whole class of bug impossible instead of unlikely.

**3. Telling a folder from a notebook during the scan.**
A notebook directory contains `notebook.lua`; a folder directory does not.
That is the discriminator — it needs no new marker file and it makes
today's flat layout a valid special case (root-level notebook dirs are
simply unfiled). **No migration step is needed**, which is a genuine
advantage of this model. Guard against pathological nesting anyway: cap
recursion depth and ignore a directory containing both `notebook.lua` and
child notebook dirs rather than trying to interpret it.

**4. User-typed names now reach the filesystem and the shell.**
See the blocking prerequisite below. Under the metadata model this would
have been optional hardening; here it is a correctness requirement.

`.folder.lua` still exists under this model, but only for what the
filesystem can't express: a display name that differs from the directory
name (so renaming the display name doesn't have to `mv` anything), and the
manual sort order the user asked for. A folder with neither is just a
directory with no metadata file — handle its absence as "defaults", never
as an error.

### Documentation obligations for this choice

- **ADR-006 needs a Consequences addendum**, not an edit to its Decision
  text — it currently mandates a flat UUID layout, and reality is diverging.
  Append; don't rewrite. See
  `.github/instructions/agents.instructions.md` → "ADRs are historical
  records".
- **A new ADR (next free number: ADR-008)** records the folder decision:
  filesystem directories chosen over the metadata model, transparency over
  USB as the deciding factor, with the four consequences above as the
  accepted tradeoffs.

### Blocking prerequisite: shell quoting

`model/library.lua` and `model/notebook.lua` build shell commands by string
concatenation with no quoting:

```lua
os.execute("mkdir -p " .. base_dir .. "/notebooks")
os.execute("rm -rf " .. nb.dir)          -- Library:deleteNotebook
io.popen("ls -1 " .. self:_nb_dir() .. " 2>/dev/null | sort")
```

Today every one of those paths is machine-generated (`nb_<ts>_<seq>_<rand>`)
so nothing user-typed reaches a shell. **D2 changes that** — under
filesystem folders, a user-typed folder name lands directly in every one of
those command strings. A folder named with a space breaks the scan outright;
a folder name containing shell metacharacters turns `rm -rf` into something
much worse than a bug.

Do this **first**, before any folder feature is wired up:

- Quote every interpolated path (`'%s'` with embedded single quotes escaped,
  or move off `os.execute`/`io.popen` to a helper that does it once).
- **Sanitize folder names on input**, in the browser's create/rename dialog:
  reject or strip `/`, control characters, leading `.` and `..`; cap length;
  reject empty-after-trim. Sanitize at the boundary, once — not at each use
  site.
- Consider decoupling entirely: directory name = a sanitized slug,
  display name = the user's string in `.folder.lua`. Then arbitrary user
  text never reaches the filesystem at all, and you keep the readable
  layout the user wanted. This is the recommended shape.

This is not optional polish. `rm -rf` with an unquoted user-supplied string
is how a notes library gets destroyed by a folder named `My Notes; oops`.

### The move-to-folder UI

The user's described flow: a `...` options entry per notebook → "Move to
folder" → an expandable/collapsible tree of existing folders, allowing
rename/add/delete inline.

**KOReader has no expandable tree widget.** `Menu` is flat and paginated.
Two ways to get there:

1. **Breadcrumb navigation** (recommended): entering a folder replaces the
   menu's `item_table` and pushes a breadcrumb in the title; a ".." row goes
   back. This is how KOReader's own file browser behaves, it's far less
   work, and it matches user muscle memory.
2. **Simulated tree**: build a flat list with indent prefixes and
   expand/collapse toggles that rebuild the list. Looks closer to the
   request, but you're hand-rolling tree state on a paginated widget.

Start with (1); revisit only if it genuinely feels wrong on device.

### Deletion confirmation

The user asked for: confirm always; a **second** confirmation when the
folder is non-empty, and that second notice must **list the notebooks that
would be deleted**.

Current `_context_menu` delete is a single confirm. Note the list can be
longer than the screen — cap it ("… and 7 more") rather than overflowing a
dialog. Consider offering "move contents up one level" as an alternative to
destroying them; it's the option most users actually want.

### Pitfalls

- **A notebook that appears in no folder listing is indistinguishable from a
  lost notebook.** Any notebook dir the recursive scan finds must surface
  somewhere in the UI, even if its location is unexpected — fall back to
  showing it at root rather than hiding it. Losing a notebook from the UI
  reads as data loss even when the file is perfectly intact on disk.
- **Manual sort order lists UUIDs in `.folder.lua`.** A UUID present in the
  order list but missing from disk must be skipped silently; a notebook on
  disk but absent from the order list must still appear (append it). Never
  let the order file act as a filter — that's the "lost notebook" bug in
  another costume. Sparse ordering (10, 20, 30 …) avoids renumbering every
  entry on each move.
- **A move is `mv`, and `mv` can fail** — target exists, permissions, no
  space. Check the result; `os.execute` returns a status that today's code
  ignores everywhere. A silently failed move that the UI reports as success
  is worse than an error dialog.
- **Two notebooks can't share a directory name, but two folders can want the
  same display name.** If you take the slug-plus-display-name approach
  above, handle slug collision (suffix `-2`) rather than failing the create.
- `Library:_scan()` currently loads every notebook at startup, and recursion
  makes that walk larger. Measure before optimising — a handful of notebooks
  is nothing, and lazy scanning complicates the uuid→path map that
  everything else now depends on.

### Tests

`model/` and the folder manifest are pure Lua — fully spec-able, and this
workstream is the strongest TDD candidate of the six. `ui/browser.lua` needs
the KOReader runtime; verify it in the emulator.

---

## W5 — Hardware-level input exploration

**Goal (as stated by the user):** get closer to the metal than KOReader's
input layer allows — hardware palm rejection first, maybe hardware finger
draw and pen reading, explicitly "for the heck of it."

Treat this as a **research spike behind a flag**. It must not become a
dependency of W2/W3/W4.

### Reality check on the approach — read this before buying an I2C book

The user mentioned I2C nodes and hwmon. Setting expectations honestly:

- **hwmon is the wrong subsystem.** It exposes temperature/voltage/fan
  sensors. The digitizer is not there.
- **Raw I2C (`/dev/i2c-N`, `i2cget`) fights the kernel driver.** The Elan
  chip is already claimed by an in-kernel driver that is actively
  transacting on that bus. A second userspace master on the same bus
  produces corrupt reads and can wedge the controller. This is not a "be
  careful" — it's the normal outcome.
- **The genuinely low-level surface available to userspace is evdev**: the
  ioctls (`EVIOCGABS`, `EVIOCGBIT`, `EVIOCGRAB`), the raw event stream, and
  the driver's own sysfs attributes under `/sys/bus/i2c/devices/`. That is
  where the embedded-systems interest can actually be scratched without
  fighting the kernel, and this plugin already lives there
  (`input/pendev.lua`, `input/touchdev.lua` use FFI + raw ioctls).

### The highest-value thing to check first

**The digitizer may already be reporting palm contacts, and fastnote is
throwing that away.**

- `lib/input_codes.lua` defines `ABS_MT_TOOL_TYPE = 0x37` and the
  `MT_TOOL_*` value table. `lib/eventlog.lua`'s format example shows a
  captured-looking `ABS_MT_TOOL_TYPE 2` line — and in Linux input,
  `MT_TOOL_PALM == 2`.
- **`input/touchdev.lua` does not parse `ABS_MT_TOOL_TYPE` at all.** It
  handles `ABS_MT_SLOT`, `ABS_MT_TRACKING_ID`, `ABS_MT_POSITION_X/Y` and
  `ABS_MT_TOUCH_MAJOR` only.

If the Elan chip really emits `MT_TOOL_PALM`, that is *hardware* palm
rejection — the controller's own classification — and wiring it in is maybe
twenty lines. **Verify with `evtest` on device before building anything.**
Rest a palm on the panel, watch for `ABS_MT_TOOL_TYPE` transitions.

### The second-cheapest thing, also already half-built

`lib/palmreject.lua` has an area gate: contacts with
`touch_major > area_threshold` are rejected regardless of pen state. It is
**disabled by default** (`area_threshold = 0` means off), and
`drawingcanvas.lua` constructs it with `PalmReject.new()` — no options, no
config key. So the area gate has never run in production.

`touchdev.lua` already reads `ABS_MT_TOUCH_MAJOR`, so the data is flowing.
Wiring `area_threshold` to a config key and tuning it on device is a
contained, testable improvement (`spec/palmreject_spec.lua` already covers
the gate's logic).

### Suggested spike sequence

1. On device, enumerate: `cat /proc/bus/input/devices`, then `evtest` on the
   digitizer node. Record which `ABS_MT_*` axes actually carry data, and
   their `EVIOCGABS` ranges.
2. Check for `ABS_MT_TOOL_TYPE` / `MT_TOOL_PALM`. If present → wire it into
   `touchdev.lua` and `palmreject.lua` as a first-class rejection rule.
3. If absent → wire and tune `area_threshold` instead.
4. Only then consider anything more exotic. Read the driver's sysfs
   attributes; don't open the I2C bus.

Capture findings in `.agents/notes/` — the enumeration output is exactly the
kind of device fact that gets re-derived expensively otherwise.

### Pitfalls

- **Two readers already share `/dev/input/event1`** (`pendev` and
  `touchdev`, per the combo-chip quirk in the plugin's AGENTS.md). Don't add
  a third fd. Extend the existing reader.
- **Never `EVIOCGRAB` the digitizer.** Grabbing it takes input away from
  KOReader itself; if the plugin then crashes, the device is unusable
  without a reboot.
- Anything here is untestable in the emulator and untestable in `busted`
  (FFI). It rides on device validation only — which is the trade for
  working at this level.

---

## W6 — OCR / handwriting recognition

**Read `.agents/planning/fastnote-ocr-landscape-research.md` first and do
not redo it.** It already covers what the device can do, what Kobo ships
(MyScript `iink`, commercially licensed — a legal dead end for reuse),
candidate open engines, and a recommended milestone 1.

### The constraint that shapes everything

`lib/stroke.lua` stores `pts = {x1,y1,w1, x2,y2,w2, ...}` — position and a
pre-baked width. **No per-point timestamps, no raw pressure.** Online
handwriting recognizers (the MyScript class, the ones that feel magic) want
a timestamped stroke stream. Without timestamps you are doing offline,
bitmap-based OCR on a rasterized page.

### The one decision worth making early

Adding timestamps is cheap *now* and expensive later — the storage format is
young and the user base is one person. It is a breaking change to
`Stroke.toTable`/`fromTable` and the SVG `<metadata>` JSON block, so it
needs a version field in that metadata and an ADR (ADR-001 covers the
storage format; this extends it).

Deciding "no timestamps ever" is also fine — but decide it deliberately
rather than by default, because reversing it later means every page written
in the meantime lacks the data.

### Milestone 1 (D3: the cheap proof-of-concept)

Per the research doc, in order:

1. **A ruled / structured writing mode** for the canvas — constrained line
   height and margins. This is worth having on its own merits, and it is
   the same trick that makes Kobo's own Advanced Notebook tractable.
   Unconstrained freeform handwriting is a much harder recognition problem.
2. **Rasterize a page and run it through the Tesseract already in
   `koreader-base`** (KOReader uses it for scanned PDF/DjVu; see
   `frontend/ui/data/ocr.lua`). Zero new native dependencies. Expect
   mediocre accuracy — it's a print-OCR engine. The point is to answer "is
   this the right ballpark on this CPU" before anyone cross-compiles
   anything.
3. Only if (2) is clearly inadequate, move to a purpose-built handwriting
   model (Calamari, or a small trained CRNN/CTC) and accept the ARM
   cross-compile lift. **No cross-compile machinery exists in this repo
   today** beyond what `koreader-base` provides.

### On "training mode"

The user wants to write sample A–Z sheets and have the system learn their
hand. Be honest about the architecture: **training does not happen on the
Kobo.** A realistic shape is three parts —

1. **On device:** a guided capture mode that prompts for each letter and
   saves labelled samples. This part is genuinely fun and entirely within
   the plugin's existing capabilities.
2. **On desktop:** the actual training run (Tesseract fine-tuning, or a
   CRNN trained on the samples), producing a model artifact.
3. **Back on device:** drop the artifact in and select it.

Part 1 can be built long before parts 2 and 3 exist, and it's useful on its
own — a labelled corpus of the user's handwriting is the prerequisite for
every engine choice, so capturing it early costs nothing and keeps options
open.

### Pitfalls

- Don't let OCR drive a rewrite of the stroke model beyond timestamps. ADR-002
  (StrokeBuffer is the source of truth) still holds; OCR is a consumer.
- Recognition latency on this CPU is measured in seconds. Design it as an
  explicit "convert this page" action with a progress indicator, never as
  something that runs while writing.
- Accuracy will disappoint at first. The user has already said they don't
  mind slow or inaccurate — hold them to that framing and ship the ugly
  version rather than polishing toward a target this hardware won't hit.

---

## Cross-cutting obligations

**ADRs likely needed** (`.agents/ADRs/`, next free number is ADR-008):
folder storage model (W4), thumbnail generation and caching strategy (W3),
stroke timestamps if adopted (W6). One per settled decision, written when
it's settled — not in advance.

**Doc-as-code:** every code change carries its doc change in the same pass —
`fastnote.conf.example` for new config keys, the plugin AGENTS.md File Map
for new files, the relevant `.agents/notes/` topic for changed behavior. See
`.github/skills/documentation-as-code/SKILL.md`.

**Testing:** `lib/` and `model/` are pure Lua and get specs first.
`drawingcanvas.lua`, `ui/`, and `input/` cannot be unit-tested here —
emulator for widget/gesture behavior, device for raw input and refresh. See
`.github/skills/test-driven-development/SKILL.md`.

**Test gate:** `cd plugins/fastnote.koplugin && busted spec/` before any
commit.
