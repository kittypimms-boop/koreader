--[[--
lib/page_nav.lua

Pure layout and state logic for the chrome strip's page controls. No KOReader
or FFI dependencies, so everything here is unit-testable.

The strip reads, left to right:

    [exit] gutter [prev] [number] [next] gutter [menu]

Gutters are dead bands so a tap that misses the arrow cannot land on exit or
menu, which are the expensive mistaps. The number zone keeps a fixed width and
the arrows take whatever is left, so on a narrow screen the arrows go away and
the number zone gets the whole middle.

Coordinates are screen pixels. Rects are {x, y, w, h}; all hit tests use
half-open bounds, the same convention as canvas_utils.point_in_zone.

@module fastnote.lib.page_nav
--]]--

local M = {}

-- Widths in pixels at 300 dpi (11.81 px/mm).
M.EXIT_W        = 80    -- exit tap area, flush left
M.MENU_W        = 80    -- menu tap area, flush right
M.GUTTER_W      = 40    -- dead band between exit|prev and next|menu (3.4 mm)
M.NUMBER_W      = 300   -- fixed width of the "n / N" zone (25 mm)
M.MIN_TARGET_W  = 106   -- narrowest acceptable arrow zone (9 mm)

local ZONE_ORDER = {"exit", "prev", "number", "next", "menu"}

local function make_rect(x, w, h)
    return {x = x, y = 0, w = w, h = h}
end

--- Compute the five chrome zones for a screen width.
-- @int   screen_w  Canvas width in pixels.
-- @int   chrome_h  Chrome strip height in pixels.
-- @table opts      Optional: exit_w, menu_w, gutter_w, number_w, min_target_w,
--                  mirrored (swap prev and next for right-to-left layouts).
-- @treturn table   {exit, prev, number, next, menu, chrome_h}. prev and next
--                  are nil when the screen is too narrow for usable arrows.
function M.chrome_layout(screen_w, chrome_h, opts)
    opts = opts or {}
    local exit_w       = opts.exit_w       or M.EXIT_W
    local menu_w       = opts.menu_w       or M.MENU_W
    local gutter_w     = opts.gutter_w     or M.GUTTER_W
    local number_w     = opts.number_w     or M.NUMBER_W
    local min_target_w = opts.min_target_w or M.MIN_TARGET_W

    local layout = {
        chrome_h = chrome_h,
        exit     = make_rect(0, exit_w, chrome_h),
        menu     = make_rect(screen_w - menu_w, menu_w, chrome_h),
    }

    local middle_x = exit_w
    local middle_w = screen_w - exit_w - menu_w
    local side_w   = math.floor((middle_w - 2 * gutter_w - number_w) / 2)

    if side_w < min_target_w then
        layout.number = make_rect(middle_x, middle_w, chrome_h)
        return layout
    end

    -- An odd leftover pixel goes to the number zone so the three middle zones
    -- stay contiguous.
    local number_actual_w = middle_w - 2 * gutter_w - 2 * side_w
    local left_x   = middle_x + gutter_w
    local number_x = left_x + side_w
    local right_x  = number_x + number_actual_w

    local left  = make_rect(left_x,  side_w, chrome_h)
    local right = make_rect(right_x, side_w, chrome_h)
    layout.number = make_rect(number_x, number_actual_w, chrome_h)

    if opts.mirrored then
        layout.prev, layout.next = right, left
    else
        layout.prev, layout.next = left, right
    end
    return layout
end

--- Which chrome zone contains a point.
-- @table layout  Result of chrome_layout().
-- @number x, y   Screen coordinates.
-- @treturn string|nil  "exit" | "prev" | "number" | "next" | "menu", or nil
--                      for a gutter or any point outside the strip.
function M.hit_test(layout, x, y)
    if y < 0 or y >= layout.chrome_h then return nil end
    for __, name in ipairs(ZONE_ORDER) do
        local zone = layout[name]
        if zone and x >= zone.x and x < zone.x + zone.w then
            return name
        end
    end
    return nil
end

--- What the previous and next arrows offer on the current page.
-- @int     idx             Current page (1-based).
-- @int     count           Number of pages.
-- @boolean forward_blocked True when canvas_utils.should_block_forward_nav
--                          says a new page may not be created from here.
-- @treturn table  {prev = "enabled"|"disabled",
--                  next = "next"|"create"|"disabled"}
function M.arrow_state(idx, count, forward_blocked)
    idx   = idx or 1
    count = count or 1

    local prev_state = (idx > 1) and "enabled" or "disabled"

    local next_state
    if idx < count then
        next_state = "next"
    elseif forward_blocked then
        next_state = "disabled"
    else
        next_state = "create"
    end

    return {prev = prev_state, next = next_state}
end

--- The "n / N" readout text.
-- A missing or zero count reads as a single page; the index is clamped.
-- @treturn string
function M.format_indicator(idx, count)
    local total = 1
    if type(count) == "number" and count >= 1 then
        total = math.floor(count)
    end
    local current = 1
    if type(idx) == "number" then
        current = math.max(1, math.min(math.floor(idx), total))
    end
    return string.format("%d / %d", current, total)
end

--- Which page to show after page idx is removed from a notebook of count pages.
-- The page that slid into the removed slot, or the new last page when the
-- last one was removed.
-- @int idx    Page being removed (1-based).
-- @int count  Page count before the removal.
-- @treturn number|nil  New current page, or nil when the removal is refused
--                      (the only page, or an index out of range).
function M.page_after_remove(idx, count)
    if type(idx) ~= "number" or type(count) ~= "number" then return nil end
    if count < 2 then return nil end
    if idx < 1 or idx > count then return nil end
    return math.min(idx, count - 1)
end

return M
