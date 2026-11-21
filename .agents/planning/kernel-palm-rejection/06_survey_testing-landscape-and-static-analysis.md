# Testing landscape and static analysis

**Date:** 2026-11-20

Walkthrough of the test layers for the palm-rejection module and the later digitizer driver: what each layer tests, what it cannot, and which static tools fit. Facts about tools are from memory except the apt versions, which were read with `apt-cache policy` on this host on 2026-11-20. Nothing below has been installed or run yet.

## The layers

| Layer | Runs on | Tests | Cannot test | Feedback |
|---|---|---|---|---|
| L0 Lua specs (exist today) | `busted`, plain Lua | `lib/` logic: state machines, config, geometry | FFI readers, widgets, e-ink | ~1 s |
| L1 Userspace C core | gcc/clang on the host | The pure-C verdict logic, with sanitizers, fuzzing, bounded proofs | Anything needing kernel headers or the input core | under 1 s |
| L2 KUnit | Mainline kernel under UML (or QEMU) via `kunit.py` | Core cases and the glue against a real mainline `input_dev` | 4.9 behavior, real SMP races, hardware, userspace file semantics | tens of seconds |
| L3 QEMU rig | x86_64 KVM guest running a 4.9 kernel (ARM `virt` as a 32-bit sanity check) | The built `.ko` against the real 4.9 input core, end to end through `uinput` and evdev | MediaTek and Elan specifics, true timing, power, KOReader on device | seconds per boot |
| L4 Device | The Libra Colour | Captured traces, observer counts, A/B on real strokes, soak | Nothing is off limits, but nothing is repeatable | minutes, manual |
| L5 KOReader integration | Emulator, optional LuaJIT harness over `input.lua` and `gesturedetector.lua` | UI behavior, how KOReader treats muted slots | Raw input, e-ink waveforms | seconds |

Rule of thumb: put every decision in the layer closest to the top that can express it, and only push a test down when the layer above cannot see the behavior.

## KUnit: the tests we would write

KUnit needs kernel 5.5 or later, so it runs on a mainline kernel, never on the device's 4.9. That is why the logic is split into a pure core and a thin glue layer. Suites are named `palmrej_core` and `palmrej_filter`.

**`palmrej_core` (same cases also run in userspace and in Lua, from one fixture file)**
- Fixture replay: each row is a stream of frames plus the expected verdicts and the expected keep/drop mask.
- Invariants: stylus-class values are never dropped, and neither are `ABS_MT_SLOT` and `ABS_MT_TOOL_TYPE`.
- Verdict latching: a contact's verdict is fixed when it starts; a pen arriving later never flips a finger already accepted.
- Blackout boundary with an injected clock: reject at 249 ms, accept at 250 ms, and the `blackout_ms = 0` case.
- Pen release clears proximity: the kernel twin of the Lua bug we just fixed. Plus the stale-pen timeout expiring.
- Eraser latch order-independence: `BTN_STYLUS` before and after the tool-type event, a re-emitted tool type while the tip is down, and the `stylus2` swap setting. Mirrors `spec/eraser_button_spec.lua`.
- Slot mirror persistence: a new contact whose tool type is omitted by the kernel's dedup uses the stored value.
- Bounds: slot out of range or negative, a frame longer than the buffer, an empty frame, a sync-only frame, a missing `TOUCH_MAJOR`.
- Area gate on and off.

**`palmrej_filter` (glue, mainline only)**
- Register the handler and a test sink handler on a fake multitouch `input_dev`, drive frames, and assert what the sink saw: a muted palm produces no new tracking id; pen frames come through unchanged.
- Lookahead mismatch fails open, bumps a counter, and after N misses the module drops to observe mode.
- Mode changes take effect only at a frame boundary.
- Draining: leaving filter mode leaves an already-muted contact muted until it lifts.
- Parameter callbacks reject bad values; the status string has the agreed format.
- The watchdog expiry callback, called directly (no sleeping in tests).
- `connect()` allow-list: attaches only to the matching device and refuses a device with more slots than the core supports.
- Unregistering while a contact is active.

**What KUnit cannot tell us**
- Anything about kernel 4.9 itself: it runs on mainline, and the input core differs between the two.
- Real concurrency. UML is single-CPU, so lock-ordering and race bugs need the QEMU rig.
- Hardware timing, interrupts, i2c, suspend and resume.
- Userspace-facing behavior of the char device, beyond calling the file operations directly.
- Module init and exit as a real load and unload cycle.

## QEMU: the tests we would run

The rig replays fixture frames through `uinput` inside a 4.9 guest, so the module sees them through the real input core, and a capture tool reads the resulting evdev stream and diffs it against expectations.

