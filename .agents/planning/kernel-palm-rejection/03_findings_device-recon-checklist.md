# Device recon checklist

**Date:** 2026-11-18

Run these on the Kobo over ssh or telnet (read-only; nothing here changes device state). Paste the output under each heading as you collect it. Questions are ordered by how much they gate.

## Q1. Which exact model?

```bash
cat /proc/device-tree/model
cat /mnt/onboard/.kobo/version
tail -n 12 /proc/cpuinfo
```

Also note the device line in KOReader's startup log. Then check for a pen: in `/proc/bus/input/devices`, does any device advertise `BTN_TOOL_PEN` in its `B: KEY=` bitmap, or `ABS_MT_PRESSURE` in `B: ABS=`? If not, there is no pen digitizer on this unit.

## Q2. Which kernel, and does it match a Kobo source tag?

```bash
uname -a
zcat /proc/config.gz | grep -E 'MODULES|MODVERSIONS|MODULE_SIG|LOCALVERSION|SMP|PREEMPT'
```

## Q3. Can modules load at all?

```bash
ls /lib/modules/"$(uname -r)"
cat /proc/modules
```

The real test is the Phase 0 `hello.ko`.

## Q4. Is there a safe shell?

```bash
id
```

Confirm the shell is root, and that it survives a KOReader crash (start the telnet or ssh server outside KOReader if possible).

## Q5. Which digitizer chip and stock driver?

```bash
ls -l /sys/bus/i2c/devices/*/driver
cat /sys/bus/i2c/devices/*/name
ls /sys/bus/i2c/drivers
dmesg | grep -i -E 'elan|ekth|touch|i2c'
cat /sys/class/input/event1/device/name
ls /sys/firmware/devicetree/base
```

## Q6. One combined device or two?

```bash
cat /proc/bus/input/devices
cat /proc/bus/input/handlers
```

Then run `evtest` on each node (read-only; do not grab). Docs for the Libra Colour say pen and touch share event1; verify on the target model.

## Q7. The free hardware signal

With a palm resting on the panel, does `evtest` show `ABS_MT_TOOL_TYPE` changing to 2 (`MT_TOOL_PALM`)? Record `touch_major` for a finger tap versus a resting palm as well; those two numbers are the area-gate calibration data.

## Q8. Recovery path (needed before Phase 6 only)

Is there a spare unit, and a known recovery route (firmware reflash)? A bad module cannot brick the device (reboot clears it); an unbound stock driver can leave the panel dead until a power cycle.

## Additions from the senior planner review (all read-only)

```bash
uname -r; cat /proc/version          # /proc/version names the GCC that built the kernel: match it
zcat /proc/config.gz | grep -E 'MODVERSIONS|MODULE_SIG|PREEMPT|SMP|HZ=|NO_HZ|DEBUG_ATOMIC|LOCKDEP|INPUT_UINPUT|INPUT_EVDEV'
cat /proc/bus/input/handlers          # any other filter handlers?
cat /sys/class/input/event1/device/capabilities/ev
cat /sys/class/input/event1/device/capabilities/key
cat /sys/class/input/event1/device/capabilities/abs
cat /sys/class/input/event1/device/properties
evtest --query /dev/input/event1 EV_ABS ABS_MT_TOUCH_MAJOR; echo $?   # is the axis advertised?
ls /drivers/*/                        # where Kobo keeps out-of-tree .ko files
ls /tmp/MiniClock 2>/dev/null && echo "MiniClock present -> KOReader will EVIOCGRAB"
```

Record three `evtest /dev/input/event1` traces (do not use `--grab`): (1) pen hover, write, lift, then leave hover range; (2) a palm resting while writing; (3) finger taps and drags. These become the first fixtures (see 04, section C3).

Why the grab check matters: an `EVIOCGRAB` by KOReader makes the kernel skip every filter, so a filter module would silently do nothing (04, gap 1).
