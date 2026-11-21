--[[--
Unit tests for lib/double_tap.

Pure double-tap detection with an injectable clock: two taps in the same zone,
close in time and close in place, make a double tap. KOReader's own double_tap
gesture is not used because enabling it delays every single tap on the widget.

Run with: busted spec/double_tap_spec.lua
--]]--

local plugin_dir = (debug.getinfo(1,"S").source:match("@(.+)/spec/") or "..")
package.path = plugin_dir .. "/?.lua;" .. plugin_dir .. "/lib/?.lua;" .. package.path

local DoubleTap = require("lib/double_tap")

local function make_clock(start_ms)
    local clock = {now = start_ms or 0}
    clock.fn      = function() return clock.now end
    clock.advance = function(delta) clock.now = clock.now + delta end
    return clock
end

local function make_detector(opts)
    local clock = make_clock(1000)
    local merged = {window_ms = 350, slop_px = 60, clock_fn = clock.fn}
    for key, value in pairs(opts or {}) do merged[key] = value end
    return DoubleTap.new(merged), clock
end

describe("DoubleTap", function()

    it("the first tap is never a double tap", function()
        local detector = make_detector()
        assert.is_false(detector:register("top", 100, 20))
    end)

    it("a second tap in the same zone within the window is a double tap", function()
        local detector, clock = make_detector()
        detector:register("top", 100, 20)
        clock.advance(200)
        assert.is_true(detector:register("top", 110, 25))
    end)

    it("a second tap exactly at the window edge still counts", function()
        local detector, clock = make_detector()
        detector:register("top", 100, 20)
        clock.advance(350)
        assert.is_true(detector:register("top", 100, 20))
    end)

    it("a second tap one millisecond after the window starts a new pair", function()
        local detector, clock = make_detector()
        detector:register("top", 100, 20)
        clock.advance(351)
        assert.is_false(detector:register("top", 100, 20))
    end)

    it("a late second tap becomes the first tap of the next pair", function()
        local detector, clock = make_detector()
        detector:register("top", 100, 20)
        clock.advance(500)
        detector:register("top", 100, 20)
        clock.advance(100)
        assert.is_true(detector:register("top", 100, 20))
    end)

    it("a second tap farther than the slop is not a double tap", function()
        local detector, clock = make_detector()
        detector:register("top", 100, 20)
        clock.advance(100)
        assert.is_false(detector:register("top", 400, 20))
    end)

    it("a second tap exactly at the slop distance still counts", function()
        local detector, clock = make_detector()
        detector:register("top", 100, 20)
        clock.advance(100)
        assert.is_true(detector:register("top", 160, 20))
    end)

    it("measures the slop as straight-line distance", function()
        local detector, clock = make_detector()
        detector:register("top", 100, 100)
        clock.advance(100)
        -- 50 px across and 50 px down is about 70.7 px apart, over the 60 px slop.
        assert.is_false(detector:register("top", 150, 150))
    end)

    it("taps in different zones do not pair", function()
        local detector, clock = make_detector()
        detector:register("margin_left", 30, 500)
        clock.advance(100)
        assert.is_false(detector:register("margin_right", 30, 500))
    end)

    it("a completed double tap resets, so a triple tap is a double plus a single", function()
        local detector, clock = make_detector()
        detector:register("top", 100, 20)
        clock.advance(100)
        assert.is_true(detector:register("top", 100, 20))
        clock.advance(100)
        assert.is_false(detector:register("top", 100, 20))
    end)

    it("pending() is true after a first tap and false once the pair completes", function()
        local detector, clock = make_detector()
        assert.is_false(detector:pending("top"))
        detector:register("top", 100, 20)
        assert.is_true(detector:pending("top"))
        clock.advance(100)
        detector:register("top", 100, 20)
        assert.is_false(detector:pending("top"))
    end)

    it("reset() forgets every waiting first tap", function()
        local detector, clock = make_detector()
        detector:register("top", 100, 20)
        detector:reset()
        clock.advance(100)
        assert.is_false(detector:register("top", 100, 20))
    end)

    it("works with the defaults when no options are given", function()
        local detector = DoubleTap.new()
        assert.is_false(detector:register("top", 0, 0))
    end)
end)
