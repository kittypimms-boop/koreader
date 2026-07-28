--[[--
spec/shell_quote_spec.lua — unit tests for lib/shell_quote.lua

Two layers of coverage, deliberately:
  1. String-level assertions on the exact quoted form.
  2. A real-shell round trip (os.execute / io.popen), because a quoting
     helper that only satisfies a string comparison proves nothing about
     the shell it exists to protect.

Run: busted spec/shell_quote_spec.lua   (from plugin root)
--]]--

package.path = package.path .. ";fastnote.koplugin/?.lua"

local shell_quote = require("lib/shell_quote")
local quote = shell_quote.quote

describe("lib/shell_quote", function()

    -- ── quote: exact output form ──────────────────────────────────────────

    describe("quote", function()

        it("wraps a plain path in single quotes", function()
            assert.equal("'/tmp/fastnote'", quote("/tmp/fastnote"))
        end)

        it("keeps a path containing spaces as one shell word", function()
            assert.equal("'/tmp/My Notes'", quote("/tmp/My Notes"))
        end)

        it("escapes an embedded single quote as '\\''", function()
            -- it's  ->  'it'\''s'
            assert.equal("'it'\\''s'", quote("it's"))
        end)

        it("escapes every single quote, not just the first", function()
            assert.equal("'a'\\''b'\\''c'", quote("a'b'c"))
        end)

        it("quotes a string that is nothing but a single quote", function()
            assert.equal("''\\'''", quote("'"))
        end)

        it("neutralises a command separator", function()
            assert.equal("'notes; rm -rf /'", quote("notes; rm -rf /"))
        end)

        it("neutralises && and || chaining", function()
            assert.equal("'a && b || c'", quote("a && b || c"))
        end)

        it("neutralises $(...) command substitution", function()
            assert.equal("'$(whoami)'", quote("$(whoami)"))
        end)

        it("neutralises backtick command substitution", function()
            assert.equal("'`id`'", quote("`id`"))
        end)

        it("neutralises a glob", function()
            assert.equal("'*'", quote("*"))
        end)

        it("neutralises a variable reference", function()
            assert.equal("'$HOME'", quote("$HOME"))
        end)

        it("leaves a backslash alone (no interior escapes inside '...')", function()
            assert.equal("'a\\b'", quote("a\\b"))
        end)

        it("quotes the empty string as ''", function()
            assert.equal("''", quote(""))
        end)

        it("quotes a newline without splitting the word", function()
            assert.equal("'a\nb'", quote("a\nb"))
        end)

        it("rejects a non-string argument rather than coercing it", function()
            -- A nil path reaching a shell command is a bug, not a value to
            -- silently paper over.
            assert.has_error(function() quote(nil) end)
            assert.has_error(function() quote(42) end)
            assert.has_error(function() quote({}) end)
        end)

    end)

    -- ── real shell round trip ─────────────────────────────────────────────
    --
    -- These run actual /bin/sh commands. Every path they touch lives under a
    -- fresh os.tmpname() directory, and every command in here is itself
    -- quoted with the helper under test.

    describe("real shell round trip", function()

        local base

        before_each(function()
            base = os.tmpname()
            os.remove(base)
            os.execute("mkdir -p " .. quote(base))
        end)

        after_each(function()
            os.execute("rm -rf " .. quote(base))
        end)

        local HOSTILE = "it's a $(date) `id` && rm -rf * ; \"x\""

        it("creates and lists back a directory whose name is hostile", function()
            os.execute("mkdir -p " .. quote(base .. "/" .. HOSTILE))

            local handle = io.popen("ls -1 " .. quote(base) .. " 2>/dev/null | sort")
            local entries = {}
            for entry in handle:lines() do entries[#entries + 1] = entry end
            handle:close()

            assert.same({ HOSTILE }, entries)
        end)

        it("does not execute a command substitution in the name", function()
            -- If $(...) were expanded, the canary would exist and the
            -- directory would be named something else entirely.
            local canary = base .. "/canary-must-not-exist"
            local name   = "sub $(touch " .. canary .. ")"

            os.execute("mkdir -p " .. quote(base .. "/" .. name))

            local f = io.open(canary, "r")
            assert.is_nil(f)

            local probe = io.open(base .. "/" .. name .. "/.probe", "w")
            assert.truthy(probe)
            probe:close()
        end)

        it("does not execute an appended rm in the name", function()
            -- Unquoted, `mkdir -p <base>/x; rm -rf sentinel` run from <base>
            -- deletes the sentinel. Quoted, the whole thing is one directory
            -- name and the sentinel survives.
            local sentinel = io.open(base .. "/sentinel", "w")
            sentinel:write("keep me")
            sentinel:close()

            local name = "x; rm -rf sentinel"
            os.execute("cd " .. quote(base) .. " && mkdir -p " .. quote(name))

            local survivor = io.open(base .. "/sentinel", "r")
            assert.truthy(survivor)
            assert.equal("keep me", survivor:read("*a"))
            survivor:close()
        end)

        it("rm -rf removes exactly the hostile directory and nothing else", function()
            local keep = io.open(base .. "/keep", "w")
            keep:write("x")
            keep:close()

            local victim = base .. "/" .. HOSTILE
            os.execute("mkdir -p " .. quote(victim))
            os.execute("rm -rf " .. quote(victim))

            local handle = io.popen("ls -1 " .. quote(base) .. " 2>/dev/null | sort")
            local entries = {}
            for entry in handle:lines() do entries[#entries + 1] = entry end
            handle:close()

            assert.same({ "keep" }, entries)
        end)

    end)

end)
