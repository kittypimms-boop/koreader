--[[--
spec/strokebuffer_spec.lua — unit tests for lib/strokebuffer.lua
Run: busted spec/strokebuffer_spec.lua   (from plugin root)
--]]--

package.path = package.path .. ";fastnote.koplugin/?.lua"

local StrokeBuffer = require("lib/strokebuffer")

describe("StrokeBuffer", function()

    -- ── Construction ────────────────────────────────────────────────────────

    describe("new", function()
        it("starts empty", function()
            local sb = StrokeBuffer.new()
            assert.is_true(sb:isEmpty())
            assert.equals(0, #sb.strokes)
            assert.equals(0, #sb.undone)
            assert.is_nil(sb.current)
        end)
    end)

    -- ── penDown / penMove / penUp ────────────────────────────────────────────

    describe("live drawing", function()
        it("penDown starts a current stroke", function()
            local sb = StrokeBuffer.new()
            sb:penDown(10, 20, 3, "#000000")
            assert.is_not_nil(sb.current)
            assert.equals(1, sb.current:pointCount())
        end)

        it("penMove before penDown is a no-op", function()
            local sb = StrokeBuffer.new()
            sb:penMove(5, 5, 2)
            assert.is_nil(sb.current)
        end)

        it("penUp with a single-point stroke discards it", function()
            local sb = StrokeBuffer.new()
            sb:penDown(10, 10, 2)
            sb:penUp()
            assert.is_true(sb:isEmpty())
        end)

        it("penUp commits a multi-point stroke", function()
            local sb = StrokeBuffer.new()
            sb:penDown(0, 0, 2)
            sb:penMove(10, 10, 2)
            sb:penUp()
            assert.equals(1, #sb.strokes)
            assert.is_nil(sb.current)
        end)

        it("committed stroke preserves color", function()
            local sb = StrokeBuffer.new()
            sb:penDown(0, 0, 2, "#ff0000")
            sb:penMove(10, 10, 2)
            sb:penUp()
            assert.equals("#ff0000", sb.strokes[1].color)
        end)

        it("multiple strokes accumulate", function()
            local sb = StrokeBuffer.new()
            for i = 1, 5 do
                sb:penDown(i, i, 2)
                sb:penMove(i+10, i+10, 2)
                sb:penUp()
            end
            assert.equals(5, #sb.strokes)
        end)
    end)

    -- ── isEmpty / isDirty ───────────────────────────────────────────────────

    describe("isEmpty / isDirty", function()
        it("isEmpty is false after committing a stroke", function()
            local sb = StrokeBuffer.new()
            sb:penDown(0, 0, 2)
            sb:penMove(5, 5, 2)
            sb:penUp()
            assert.is_false(sb:isEmpty())
        end)

        it("isDirty is false when empty", function()
            assert.is_false(StrokeBuffer.new():isDirty())
        end)

        it("isDirty is true after committing", function()
            local sb = StrokeBuffer.new()
            sb:penDown(0, 0, 2)
            sb:penMove(5, 5, 2)
            sb:penUp()
            assert.is_true(sb:isDirty())
        end)
    end)

    -- ── undo / redo ─────────────────────────────────────────────────────────

    describe("undo / redo", function()
        local function make_sb_with_strokes(n)
            local sb = StrokeBuffer.new()
            for i = 1, n do
                sb:penDown(i*10, 0, 2)
                sb:penMove(i*10 + 5, 5, 2)
                sb:penUp()
            end
            return sb
        end

        it("undo returns nil on empty buffer", function()
            assert.is_nil(StrokeBuffer.new():undo())
        end)

        it("undo removes the last stroke", function()
            local sb = make_sb_with_strokes(3)
            sb:undo()
            assert.equals(2, #sb.strokes)
        end)

        it("undo moves the stroke to undone", function()
            local sb = make_sb_with_strokes(1)
            local removed = sb:undo()
            assert.is_not_nil(removed)
            assert.equals(1, #sb.undone)
        end)

        it("redo returns nil when nothing undone", function()
            assert.is_nil(StrokeBuffer.new():redo())
        end)

        it("redo restores the last undone stroke", function()
            local sb = make_sb_with_strokes(2)
            sb:undo()
            sb:redo()
            assert.equals(2, #sb.strokes)
            assert.equals(0, #sb.undone)
        end)

        it("multiple undo/redo cycles are stable", function()
            local sb = make_sb_with_strokes(3)
            sb:undo(); sb:undo()
            assert.equals(1, #sb.strokes)
            assert.equals(2, #sb.undone)
            sb:redo()
            assert.equals(2, #sb.strokes)
            assert.equals(1, #sb.undone)
        end)

        it("penDown clears redo history", function()
            local sb = make_sb_with_strokes(2)
            sb:undo()
            assert.equals(1, #sb.undone)
            -- New stroke clears redo
            sb:penDown(99, 99, 2)
            sb:penMove(100, 100, 2)
            sb:penUp()
            assert.equals(0, #sb.undone)
        end)
    end)

    -- ── stroke grouping ──────────────────────────────────────────────────────

    describe("stroke grouping (group_id > 0)", function()

        it("strokes with same group_id are undone together", function()
            local sb = StrokeBuffer.new()
            -- group 1: two strokes
            sb:penDown(0, 0, 2, nil, 1); sb:penMove(5, 5, 2); sb:penUp()
            sb:penDown(10, 0, 2, nil, 1); sb:penMove(15, 5, 2); sb:penUp()
            -- group 2: one stroke
            sb:penDown(20, 0, 2, nil, 2); sb:penMove(25, 5, 2); sb:penUp()
            assert.equals(3, #sb.strokes)

            local bundle = sb:undo()   -- undoes group 2
            assert.equals(2, #sb.strokes)
            assert.equals(1, #bundle)

            local bundle2 = sb:undo()  -- undoes group 1 (both strokes)
            assert.equals(0, #sb.strokes)
            assert.equals(2, #bundle2)
        end)

        it("redo restores the full group at once", function()
            local sb = StrokeBuffer.new()
            sb:penDown(0, 0, 2, nil, 1); sb:penMove(5, 5, 2); sb:penUp()
            sb:penDown(10, 0, 2, nil, 1); sb:penMove(15, 5, 2); sb:penUp()
            sb:undo()
            assert.equals(0, #sb.strokes)
            sb:redo()
            assert.equals(2, #sb.strokes)
        end)

        it("group_id=0 still undoes one stroke at a time", function()
            local sb = StrokeBuffer.new()
            for i = 1, 3 do
                sb:penDown(i, 0, 2, nil, 0)
                sb:penMove(i+5, 5, 2)
                sb:penUp()
            end
            sb:undo()
            assert.equals(2, #sb.strokes)
            sb:undo()
            assert.equals(1, #sb.strokes)
        end)

        it("mixed groups: ungrouped strokes before a group undo correctly", function()
            local sb = StrokeBuffer.new()
            sb:penDown(0, 0, 2, nil, 0); sb:penMove(5, 5, 2); sb:penUp()  -- ungrouped
            sb:penDown(10, 0, 2, nil, 5); sb:penMove(15, 5, 2); sb:penUp() -- group 5
            sb:penDown(20, 0, 2, nil, 5); sb:penMove(25, 5, 2); sb:penUp() -- group 5
            -- undo removes group 5 (2 strokes)
            sb:undo()
            assert.equals(1, #sb.strokes)
            assert.equals(0, sb.strokes[1].group_id)
            -- undo removes the ungrouped stroke
            sb:undo()
            assert.equals(0, #sb.strokes)
        end)

        it("group_id is preserved through serialisation round-trip", function()
            local sb = StrokeBuffer.new()
            sb:penDown(0, 0, 2, "#ff0000", 7); sb:penMove(5, 5, 2); sb:penUp()
            local sb2 = StrokeBuffer.fromTable(sb:toTable())
            assert.equals(7, sb2.strokes[1].group_id)
        end)
    end)

    -- ── eraseAt ─────────────────────────────────────────────────────────────

    describe("eraseAt", function()
        it("returns empty list when nothing hit", function()
            local sb = StrokeBuffer.new()
            sb:penDown(100, 100, 2)
            sb:penMove(200, 100, 2)
            sb:penUp()
            local removed = sb:eraseAt(0, 0, 5)
            assert.equals(0, #removed)
            assert.equals(1, #sb.strokes)
        end)

        it("removes a stroke whose segment is within radius", function()
            local sb = StrokeBuffer.new()
            sb:penDown(0, 50, 2)
            sb:penMove(100, 50, 2)
            sb:penUp()
            local removed = sb:eraseAt(50, 50, 10)
            assert.equals(1, #removed)
            assert.equals(0, #sb.strokes)
        end)

        it("only removes strokes that are hit", function()
            local sb = StrokeBuffer.new()
            sb:penDown(0, 0, 2); sb:penMove(10, 0, 2); sb:penUp()
            sb:penDown(100, 100, 2); sb:penMove(110, 100, 2); sb:penUp()
            local removed = sb:eraseAt(5, 0, 5)
            assert.equals(1, #removed)
            assert.equals(1, #sb.strokes)
        end)

        it("eraseAt clears redo history", function()
            local sb = StrokeBuffer.new()
            sb:penDown(0, 50, 2); sb:penMove(100, 50, 2); sb:penUp()
            sb:penDown(0, 0, 2); sb:penMove(10, 0, 2); sb:penUp()
            sb:undo()
            assert.equals(1, #sb.undone)
            sb:eraseAt(50, 50, 10)
            assert.equals(0, #sb.undone)
        end)
    end)

    -- ── toTable / fromTable round-trip ───────────────────────────────────────

    describe("serialisation", function()
        it("empty buffer round-trips", function()
            local sb = StrokeBuffer.new()
            local sb2 = StrokeBuffer.fromTable(sb:toTable())
            assert.is_true(sb2:isEmpty())
        end)

        it("strokes are preserved through round-trip", function()
            local sb = StrokeBuffer.new()
            sb:penDown(1, 2, 3, "#abcdef")
            sb:penMove(4, 5, 6)
            sb:penUp()
            sb:penDown(10, 20, 1)
            sb:penMove(30, 40, 2)
            sb:penUp()
            local sb2 = StrokeBuffer.fromTable(sb:toTable())
            assert.equals(2, #sb2.strokes)
            assert.equals("#abcdef", sb2.strokes[1].color)
            assert.same(sb.strokes[1].pts, sb2.strokes[1].pts)
            assert.same(sb.strokes[2].pts, sb2.strokes[2].pts)
        end)

        it("undone strokes are not serialised", function()
            local sb = StrokeBuffer.new()
            sb:penDown(0, 0, 2); sb:penMove(5, 5, 2); sb:penUp()
            sb:penDown(10, 10, 2); sb:penMove(15, 15, 2); sb:penUp()
            sb:undo()
            local sb2 = StrokeBuffer.fromTable(sb:toTable())
            assert.equals(1, #sb2.strokes)
        end)
    end)

end)
