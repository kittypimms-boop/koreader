# Plan: Kernel-module palm rejection and home-grown digitizer driver (Kobo, fastnote)

**Date:** 2026-11-18
**Status:** Proposed
---

> Living plan and handoff. Drafted from a planner pass plus the repo survey (`02_`). Verification tags:
> **[V]** verified this session against a repo file or a fetched page; **[U]** not verified, check before relying on it.
> Every kernel API detail below is **[U] for the device kernel (4.9.x)** until checked against that tree's headers.









## 1. Goal and motivation

- **Goal:** learn kernel module and driver development by replacing fastnote's userland palm rejection with a kernel-assisted one, then writing a minimal digitizer driver of your own.
- **Current state:** `lib/palmreject.lua` (pen-proximity gate, 250 ms blackout, optional area gate) fed by two FFI readers on the same `/dev/input/event1`.
- **Desired state:** a module that observes the digitizer and publishes palm/pen verdicts to userland, a fastnote toggle between software and module backends, and later a home-grown i2c digitizer driver you can bind in place of the stock one.
- **Honest payoff:** userland already sees every event with sub-millisecond latency, so a module adds no functional gain for a 250 ms blackout. The only real in-kernel benefit is `filter()` mode, which protects other readers of the node (KOReader's own UI). This is a learning project and is scoped that way.

## 2. Device: Kobo Libra Colour with Kobo Stylus 2 (confirmed by the user, 2026-11-18)

The device is the Libra Colour (`KoboMonza`), not a Clara; the Clara analysis below is background only. Kobo publishes the Libra Colour kernel at `hw/mt8113-libraC_vision7/` in `kobolabs/Kobo-Reader` [V listing; contents not yet read]. Its kernel version is **unknown**; the only datapoint is a Clara Colour on 4.9.77. KUnit needs kernel 5.5 or later, so assume the device kernel has none.

> **Supersession:** `04_findings_senior-planner-review.md` replaces §3 and §4 of this plan for filter mode, the QEMU rig, KUnit, the gap list and the phase ordering. Filter mode is now a goal, not a stretch. Read 04 first; this file keeps the original framing and the Phase 6 driver staircase (§4c). Claims in 04 tagged [V] were checked by the planner against kernel source at tags and fetched pages; I have not independently re-checked them.

[V] The repo targets the **Libra Colour** (`KoboMonza`, `pressure_event = ABS_MT_PRESSURE`; `frontend/device/kobo/device.lua` lines 533-556).
[V] KOReader's **Clara Colour** is `KoboSpaColour` (`spaColour`), with `touch_snow_protocol = true` and no `pressure_event` (lines 578-598).
[U] Whether the Clara Colour has any pen digitizer: search results conflicted. Without a pen there is no palm-vs-pen problem and Phases 3-5 lose their purpose; Phase 6 (own driver) would still work as finger-only.
"Clara 2 Color" is not a model name KOReader knows. Candidates: Clara Colour (2024), Clara 2E (2022, i.MX-class, not MediaTek [V in `device.lua`]), Clara BW. Resolve with the commands in `03_findings_device-recon-checklist.md` before any toolchain work.

## 3. Architecture decision

| Layer | What runs here | Why |
|---|---|---|
| `input_handler` `event()` (atomic context, may be hardirq/softirq) | O(1) bookkeeping: record pen/tool state, timestamp, set flags. No sleep, no allocation, no log spam. | Only place that sees events in order with minimal latency. |
| `SYN_REPORT` inside `event()` | Compute the per-frame verdict (pen near? blackout? area gate?), push to a spinlock-protected ring, wake the waitqueue. | The verdict is per frame. |
| Timer (`timer_list` or hrtimer, 250 ms) | Expire the blackout. | Idiomatic replacement for `os.clock()` comparison. |
| Workqueue | Only if something must sleep. Probably unused. | Do not invent needs. |
| kthread | Not needed; Phase 1 exercise only. | Polling in a kthread re-implements userland badly. |
| Misc char device, `poll()` + `read()` | Fixed-size verdict records `{u64 ts_ns; u8 verdict; u8 reason; u16 slot}`. | Same fd semantics fastnote already uses on event1; easy from FFI. |
| sysfs / module parameters | Knobs (`blackout_ms`, `area_gate`, `enabled`) and counters. | Scriptable with `echo`. |
| debugfs | Optional ring dump. | Not ABI; fine for learning. |
| Userland (fastnote) | Applies verdicts; keeps the software fallback. | Policy stays in Lua and stays busted-testable. |

- **Primary design (Phases 2-4):** read-only observer, verdicts on `/dev/palmrej`. KOReader and fastnote still read event1 untouched, so the module cannot drop real input.
- **Stretch design (Phase 5):** `filter()` returning true to drop touch frames while the pen is near. Caveats to teach and test: `filter()` drops per event, so a half-dropped frame can corrupt MT type-B state (drop whole frames or emit `ABS_MT_TRACKING_ID = -1`); filters apply to every handler including evdev, so raw readers see the filtered stream and **pen events must never be filtered**; re-verify evdev/filter behavior in the 4.9 source [U].
- **Rejected:** netlink (boilerplate for a first module), ioctl (ABI surface, compat issues, no benefit), and a virtual input device that re-emits accepted touches after grabbing the original (wedge-input hazard of the same class as the `EVIOCGRAB` the roadmap forbids).

## 4. Steps / Phases

| Phase | Goal | Concepts taught | Exit test | Rollback |
|---|---|---|---|---|
| 0 | Recon, host toolchain, `hello.ko` on a VM then on device | `module_init/exit`, printk, vermagic, Kbuild `obj-m`, out-of-tree build | `modinfo` vermagic equals `uname -r`; `insmod`/`rmmod` clean on device | Reboot. Never install into `/lib/modules` or autoload. |
| 1 | Host-only modules in a throwaway VM | See 4a | Per-module, see 4a | VM snapshot revert |
| 2 | Read-only observer on the real digitizer | `id_table` capability match, `connect()` allow-list, ratelimited logging | Counts agree with `evtest /dev/input/event1`; answer the `MT_TOOL_PALM` question | `rmmod`; an observer cannot wedge input |
| 3 | Port the `palmreject.lua` logic to C, publish verdicts | State machine in atomic context, timer, ring buffer, `poll()` mask, locking order | Scripted frames from the Phase 1 fake device produce the expected verdict records | As Phase 2; verdicts are advisory |
| 4 | fastnote toggle and integration | See 4b | busted specs plus on-device A/B of both backends on the same strokes | Toggle defaults to software |
| 5 (stretch) | `filter()` mode | Frame-atomic dropping, MT type-B consistency | Palm touches vanish in `evtest`, pen intact, no stuck touch | `echo observe` over ssh, `rmmod`; heartbeat watchdog auto-reverts |
| 6+ | Home-grown digitizer driver | See 4c | Stock driver rebinds cleanly after every test | Rebind stock driver; power-cycle via reset |

### 4a. Phase 1 modules (each small and separate)

1. **hello + params:** module parameter visible under `/sys/module/<n>/parameters`.
2. **misc device:** `misc_register`, `read`/`poll`, waitqueue; a timer feeds it ticks.
3. **timer and hrtimer:** 250 ms one-shot; `rmmod` with a timer pending must not oops (`del_timer_sync` / `hrtimer_cancel`).
4. **spinlock, ring buffer, atomic-context rules:** build with `CONFIG_DEBUG_ATOMIC_SLEEP` and lockdep; a deliberate `msleep` under a spinlock should be flagged.
5. **fake digitizer `input_dev`:** `input_allocate_device`, `input_mt_init_slots`, `input_mt_slot`, `input_mt_report_slot_state`, `input_register_device`, driven by a timer or sysfs write. Becomes the test fixture for Phases 2-5. Compare against the `uinput` userspace route.
6. **observer `input_handler` on the fake device:** `input_register_handler`, `connect`/`disconnect`, `input_register_handle`, `input_open_device`, `event()`. Survives `rmmod` of both modules in either order.

### 4b. Phase 4 fastnote integration

- Keep `lib/palmreject.lua` unchanged as the fallback.
- Add `lib/palmreject_km.lua` (pure Lua, consumes decoded verdict records, same interface as `palmreject`).
- Add `input/palmdev.lua` (the only FFI file: open `/dev/palmrej` non-blocking, read, decode). Test the record decoder as pure Lua.
- Add `lib/` pure function `detect_backend(stat_fn)` using `/sys/module/palmrej` or the device node, so busted can stub the stat.
- `drawingcanvas.lua` `_pollTouch` consumes whichever backend is selected. Toggle appears only when the module is present.
- Loading: **never autoload.** Menu items "Load kernel module" (confirm first, show `dmesg | tail` on failure) and "Unload". Refuse when `modinfo -F vermagic` differs from `uname -r`; ship per-firmware builds named by kernel version. Root is required [U: confirm with `id` in a shell on the device].
- If a read errors or the module disappears mid-session, revert to software and show a toast.
- Shared test table: put (input sequence, expected verdicts) in `fixtures/palm_cases.json`, consumed by a Lua spec and by a host-side driver for the C code, so the two implementations stay in agreement.
- Follow `lua.instructions.md` in the repo (`__` throwaway, `pcall` on I/O, no `ffi.cdef` in callable functions).

### 4c. Phase 6 staircase (spare, recoverable unit only)

- **6a Recon:** `/sys/bus/i2c/devices`, bound driver, device-tree node (regulators, reset GPIO, interrupts). Find the stock driver in Kobo's kernel source; it may not be `elants_i2c` [U].
- **6b Probe-only stub:** `of_match_table` / `i2c_device_id`, `probe` prints and reads one register. Unbind stock, bind yours (`driver_override` on i2c in 4.9 is [U]; otherwise `new_id`).
- **6c Power and reset:** replicate the stock sequence. Upstream `elants_i2c` enables regulators, waits ~5 ms, releases reset, waits ~20 ms [V]. Unbinding may power the chip off, so rebind needs full init.
- **6d Threaded IRQ:** `devm_request_threaded_irq`, `IRQF_ONESHOT`; hex-dump raw reports, ratelimited.
- **6e Parse and `input_dev`:** finger-only first.
- **6f Pen vs finger:** pen report format is vendor-specific; recover it from the Kobo driver source or raw hex dumps. Then `BTN_TOOL_PEN`, `ABS_MT_PRESSURE`, `BTN_STYLUS`.
- **6g Parity:** same `ABS_*` ranges and resolution, `INPUT_PROP_DIRECT`, axis flips, suspend/resume, and firmware load if the stock driver uses `request_firmware` (chip may stay in recovery mode without it).
- **Safety pattern:** a script over ssh that unbinds, tests for 30 s, then rebinds regardless. Never put unbind in autostart.
- [V] Upstream `elants_i2c.c` has no pen handling at all, reports finger and palm tool types only, and uses a hello packet of four `0x55` bytes plus a threaded IRQ. It is a finger-side reference, not a pen reference.

## 5. Build environment facts

- [V, Nerves-on-Kobo thread] Clara Colour: MT8113-class SoC, 32-bit ARMv7, kernel **4.9.77**, `CONFIG_MODULES=y`, `CONFIG_MODULE_SIG` not set (unsigned modules load; `insmod` of a self-built `f2fs.ko` worked). Stock modules include `wlan_drv_gen4m` and `wmt_*`.
- [V] Kobo publishes kernel and U-Boot source (`hw/`) and a toolchain (`toolchain/`) in `github.com/kobolabs/Kobo-Reader`. The shipped toolchain is GCC 4.9 (C89 default).
- [V] `koreader/koxtoolchain` targets: `kobo`, `kobov4`, `kobov5`, `nickel`. The README says `nickel` is for Kobo's kernels. There is no `kobo-mk7` target.
- Build line: `make -C <kernel-build-dir> M=$PWD ARCH=arm CROSS_COMPILE=<tc>- modules`, against the exact source for `uname -r`, with `/proc/config.gz` as `.config`, then `olddefconfig` and `modules_prepare`.
- `Module.symvers` is needed. If it is missing and `CONFIG_MODVERSIONS=y`, modules will refuse to load; the fallback is one full kernel build.
- [U] Libra Colour probably shares this platform (`isMTK`). Confirm on the device.

## 6. Cross-cutting contracts

- Observer-first: nothing in Phases 2-4 may drop or alter input.
- Software palm rejection stays as the default and as the automatic fallback.
- No autoload, no install into `/lib/modules`, until a phase is proven. A working ssh or telnet shell that survives a KOReader crash is a prerequisite for every on-device `insmod`.
- Pen events are never filtered in Phase 5.
- `lib/` stays pure Lua and busted-tested; FFI stays in `input/`.
- The emulator path (`use_raw_input = false`) keeps working.

## 7. Gaps & Risks (non-obvious constraints and traps)

Top three risks: (1) wrong target or kernel (vermagic or ABI mismatch); (2) wedging input or panicking the device, far likelier in Phase 6 than Phases 2-4; (3) unknown vendor touch protocol plus a possible secure-boot chain.

- [V, roadmap W5] Never `EVIOCGRAB` the digitizer; raw `/dev/i2c` fights the kernel driver; hwmon is the wrong subsystem.
- Eraser tip reports `ABS_MT_TOOL_TYPE = 1` (pen); the real signal is `BTN_STYLUS` or `BTN_STYLUS2` as a level, latched in `pendev.lua`. A module that classifies pen state must reproduce this.
- Tool-type synthesis must fire once per contact start, not per `EV_SYN`.
- Newest Kobos reportedly have a secure-boot chain [U, one MobileRead poster]. It should not affect loading modules into a running kernel, but would block a replacement kernel.
- Vendor Elan combo-chip protocol may differ from upstream `elants_i2c.c`.

## 8. Out of scope

- Replacing or reflashing the Kobo kernel.
- Autoloading the module at boot.
- Re-emitting a virtual input device with the original grabbed.

## 9. Done when (verification gates)

- [ ] Device model and kernel confirmed (`03_`).
- [ ] `hello.ko` loads and unloads on the device with a vermagic match.
- [ ] Phase 1 modules each pass their exit test in the VM.
- [ ] Observer counts match `evtest`; `MT_TOOL_PALM` question answered.
- [ ] C and Lua verdicts agree on `fixtures/palm_cases.json`.
- [ ] fastnote toggle works both ways and degrades to software on module failure.
- [ ] Phase 6: stock driver rebinds cleanly after every experiment.

## Next steps and open questions

1. Answer the device question and run the recon commands in `03_findings_device-recon-checklist.md`.
2. Decide where kernel-side code lives (this repo's `kernel-palm-rejection` branch, or a separate repo; the repo rule is direct-to-`master`, no PRs).
3. Decide whether rejection should protect the shared event path (makes Phase 5 matter) or only fastnote.
4. Start Phase 0 on the laptop VM while recon is pending.
