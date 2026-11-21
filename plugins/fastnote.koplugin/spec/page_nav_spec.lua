--[[--
Unit tests for lib/page_nav.

Pure layout and state logic for the chrome strip's page controls: where the
exit, previous, number, next and menu zones sit, which control a tap hits,
what the arrows look like on the current page, and where the user lands after
a page is removed.

Run with: busted spec/page_nav_spec.lua
--]]--

local plugin_dir = (debug.getinfo(1,"S").source:match("@(.+)/spec/") or "..")
package.path = plugin_dir .. "/?.lua;" .. plugin_dir .. "/lib/?.lua;" .. package.path

local nav = require("lib/page_nav")

local CHROME_H = 106

-- True when two {x,y,w,h} rects share no pixel (half-open bounds).
local function disjoint(a, b)
    return a.x + a.w <= b.x or b.x + b.w <= a.x
end

describe("page_nav.chrome_layout", function()

    describe("portrait width 1264", function()
        local layout = nav.chrome_layout(1264, CHROME_H)

        it("returns the five zones", function()
            assert.is_table(layout.exit)
            assert.is_table(layout.prev)
            assert.is_table(layout.number)
            assert.is_table(layout.next)
            assert.is_table(layout.menu)
        end)

        it("zones are pairwise disjoint", function()
            local names = {"exit", "prev", "number", "next", "menu"}
            for i = 1, #names do
                for j = i + 1, #names do
                    assert.is_true(disjoint(layout[names[i]], layout[names[j]]),
                                   names[i] .. " overlaps " .. names[j])
                end
            end
        end)

        it("exit is flush left and menu is flush right", function()
            assert.equals(0, layout.exit.x)
            assert.equals(1264, layout.menu.x + layout.menu.w)
        end)

        it("every zone is as tall as the chrome strip", function()
            for __, name in ipairs({"exit", "prev", "number", "next", "menu"}) do
                assert.equals(CHROME_H, layout[name].h, name)
                assert.equals(0, layout[name].y, name)
            end
        end)

        it("leaves a dead gutter between exit and prev, and next and menu", function()
            assert.is_true(layout.prev.x > layout.exit.x + layout.exit.w)
            assert.is_true(layout.next.x + layout.next.w < layout.menu.x)
        end)

        it("prev and next are the same width and at least the minimum target", function()
            assert.equals(layout.prev.w, layout.next.w)
            assert.is_true(layout.prev.w >= 106)
        end)

        it("number sits between prev and next with no gap", function()
            assert.equals(layout.prev.x + layout.prev.w, layout.number.x)
            assert.equals(layout.number.x + layout.number.w, layout.next.x)
        end)
    end)

    describe("landscape width 1680", function()
        local portrait  = nav.chrome_layout(1264, CHROME_H)
        local landscape = nav.chrome_layout(1680, CHROME_H)

        it("the arrows widen while the number zone stays the same size", function()
            assert.is_true(landscape.prev.w > portrait.prev.w)
            assert.is_true(math.abs(landscape.number.w - portrait.number.w) <= 1)
        end)
    end)

    describe("odd widths", function()
        it("an odd leftover pixel goes to the number zone, never a gap", function()
            local layout = nav.chrome_layout(1265, CHROME_H)
            assert.equals(layout.prev.x + layout.prev.w, layout.number.x)
            assert.equals(layout.number.x + layout.number.w, layout.next.x)
        end)
    end)

    describe("mirrored (right-to-left) layout", function()
        local plain    = nav.chrome_layout(1264, CHROME_H)
        local mirrored = nav.chrome_layout(1264, CHROME_H, {mirrored = true})

        it("swaps which side the previous and next zones are on", function()
            assert.equals(plain.prev.x, mirrored.next.x)
            assert.equals(plain.next.x, mirrored.prev.x)
        end)

        it("keeps exit and menu where they are", function()
            assert.equals(plain.exit.x, mirrored.exit.x)
            assert.equals(plain.menu.x, mirrored.menu.x)
        end)
    end)

    describe("too narrow for arrows", function()
        local layout = nav.chrome_layout(480, CHROME_H)

        it("drops the arrows and gives the whole middle to the number", function()
            assert.is_nil(layout.prev)
            assert.is_nil(layout.next)
            assert.equals(layout.exit.x + layout.exit.w, layout.number.x)
            assert.equals(layout.menu.x, layout.number.x + layout.number.w)
        end)
    end)
end)

describe("page_nav.hit_test", function()
    local layout = nav.chrome_layout(1264, CHROME_H)

    it("finds each zone from its centre", function()
        for __, name in ipairs({"exit", "prev", "number", "next", "menu"}) do
            local r = layout[name]
            local hit = nav.hit_test(layout, r.x + math.floor(r.w / 2),
                                     math.floor(CHROME_H / 2))
            assert.equals(name, hit)
        end
    end)

    it("a tap in a dead gutter hits nothing", function()
        local gutter_x = layout.exit.x + layout.exit.w + 1
        assert.is_nil(nav.hit_test(layout, gutter_x, 10))
    end)

    it("uses half-open bounds: the left edge is in, the right edge is out", function()
        local r = layout.number
        assert.equals("number", nav.hit_test(layout, r.x, 10))
        assert.equals("next",   nav.hit_test(layout, r.x + r.w, 10))
    end)

    it("below the chrome strip hits nothing", function()
        local r = layout.number
        assert.is_nil(nav.hit_test(layout, r.x + 5, CHROME_H))
    end)

    it("above the screen or left of it hits nothing", function()
        assert.is_nil(nav.hit_test(layout, 10, -1))
        assert.is_nil(nav.hit_test(layout, -1, 10))
    end)

    it("works on a layout with no arrows", function()
        local narrow = nav.chrome_layout(480, CHROME_H)
        local r = narrow.number
        assert.equals("number", nav.hit_test(narrow, r.x + 10, 10))
    end)
end)