- The same fixtures, end to end: replay, filter, evdev, diff.
- Load and unload loops (about 100 cycles) with lockdep, KASAN (x86_64 only on 4.9), atomic-sleep checks and kmemleak enabled.
- `rmmod` while `/dev/palmrej` is open (expect EBUSY) and while contacts are down (expect no orphan contacts).
- Watchdog trip using real timers: stop the heartbeat, assert pass-through within the timeout plus one frame.
- SMP stress: parallel sysfs writes while frames flow, with lockdep watching.
- A slow evdev reader overflowing its buffer, to see the `SYN_DROPPED` behavior.
- Fault injection (`failslab`) during module init.
- A 32-bit ARM build and link check, to catch 64-bit division that needs a runtime helper.
- Golden traces: record on the real device in Phase 0, then replay them against the module. This is the highest-value test in the whole project.

**What QEMU cannot tell us:** MediaTek and Elan behavior (no machine model exists), true timing and jitter, power management, secure boot, and how KOReader behaves on the device.

## Other testing worth doing

- **Differential testing:** run the Lua state machine and the C core on the same fixtures and diff the outputs. This is how the Lua oracle's bugs surface.
- **Property-based tests:** generate random valid frame streams and assert the invariants hold.
- **Fuzzing:** AFL++ (in apt here) on the core's frame function, with the invariants as assertions.
- **Bounded model checking:** CBMC (in apt) can prove the invariants for all frames up to a bounded size, which fits a small pure core well.
- **Coverage:** gcov and lcov (in apt) with a branch-coverage review of the core.
- **Poor-man's mutation testing:** flip a comparison in the core by hand and confirm a test fails.
- **Lua side:** busted, luacheck, and the emulator for the page-navigation UI.

## Static analysis and linters

| Tool | What it checks | Fit | Where | Verdict |
|---|---|---|---|---|
| `gcc -Wall -Wextra -Wconversion -Wshadow -Werror`, `-fanalyzer` | Warnings and path-sensitive bugs | Pure core | gcc 15 here | Adopt for the core |
| cppcheck 2.19 | General C defects | Core yes; kernel glue is noisy with macros | apt; already adopted in this workspace for C | Adopt on the core, reuse the workspace config |
| clang-tidy and clang static analyzer 21 | `bugprone-*`, `cert-*`, `clang-analyzer-*` | Core; glue only on mainline built with `LLVM=1` | apt | Adopt on the core |
| `checkpatch.pl` | Kernel style and some common mistakes | Glue | Ships in the kernel tree (the mainline worktree we plan) | Adopt for glue |
| sparse 0.6.4 | Address spaces, endianness, lock-context annotations | Glue; needs a kernel build (`make C=2`) | apt | Adopt for glue |
| Coccinelle 1.3.0 | Semantic patches and kernel `make coccicheck` | Glue | apt | Experiment; writing a small custom rule is a good learning exercise |
| Smatch | Deep kernel checks: locking, null dereferences | Glue; needs a full kernel build | Not in apt; build from source | Experiment later |
| CBMC 6.6 | Proves invariants for bounded inputs | Pure core | apt | Experiment; high learning value |
| Frama-C | Deductive verification | Pure core | Not in apt | Skip for now |
| ast-grep | Custom pattern rules | Already adopted here, supports C | Workspace | Possible for project rules, such as no `printk` in the hot path |
| luacheck | Lua globals and unused variables | Plugin | Not in apt here; the repo has a `.luacheckrc` | Find an install route (the repo warns LuaRocks can fail behind a proxy) |
| shellcheck 0.11 | Shell scripts | Rig scripts | apt; adopted in this workspace | Adopt |
| Kernel `W=1`/`W=2`, `make checkstack`, `kernel-doc -Wall` | Extra warnings, stack use, doc comments | Glue | In the kernel tree | Adopt `W=1` |
| Coverity Scan, CodeQL | Hosted analysis | Optional | Free for open source | Not now |
| MISRA C | Safety coding standard | The kernel is not MISRA compliant; full checks need paid rule text | n/a | Skip; keep the core MISRA-flavored (no allocation, bounded loops, fixed-width integers) |

Runtime checkers (not static, but the kernel's real safety net): KASAN, UBSAN, lockdep, KCSAN (mainline x86_64), kmemleak, `DEBUG_ATOMIC_SLEEP`, `PROVE_RCU`, `failslab`. These belong in every QEMU guest configuration.

Suggested starter set: for the core, gcc warnings as errors, cppcheck, clang-tidy, ASan and UBSan, and a CBMC experiment. For the glue, `checkpatch.pl`, sparse and `W=1` in both the mainline overlay and the 4.9 guest build. Coccinelle and Smatch are later experiments.

All of these would be declared per skill and installed selectively through the install protocol being planned (for example a `kernel-static` group), rather than as one big bundle.
