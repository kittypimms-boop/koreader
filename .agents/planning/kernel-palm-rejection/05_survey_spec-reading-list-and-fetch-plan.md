# Spec reading list and fetch plan

**Date:** 2026-11-19

Reading list and fetch plan for the kernel palm-rejection project. Status key: **fetched** = the planner read it this session; **local** = already in a clone on disk; **not fetched** = named from memory or from a pointer in the repo, URL unchecked; **not public** = expected to be behind an NDA or a login.

## Reading list

| # | Resource | Why it matters here | Where | Status |
|---|---|---|---|---|
| 1 | Multi-touch protocol (type B) | Slots, `ABS_MT_TRACKING_ID`, tool types, what a "contact" is. The whole filter design rests on it. | kernel `Documentation/input/multi-touch-protocol.rst` (v4.9: `.txt`) | not fetched |
| 2 | Input event codes | `SYN_DROPPED`, `BTN_TOOL_*`, `BTN_STYLUS`, `ABS_MT_*` meanings | kernel `Documentation/input/event-codes.rst` | not fetched |
| 3 | Input programming and handler API | `input_register_handler`, `connect`/`disconnect`, filter semantics | `Documentation/input/input-programming.rst`, `Documentation/driver-api/input.rst` | not fetched |
| 4 | `input.c`, `input-mt.c`, `evdev.c` at tag v4.9 | The real filter, dedup and grab behavior. Short enough to read in full. | `raw.githubusercontent.com/torvalds/linux/v4.9/drivers/input/` | fetched (planner, `input.c`, `input-mt.c`) |
| 5 | `input-event-codes.h`, `input.h` | Exact `MT_TOOL_*`, `EVIOC*` values | `include/uapi/linux/` | not fetched |
| 6 | uinput | The test-injection path in the QEMU rig | `Documentation/input/uinput.rst` | not fetched |
| 7 | KUnit docs: start, usage, style, running tips, `kunit.py` run wrapper | Kernel TDD | `docs.kernel.org/dev-tools/kunit/` | fetched (planner) |
| 8 | `drivers/input/tests/input_test.c` | Model for a KUnit test with a real `input_dev` | mainline master | fetched (planner) |
| 9 | Kbuild for out-of-tree modules | `Makefile`, `obj-m`, `modules_prepare`, vermagic | `Documentation/kbuild/modules.rst` (v4.9: `modules.txt`) | not fetched |
| 10 | Locking, hrtimers, gdb debugging | Atomic-context rules, timers, kernel debugging in QEMU | `Documentation/kernel-hacking/locking.rst`, `timers/hrtimers.rst`, `dev-tools/gdb-kernel-debugging.rst` | not fetched |
| 11 | Kobo GPL kernel source for the Libra Colour | Kernel version, the Elan driver, the tool-type values it emits | `github.com/kobolabs/Kobo-Reader`, `hw/mt8113-libraC_vision7/` (split `.tar.zst`) | directory listing fetched; archive contents not read |
| 12 | Kobo toolchain and `koxtoolchain` | Compiler that matches the device kernel | `Kobo-Reader/toolchain/`, `github.com/koreader/koxtoolchain` | fetched (planner, README) |
| 13 | KOReader Kobo scripts and input code | Grab behavior, `insmod` pattern, slot handling | `platform/kobo/koreader.sh`, `enable-wifi.sh`, `frontend/device/input.lua`, `gesturedetector.lua` | local |
| 14 | MobileRead Kobo Developer's Corner | Kernel and boot-chain facts from other developers | `mobileread.com/forums` (secure-boot bypass thread `showthread.php?p=4609616` found) | search hit only; not read |
| 15 | `pencil.koplugin` and `eraser.koplugin` | Community prior art for the Elan chip and Stylus 2 eraser signal | summarized in the fork's `.agents/planning/pencil-koplugin-research.md` | local summary |
| 16 | Upstream `elants_i2c.c` and its binding | Finger-side reference for Phase 6; no pen support | `drivers/input/touchscreen/`, `Documentation/devicetree/bindings/input/touchscreen/elan,elants_i2c.yaml` | fetched (planner, `elants_i2c.c`) |
| 17 | libinput palm-detection design | How userland palm heuristics are specified (cross-check for your rules) | `wayland.freedesktop.org/libinput/doc/latest/palm-detection.html` | not fetched |
| 18 | QEMU: QMP schema and docs; virtme-ng | Input injection limits, guest boot recipes | `qapi/ui.json` in QEMU, `qemu.org/docs`, `github.com/arighi/virtme-ng` | fetched (planner, `ui.json`, virtme-ng README) |
| 19 | Learning material | Concepts when the kernel docs are terse. Old APIs, so use it for ideas only. | LDD3 (`lwn.net/Kernel/LDD3/`), Bootlin kernel and driver training slides, `kernelnewbies.org` | not fetched |
| 20 | Elan controller datasheet and pen protocol | Needed only for Phase 6 pen support | vendor | **not public**; the Kobo tarball driver is the practical source |
| 21 | MediaTek MT8113 reference manual | SoC internals | vendor | **not public**; only what the kernel source reveals |

Open question the reading list cannot settle: the fork's docs call the Stylus 2 a "Wacom EMR" pen while the controller is an Elan combo chip. Which pen technology the Stylus 2 uses decides whether pen reports follow a Wacom-style or an Elan-style format. The Kobo tarball driver should answer it.

## Fetch plan

1. Put a `specs-manifest.yaml` in this project folder: one row per document with `url`, `local_path`, `license`, `sha256`, `fetched_at`.
2. Fetch only freely published sources (kernel docs and source are GPL, QEMU and virtme-ng are open). Do not fetch from paywalled or login-gated pages.
3. Save HTML pages as Markdown under `evidence/specs/` (the document-conversion skill handles HTML to Markdown). Record `source_sha256` in each file's frontmatter so changes upstream are detectable.
4. Keep large archives (the Kobo kernel tarball) outside the notes tree and record only the sha256 and the paths you extracted.
5. Vendor datasheets (rows 20 and 21) are bring-your-own. Never fetch them from unofficial mirrors.

## Slotting into a specs library later

The workspace already has a protocol for this: skills announce docs through a `*.spec-sources.yaml` sidecar, converted Markdown lives in `<skill>/references/spec-docs/`, `discover_spec_targets` finds unannounced folders, and `search_specs {spec: "<slug>", query: "..."}` does hybrid keyword plus vector lookup. Upstream hashes are tracked in `spec-lock.json`.

Retrieval options, cheapest first:
- **Skill topic list:** index the spec in the owning skill's `SKILL.md` (the protocol requires it).
- **Path-scoped instruction:** an `.instructions.md` with `applyTo: kernel/**/*.c` that says "look up `linux-input` with `search_specs` before changing handler code". Cheap and realistic.
- **Hook injection:** a hook that attaches the top spec headlines for the file being edited, as the existing librarian hook does for prompts. Feasible, but adds tokens and noise on every edit, so try it only after the first two prove too passive.