describe("page_nav.arrow_state", function()

    it("page 1 disables the previous arrow", function()
        local s = nav.arrow_state(1, 5, false)
        assert.equals("disabled", s.prev)
    end)

    it("a middle page enables both arrows", function()
        local s = nav.arrow_state(3, 5, false)
        assert.equals("enabled", s.prev)
        assert.equals("next",    s.next)
    end)

    it("the last page offers to create a page when forward is allowed", function()
        local s = nav.arrow_state(5, 5, false)
        assert.equals("create", s.next)
    end)

    it("the last page disables forward when navigation is blocked", function()
        local s = nav.arrow_state(5, 5, true)
        assert.equals("disabled", s.next)
    end)

    it("the blocked flag does not affect a page that has a successor", function()
        local s = nav.arrow_state(2, 5, true)
        assert.equals("next", s.next)
    end)

    it("a single-page notebook has no previous page", function()
        local s = nav.arrow_state(1, 1, false)
        assert.equals("disabled", s.prev)
        assert.equals("create",   s.next)
    end)
end)

describe("page_nav.format_indicator", function()

    it("formats current and total with spaces around the slash", function()
        assert.equals("3 / 12", nav.format_indicator(3, 12))
    end)

    it("clamps an index above the count", function()
        assert.equals("5 / 5", nav.format_indicator(9, 5))
    end)

    it("clamps an index below one", function()
        assert.equals("1 / 5", nav.format_indicator(0, 5))
    end)

    it("treats a missing or zero count as a single page", function()
        assert.equals("1 / 1", nav.format_indicator(1, 0))
        assert.equals("1 / 1", nav.format_indicator(nil, nil))
    end)
end)

describe("page_nav.page_after_remove", function()

    it("lands on the page that slid into the removed slot", function()
        assert.equals(3, nav.page_after_remove(3, 5))
    end)

    it("removing the last page lands on the new last page", function()
        assert.equals(4, nav.page_after_remove(5, 5))
    end)

    it("removing the first page lands on the new first page", function()
        assert.equals(1, nav.page_after_remove(1, 5))
    end)

    it("refuses to remove the only page", function()
        assert.is_nil(nav.page_after_remove(1, 1))
    end)

    it("refuses an out-of-range index", function()
        assert.is_nil(nav.page_after_remove(0, 5))
        assert.is_nil(nav.page_after_remove(6, 5))
    end)
end)

describe("page_nav.strip_height", function()

    it("is the full strip height when the strip is shown", function()
        assert.equals(106, nav.strip_height(false, 106))
    end)

    it("is zero when the strip is hidden, so drawing may use the whole page", function()
        assert.equals(0, nav.strip_height(true, 106))
    end)
end)

describe("page_nav.top_peek_zone", function()

    it("spans the full width at the top edge", function()
        local zone = nav.top_peek_zone(1264, 80)
        assert.same({x = 0, y = 0, w = 1264, h = 80}, zone)
    end)
end)

describe("page_nav.tab_rect", function()

    it("is centred horizontally at the top edge", function()
        local tab = nav.tab_rect(1264, 240, 40)
        assert.equals(0, tab.y)
        assert.equals(240, tab.w)
        assert.equals(40, tab.h)
        assert.equals(math.floor((1264 - 240) / 2), tab.x)
    end)

    it("never extends past the screen on a very narrow width", function()
        local tab = nav.tab_rect(200, 240, 40)
        assert.equals(0, tab.x)
        assert.equals(200, tab.w)
    end)
end)

describe("page_nav.margin_zones", function()
    local zones = nav.margin_zones(1264, 1680, 106, 70)

    it("puts a margin strip against each side edge", function()
        assert.equals(0, zones.left.x)
        assert.equals(70, zones.left.w)
        assert.equals(1264, zones.right.x + zones.right.w)
        assert.equals(70, zones.right.w)
    end)

    it("starts below the top strip and runs to the bottom of the page", function()
        assert.equals(106, zones.left.y)
        assert.equals(1680 - 106, zones.left.h)
        assert.equals(zones.left.y, zones.right.y)
        assert.equals(zones.left.h, zones.right.h)
    end)

    it("starts at the top edge when the strip is hidden", function()
        local hidden = nav.margin_zones(1264, 1680, 0, 70)
        assert.equals(0, hidden.left.y)
        assert.equals(1680, hidden.left.h)
    end)

    it("the two strips never overlap", function()
        assert.is_true(zones.left.x + zones.left.w <= zones.right.x)
    end)

    it("returns nil when the screen is too narrow to leave a drawing area", function()
        assert.is_nil(nav.margin_zones(200, 1680, 106, 70))
    end)
end)

describe("page_nav.in_margin", function()
    local zones = nav.margin_zones(1264, 1680, 106, 70)

    it("is true inside either margin strip below the top strip", function()
        assert.equals("margin_left",  nav.in_margin(zones, 10, 800))
        assert.equals("margin_right", nav.in_margin(zones, 1250, 800))
    end)

    it("is nil in the drawing area", function()
        assert.is_nil(nav.in_margin(zones, 600, 800))
    end)

    it("uses half-open bounds", function()
        assert.equals("margin_left", nav.in_margin(zones, 69, 800))
        assert.is_nil(nav.in_margin(zones, 70, 800))
    end)

    it("is nil above the margin strips", function()
        assert.is_nil(nav.in_margin(zones, 10, 50))
    end)

    it("is nil when there are no margin zones", function()
        assert.is_nil(nav.in_margin(nil, 10, 800))
    end)
end)
