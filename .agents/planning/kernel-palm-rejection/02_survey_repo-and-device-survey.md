# Repo and device survey

**Date:** 2026-11-18

## Where things live

| Thing | Location |
|---|---|
| Read-only base clone (default branch `master`) | `sandbox-research/github.com/kittypimms-boop/koreader` |
| Editable worktree, branch `kernel-palm-rejection` | `sandbox/github.com/kittypimms-boop/koreader/kernel-palm-rejection` |
| The plugin | `plugins/fastnote.koplugin/` (repo is a host shell for it; KOReader core is unmodified) |
| Repo design docs | `.agents/` at the repo root (not inside the plugin) |

Repo workflow rule: commit straight to `master`, no PRs (ADR-007 in the repo). The worktree branch is for experiments; decide before the first commit whether kernel-side code belongs in this repo at all (see Open questions).

## What the userland palm rejection does today

`lib/palmreject.lua` is a pure-Lua state machine, covered by `spec/palmreject_spec.lua`.

- Input 1: high-level pen events (`down`/`move`/`hover`/`up`) from `lib/pen_statemachine.lua`.
- Input 2: touch slot events (`down`/`move`/`up` with `slot`, `id`, `x`, `y`, `touch_major`) from `input/touchdev.lua`.
- Rule 1, pen-proximity gate: any new touch contact is rejected while the pen is down, hovering, or within `blackout_ms` (default 250) of its last lift.
- Rule 2, area gate: reject when `touch_major > area_threshold`. Off by default (`area_threshold = 0`) and never wired to a config key, so it has never run in production.
- Per-contact verdict is latched at `down` and applied to the contact's `move` and `up` events.
- The clock is injectable (`clock_fn`), which is what makes the timing testable.

The readers (`input/pendev.lua`, `input/touchdev.lua`) are FFI evdev readers that both open the same node, `/dev/input/event1`, because the Elan chip combines pen and touch. They cannot be busted-tested.

## Facts that shape the kernel design

1. **One chip, one input node.** Pen and finger arrive on the same evdev device as multitouch slots. A kernel `input_handler` that attaches to that `input_dev` sees both streams in a single frame order, which is an advantage over the userland two-reader setup.
2. **The roadmap (W5) already rules out two approaches.** hwmon is the wrong subsystem. Raw `/dev/i2c-N` access fights the in-kernel driver. The low-level surface worth using is evdev plus the driver's sysfs attributes.
3. **Never `EVIOCGRAB` the digitizer.** A crash after a grab leaves the device unusable until reboot. The same caution applies to a kernel filter that drops events: it needs a recovery path.
4. **Cheapest hardware signal not yet checked:** whether the chip emits `ABS_MT_TOOL_TYPE == MT_TOOL_PALM` (value 2). `touchdev.lua` does not parse `ABS_MT_TOOL_TYPE` at all. If the controller classifies palms itself, a module has less to do. Verify with `evtest` on device.
5. **Eraser quirk:** the Stylus 2 eraser tip reports `ABS_MT_TOOL_TYPE = 1` (pen). The real signal is `BTN_STYLUS` (or `BTN_STYLUS2`) as a level, latched in `pendev.lua`. A module that classifies pen state has to reproduce this.
6. **Tool-type synthesis must fire once per contact start**, not on every `EV_SYN` (an incident already hit once in this codebase).

## Discrepancy to resolve first: which device?

The request says "Kobo Clara 2 Color". The plugin docs, the roadmap and the `koreader-plugin` skill all say **Kobo Libra Colour** (`KoboMonza`, MTK SoC, Kaleido 3, Elan combo digitizer, Kobo Stylus 2). These are different products with different SoCs and kernels, and the Clara line does not ship with stylus support. Every kernel-side step (toolchain, kernel source, defconfig, module vermagic, driver choice) depends on the answer. See the planner's device-model research in `03_`.

## Constraints from the workspace

- This repo's own rule: project notes under `helper-user/` are personal and gitignored.
- The plugin's Lua conventions apply to the integration work: `__` for throwaway loop variables, `pcall` around all external I/O, no `ffi.cdef` inside callable functions, pure logic in `lib/` with a busted spec, device-only code in `input/`.
- Emulator path must keep working: `use_raw_input = Device:isKobo()` selects raw evdev, and both paths must stay functional. Any kernel-module path is a third, optional source behind a feature check.
