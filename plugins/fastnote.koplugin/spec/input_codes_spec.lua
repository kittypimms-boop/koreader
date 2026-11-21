--[[--
Unit tests for lib/input_codes.

Pins the tool-type constants whose meaning differs between the Linux uapi and
KOReader's Elan convention, so the ambiguity stays visible in code.

Run with: busted spec/input_codes_spec.lua
--]]--

package.path = package.path .. ";fastnote.koplugin/?.lua"

local codes = require("lib/input_codes")

describe("input_codes MT tool types", function()

    it("MT_TOOL_FINGER and MT_TOOL_PEN match the Linux uapi values", function()
        assert.equals(0, codes.MT_TOOL_FINGER)
        assert.equals(1, codes.MT_TOOL_PEN)
    end)

    it("value 2 is exposed as MT_TOOL_PALM (Linux uapi name)", function()
        assert.equals(2, codes.MT_TOOL_PALM)
    end)

    it("value 2 keeps its KOReader/Elan name MT_TOOL_ERASER", function()
        assert.equals(2, codes.MT_TOOL_ERASER)
    end)

    it("the two names for value 2 are the same number, not independent constants", function()
        assert.equals(codes.MT_TOOL_ERASER, codes.MT_TOOL_PALM)
    end)

end)
