--[[--
Unit tests for model/notebook.lua.
Run with: busted spec/notebook_spec.lua
--]]--

local plugin_dir = (debug.getinfo(1,"S").source:match("@(.+)/spec/") or "..")
package.path = plugin_dir .. "/?.lua;" .. plugin_dir .. "/lib/?.lua;" ..
               plugin_dir .. "/model/?.lua;" .. package.path

local Notebook    = require("model/notebook")
local shell_quote = require("lib/shell_quote")

describe("Notebook", function()

    local base_dir

    before_each(function()
        base_dir = os.tmpname()
        os.remove(base_dir)
        os.execute("mkdir -p " .. shell_quote.quote(base_dir))
    end)

    after_each(function()
        os.execute("rm -rf " .. shell_quote.quote(base_dir))
    end)

    describe("Notebook.create", function()
        it("creates a directory with notebook.lua", function()
            local nb = Notebook.create("Test", base_dir)
            assert.truthy(nb)
            assert.equal("Test", nb.name)
            assert.equal(1, nb:pageCount())

            local f = io.open(nb.dir .. "/notebook.lua", "r")
            assert.truthy(f)
            f:close()
        end)

        it("sets created_at to a recent timestamp", function()
            local before = os.time()
            local nb = Notebook.create("T", base_dir)
            local after = os.time()
            assert.truthy(nb.created_at >= before and nb.created_at <= after)
        end)

        it("sets last_edited to a recent timestamp", function()
            local before = os.time()
            local nb = Notebook.create("T", base_dir)
            local after = os.time()
            assert.truthy(nb.last_edited >= before and nb.last_edited <= after)
        end)

        it("generates a unique uuid directory name", function()
            local nb1 = Notebook.create("A", base_dir)
            local nb2 = Notebook.create("B", base_dir)
            assert.not_equal(nb1.uuid, nb2.uuid)
        end)
    end)

    describe("Notebook.load", function()
        it("round-trips create → load", function()
            local nb = Notebook.create("Hello", base_dir)
            local nb2, err = Notebook.load(nb.uuid, base_dir)
            assert.is_nil(err)
            assert.equal("Hello", nb2.name)
            assert.equal(nb.uuid, nb2.uuid)
            assert.equal(1, nb2:pageCount())
            assert.equal(nb.last_edited, nb2.last_edited)
        end)

        it("returns nil for a missing directory", function()
            local nb, err = Notebook.load("nonexistent-uuid", base_dir)
            assert.is_nil(nb)
            assert.truthy(err)
        end)
    end)

    describe("Notebook:pagePath", function()
        it("returns a path ending in page_001.svg", function()
            local nb = Notebook.create("X", base_dir)
            local p = nb:pagePath(1)
            assert.truthy(p:find("page_001.svg$"))
        end)

        it("returns nil for out-of-range index", function()
            local nb = Notebook.create("X", base_dir)
            assert.is_nil(nb:pagePath(0))
            assert.is_nil(nb:pagePath(2))
        end)
    end)

    describe("Notebook:addPage", function()
        it("increments pageCount and returns new path", function()
            local nb = Notebook.create("X", base_dir)
            local idx, path = nb:addPage()
            assert.equal(2, idx)
            assert.equal(2, nb:pageCount())
            assert.truthy(path:find("page_002.svg$"))
        end)

        it("persists across load", function()
            local nb = Notebook.create("X", base_dir)
            nb:addPage()
            local nb2 = Notebook.load(nb.uuid, base_dir)
            assert.equal(2, nb2:pageCount())
        end)
    end)

    describe("Notebook:deletePage", function()
        it("removes a page from the list", function()
            local nb = Notebook.create("X", base_dir)
            nb:addPage()
            assert.equal(2, nb:pageCount())
            nb:deletePage(1)
            assert.equal(1, nb:pageCount())
        end)

        it("no-ops for out-of-range index", function()
            local nb = Notebook.create("X", base_dir)
            nb:deletePage(99)
            assert.equal(1, nb:pageCount())
        end)
    end)

    describe("Notebook:rename", function()
        it("changes the name and persists", function()
            local nb = Notebook.create("Old", base_dir)
            nb:rename("New")
            assert.equal("New", nb.name)
            local nb2 = Notebook.load(nb.uuid, base_dir)
            assert.equal("New", nb2.name)
        end)
    end)

    describe("Notebook last_edited", function()
        it("persists after explicit update + save", function()
            local nb = Notebook.create("X", base_dir)
            local t  = os.time() + 100   -- simulate a future save
            nb.last_edited = t
            nb:save()
            local nb2 = Notebook.load(nb.uuid, base_dir)
            assert.equal(t, nb2.last_edited)
        end)
    end)

    -- ── per-notebook resume position (W2) ──────────────────────────────────

    describe("Notebook:setLastPage / last_page", function()
        it("is unset on a freshly created notebook", function()
            local nb = Notebook.create("X", base_dir)
            assert.is_nil(nb.last_page)
        end)

        it("round-trips through save → load", function()
            local nb = Notebook.create("X", base_dir)
            nb:addPage()
            nb:addPage()
            nb:setLastPage(3)

            local nb2 = Notebook.load(nb.uuid, base_dir)
            assert.equal(3, nb2.last_page)
        end)

        it("clamps an index beyond pageCount to the last page", function()
            local nb = Notebook.create("X", base_dir)
            nb:addPage()                      -- 2 pages
            assert.equal(2, nb:setLastPage(99))
            assert.equal(2, Notebook.load(nb.uuid, base_dir).last_page)
        end)

        it("clamps zero, negatives and nil to page 1", function()
            local nb = Notebook.create("X", base_dir)
            assert.equal(1, nb:setLastPage(0))
            assert.equal(1, nb:setLastPage(-5))
            assert.equal(1, nb:setLastPage(nil))
        end)

        it("stays unset for notebooks written before the field existed", function()
            local nb = Notebook.create("X", base_dir)
            -- Rewrite metadata the old way, without a last_page key.
            local f = io.open(nb.dir .. "/notebook.lua", "w")
            f:write('return {\n  name = "X",\n  created_at = 1,\n')
            f:write('  last_edited = 2,\n  pages = {\n    "page_001.svg",\n  },\n}\n')
            f:close()

            assert.is_nil(Notebook.load(nb.uuid, base_dir).last_page)
        end)
    end)

    describe("Notebook:resolvePage", function()
        it("returns the clamped index and its path", function()
            local nb = Notebook.create("X", base_dir)
            nb:addPage()
            local idx, path = nb:resolvePage(2)
            assert.equal(2, idx)
            assert.truthy(path:find("page_002.svg$"))
        end)

        it("clamps an index beyond pageCount instead of failing", function()
            local nb = Notebook.create("X", base_dir)
            local idx, path = nb:resolvePage(99)
            assert.equal(1, idx)
            assert.truthy(path:find("page_001.svg$"))
        end)

        it("clamps a nil or zero index to page 1", function()
            local nb = Notebook.create("X", base_dir)
            assert.equal(1, nb:resolvePage(nil))
            assert.equal(1, nb:resolvePage(0))
        end)

        it("resolves a page whose SVG has never been written", function()
            -- Pages only get an SVG on first save; an undrawn page is blank,
            -- not a dead path.
            local nb = Notebook.create("X", base_dir)
            assert.is_nil(io.open(nb:pagePath(1), "r"))
            assert.equal(1, nb:resolvePage(1))
        end)

        it("returns nil when the notebook directory is gone", function()
            local nb = Notebook.create("X", base_dir)
            os.execute("rm -rf " .. shell_quote.quote(nb.dir))
            assert.is_nil(nb:resolvePage(1))
        end)

        it("returns nil when the notebook has no pages at all", function()
            local nb = Notebook.create("X", base_dir)
            nb:deletePage(1)
            assert.equal(0, nb:pageCount())
            assert.is_nil(nb:resolvePage(1))
        end)
    end)

    describe("Notebook:getThumbnailPath", function()
        it("returns a path ending in thumb.png inside notebook dir", function()
            local nb = Notebook.create("X", base_dir)
            local p  = nb:getThumbnailPath()
            assert.truthy(p:find("thumb%.png$"))
            assert.truthy(p:find(nb.uuid, 1, true))
        end)
    end)

end)
