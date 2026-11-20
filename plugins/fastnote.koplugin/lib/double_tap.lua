--[[--
lib/double_tap.lua

Pure double-tap detection with an injectable clock. No KOReader or FFI
dependencies, so it is unit-testable.

Two taps make a double tap when they are in the same zone, no more than
window_ms apart, and no more than slop_px apart (straight-line distance). A
completed double tap resets the zone, so a triple tap is a double tap plus a
single tap, not two double taps.

KOReader's own double_tap gesture is not used for this: enabling it delays
every single tap on the widget (the arrows, the exit button) while the
detector waits to see if a second tap follows. This detector delays nothing;
the caller decides what a lone first tap does.

@module fastnote.lib.double_tap
--]]--

local DoubleTap = {}
DoubleTap.__index = DoubleTap

local DEFAULT_WINDOW_MS = 350   -- longest gap between the two taps
local DEFAULT_SLOP_PX   = 60    -- farthest the second tap may land from the first (5 mm)

--- Create a detector.
-- @table opts  Optional: window_ms, slop_px, and clock_fn, a function returning
--              milliseconds. Callers on a device must pass a monotonic clock;
--              the fallback is whole-second wall time, which is too coarse for
--              a 350 ms window and exists only so the module loads on its own.
function DoubleTap.new(opts)
    opts = opts or {}
    return setmetatable({
        window_ms = opts.window_ms or DEFAULT_WINDOW_MS,
        slop_px   = opts.slop_px   or DEFAULT_SLOP_PX,
        _clock    = opts.clock_fn or function() return os.time() * 1000 end,
        _first    = {},   -- zone key -> {t, x, y} of the tap waiting for a partner
    }, DoubleTap)
end

--- Record a tap and report whether it completes a double tap.
-- @string key  Zone the tap landed in; taps in different zones never pair.
-- @number x, y Tap position in pixels.
-- @treturn boolean
function DoubleTap:register(key, x, y)
    local now   = self._clock()
    local first = self._first[key]
    if first and now - first.t <= self.window_ms then
        local dx, dy = x - first.x, y - first.y
        if dx * dx + dy * dy <= self.slop_px * self.slop_px then
            self._first[key] = nil
            return true
        end
    end
    self._first[key] = {t = now, x = x, y = y}
    return false
end

--- True while a first tap in this zone is still waiting for its partner.
-- A first tap older than the window no longer counts as waiting.
function DoubleTap:pending(key)
    local first = self._first[key]
    return first ~= nil and self._clock() - first.t <= self.window_ms
end

--- Forget every waiting first tap.
function DoubleTap:reset()
    self._first = {}
end

return DoubleTap
