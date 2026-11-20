--[[--
lib/strokebuffer.lua — in-memory list of committed strokes with undo/redo.

Pure Lua; no KOReader runtime dependencies for all methods except repaintTo.
repaintTo(bb) requires the KOReader BlitBuffer and is not busted-testable.

Source of truth for all drawn content on a page. The BlitBuffer in
drawingcanvas.lua is a display cache that is rebuilt by repaintTo after
undo, erase, or rotation.

ASSUMES: lib/stroke.lua available on the require path.
--]]--

local Stroke = require("lib/stroke")

local StrokeBuffer = {}
StrokeBuffer.__index = StrokeBuffer

--- Create a new empty StrokeBuffer.
function StrokeBuffer.new()
    return setmetatable({
        strokes = {},   -- committed strokes (source of truth)
        undone  = {},   -- strokes moved here by undo (available for redo)
        current = nil,  -- stroke in progress (not yet committed)
        current_owner = nil,  -- input path that started `current` (see Owner tag)
    }, StrokeBuffer)
end

-- ---------------------------------------------------------------------------
-- Live drawing
-- ---------------------------------------------------------------------------

-- Owner tag
--
-- On the Kobo three input paths (pen, raw touch, gesture) write into the one
-- current stroke, so any path's move extends another path's stroke and any
-- path's up commits it. Each pen* call may carry an owner string ("pen",
-- "touch", "gesture"). A call with no owner matches any stroke.
--   * trace_fn(op, x, y, owner, open_owner), if set (class or instance), sees
--     every operation with the owner of the stroke open at that moment, so a
--     debug log can show cross-path interference. op is "down", "move" or "up";
--     x and y are nil for "up".
--   * enforce_owner, when true, isolates owners: another owner's move and up
--     are ignored, and another owner's down commits the open stroke instead of
--     silently replacing it. Off by default, which keeps the original behavior.

--- True when a call by `owner` must be ignored for the open stroke.
local function _foreign(self, owner)
    return self.enforce_owner and owner ~= nil
           and self.current_owner ~= nil and owner ~= self.current_owner
end

--- Begin a new stroke at (x, y) with line width w and given color.
-- Clears the redo stack — any new stroke discards redo history.
-- @number x      screen x
-- @number y      screen y
-- @number w      line width at this sample
-- @string color  hex color string (optional, defaults to black)
-- @string owner  input path starting the stroke (optional)
function StrokeBuffer:penDown(x, y, w, color, owner)
    if self.trace_fn then self.trace_fn("down", x, y, owner, self.current_owner) end
    if self.current and _foreign(self, owner) then
        -- Another path's stroke is open: keep it rather than discard it.
        if not self.current:isEmpty() then
            self.strokes[#self.strokes + 1] = self.current
        end
        self.current       = nil
        self.current_owner = nil
    end
    self.current       = Stroke.new(color)
    self.current_owner = owner
    self.current:addPoint(x, y, w)
    self.undone = {}  -- new stroke clears redo history
end

--- Extend the current stroke with a new sample.
-- No-op if penDown has not been called.
function StrokeBuffer:penMove(x, y, w, owner)
    if not self.current then return end
    if self.trace_fn then self.trace_fn("move", x, y, owner, self.current_owner) end
    if _foreign(self, owner) then return end
    self.current:addPoint(x, y, w)
end

--- Commit the current stroke to the strokes list.
-- Discards single-point strokes (no segment to draw).
function StrokeBuffer:penUp(owner)
    if self.current and self.trace_fn then
        self.trace_fn("up", nil, nil, owner, self.current_owner)
    end
    if self.current and _foreign(self, owner) then return end
    if self.current and not self.current:isEmpty() then
        self.strokes[#self.strokes + 1] = self.current
    end
    self.current       = nil
    self.current_owner = nil
end

-- ---------------------------------------------------------------------------
-- Undo / redo
-- ---------------------------------------------------------------------------

--- Undo the last committed stroke.
-- @return Stroke|nil  The removed stroke (caller uses its bbox for repaint).
function StrokeBuffer:undo()
    if #self.strokes == 0 then return nil end
    local s = table.remove(self.strokes)
    self.undone[#self.undone + 1] = s
    return s
end

--- Redo the last undone stroke.
-- @return Stroke|nil  The restored stroke (caller uses its bbox for repaint).
function StrokeBuffer:redo()
    if #self.undone == 0 then return nil end
    local s = table.remove(self.undone)
    self.strokes[#self.strokes + 1] = s
    return s
end

-- ---------------------------------------------------------------------------
-- Erase
-- ---------------------------------------------------------------------------

--- Remove all committed strokes whose hitTest passes within `radius` of (x, y).
-- @return table  Array of removed Stroke objects; caller handles repaint.
function StrokeBuffer:eraseAt(x, y, radius)
    local removed = {}
    local kept    = {}
    for _, s in ipairs(self.strokes) do
        if s:hitTest(x, y, radius) then
            removed[#removed + 1] = s
        else
            kept[#kept + 1] = s
        end
    end
    self.strokes = kept
    -- Erase cannot be undone via redo (undo for erase is a Stage 11 concern)
    self.undone = {}
    return removed
end

-- ---------------------------------------------------------------------------
-- Rendering (KOReader runtime required)
-- ---------------------------------------------------------------------------

--- Replay all committed strokes onto a BlitBuffer.
-- Used after undo/erase/rotation to rebuild the display cache.
-- @param bb       BlitBuffer  destination (should already be bg-filled)
-- @param color_fn optional resolver — one of:
--   • function(stored_hex) → BlitBuffer color  per-stroke color map (dark mode)
--   • BlitBuffer color value                    flat override for all strokes
--   • nil                                       each stroke uses its own stored color
function StrokeBuffer:repaintTo(bb, color_fn)
    for _, s in ipairs(self.strokes) do
        local override
        if type(color_fn) == "function" then
            override = color_fn(s.color)
        else
            override = color_fn  -- nil or a flat BlitBuffer color (backward compat)
        end
        s:paintTo(bb, override)
    end
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

--- True if there are no committed strokes and no stroke in progress.
function StrokeBuffer:isEmpty()
    return #self.strokes == 0 and self.current == nil
end

--- True if there are committed strokes.
function StrokeBuffer:hasStrokes()
    return #self.strokes > 0
end

-- ---------------------------------------------------------------------------
-- Serialisation
-- ---------------------------------------------------------------------------

--- Serialise to a plain Lua table for JSON encoding.
function StrokeBuffer:toTable()
    local out = {}
    for i, s in ipairs(self.strokes) do
        out[i] = s:toTable()
    end
    return {strokes = out}
end

--- Reconstruct a StrokeBuffer from a plain Lua table (from JSON decode).
-- @param t  table  {strokes=[array of stroke tables]}
function StrokeBuffer.fromTable(t)
    local sb = StrokeBuffer.new()
    for _, st in ipairs(t.strokes or {}) do
        sb.strokes[#sb.strokes + 1] = Stroke.fromTable(st)
    end
    return sb
end

return StrokeBuffer
