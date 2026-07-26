--[[--
model/notebook.lua — one notebook: an ordered list of pages in a UUID directory.

Storage layout:
  <base_dir>/<uuid>/
    notebook.lua      -- metadata: name, created_at, last_edited, last_page, pages
    page_001.svg
    page_002.svg
    ...

notebook.lua is a plain Lua table returned by a Lua chunk (loadfile-compatible).
--]]--

local Notebook = {}
Notebook.__index = Notebook

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Seed once at module load; avoids collision when create() is called rapidly.
math.randomseed(os.time())
math.random(); math.random(); math.random()   -- discard first few values

local _nb_seq = 0   -- per-process sequence counter for UUID uniqueness

local function _uuid()
    _nb_seq = _nb_seq + 1
    -- Format: nb_<timestamp>_<seq3>_<rand6>
    -- Alphabetical sort of directory names = chronological creation order.
    return string.format("nb_%d_%03d_%06d", os.time(), _nb_seq, math.random(0, 999999))
end

local function _write_meta(nb)
    local f = io.open(nb.dir .. "/notebook.lua", "w")
    if not f then return false end
    f:write("return {\n")
    f:write(string.format("  name = %q,\n", nb.name))
    f:write(string.format("  created_at = %d,\n", nb.created_at))
    f:write(string.format("  last_edited = %d,\n", nb.last_edited or 0))
    -- Written only once set: absent means "no recorded position", which is how
    -- callers know to fall back to the legacy global state.last_page_index.
    if nb.last_page then
        f:write(string.format("  last_page = %d,\n", nb.last_page))
    end
    f:write("  pages = {\n")
    for _, fname in ipairs(nb._pages) do
        f:write(string.format("    %q,\n", fname))
    end
    f:write("  },\n")
    f:write("}\n")
    f:close()
    return true
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

--- Create a brand-new notebook directory with one blank page.
-- @string name      User-visible name.
-- @string base_dir  Parent directory (the notebooks/ folder).
-- @return Notebook
function Notebook.create(name, base_dir)
    local uuid = _uuid()
    local dir  = base_dir .. "/" .. uuid
    os.execute("mkdir -p " .. dir)

    local now = os.time()
    local nb = setmetatable({
        uuid        = uuid,
        dir         = dir,
        name        = name or "Untitled",
        created_at  = now,
        last_edited = now,
        _pages      = {"page_001.svg"},
    }, Notebook)

    _write_meta(nb)
    return nb
end

--- Load a notebook from an existing directory.
-- @string uuid      The directory name (UUID).
-- @string base_dir  Parent directory (the notebooks/ folder).
-- @return Notebook|nil, string?
function Notebook.load(uuid, base_dir)
    local dir   = base_dir .. "/" .. uuid
    local chunk, err = loadfile(dir .. "/notebook.lua")
    if not chunk then
        return nil, "cannot load notebook " .. uuid .. ": " .. (err or "?")
    end
    local ok, t = pcall(chunk)
    if not ok or type(t) ~= "table" then
        return nil, "corrupt notebook metadata: " .. dir
    end

    return setmetatable({
        uuid        = uuid,
        dir         = dir,
        name        = t.name or "Untitled",
        created_at  = t.created_at or 0,
        last_edited = t.last_edited or 0,
        last_page   = t.last_page,        -- nil = never recorded (pre-W2 metadata)
        _pages      = t.pages or {"page_001.svg"},
    }, Notebook)
end

-- ---------------------------------------------------------------------------
-- Page management
-- ---------------------------------------------------------------------------

--- Number of pages in this notebook.
function Notebook:pageCount()
    return #self._pages
end

--- Absolute path to page N (1-indexed).
-- @number idx  Page index (1..pageCount()).
-- @return string|nil
function Notebook:pagePath(idx)
    local fname = self._pages[idx]
    if not fname then return nil end
    return self.dir .. "/" .. fname
end

--- Clamp an arbitrary page index into [1, pageCount()].
-- nil, a non-number, or an out-of-range index all resolve to a real page —
-- a stored index can outlive the page it pointed at.
-- @return number
function Notebook:clampPage(idx)
    if type(idx) ~= "number" then return 1 end
    return math.max(1, math.min(math.floor(idx), self:pageCount()))
end

--- True when this notebook's directory is still on disk.
-- Guards against a notebook that was moved, renamed or deleted outside the app.
function Notebook:exists()
    local f = io.open(self.dir .. "/notebook.lua", "r")
    if not f then return false end
    f:close()
    return true
end

--- Resolve a page index to something that is safe to open.
-- Clamps idx into range and verifies the notebook itself is still there.
-- Returns nil when the notebook directory is gone or it has no pages at all —
-- callers treat that as "fall back to the browser", never as an error.
--
-- A missing page *file* is deliberately NOT a failure: an SVG is only written
-- on first save, so an undrawn page legitimately has no file yet.
-- @number idx  Desired page index (may be nil or out of range).
-- @return number|nil, string|nil  (clamped index, absolute page path)
function Notebook:resolvePage(idx)
    if self:pageCount() == 0 then return nil end
    if not self:exists() then return nil end
    local page_idx = self:clampPage(idx)
    local path     = self:pagePath(page_idx)
    if not path then return nil end
    return page_idx, path
end

--- Record the page the user was last on, and persist it.
-- Clamped, so a caller cannot store an index this notebook can't reach.
-- @number idx
-- @return number  The clamped index actually stored.
function Notebook:setLastPage(idx)
    self.last_page = self:clampPage(idx)
    _write_meta(self)
    return self.last_page
end

--- Append a new blank page and return its index and path.
-- @return number, string  (new_index, absolute_path)
function Notebook:addPage()
    local n     = #self._pages + 1
    local fname = string.format("page_%03d.svg", n)
    self._pages[n] = fname
    _write_meta(self)
    return n, self.dir .. "/" .. fname
end

--- Remove the page at index idx (1-indexed).
-- Does not delete the SVG file — caller is responsible if needed.
function Notebook:deletePage(idx)
    if idx >= 1 and idx <= #self._pages then
        table.remove(self._pages, idx)
        _write_meta(self)
    end
end

--- Rename this notebook.
function Notebook:rename(new_name)
    self.name = new_name
    _write_meta(self)
end

--- Flush metadata to disk (call after any external mutation).
function Notebook:save()
    _write_meta(self)
end

--- Path where a thumbnail image would be stored (Stage 13 generates it).
-- Caller should check whether the file exists before using it.
function Notebook:getThumbnailPath()
    return self.dir .. "/thumb.png"
end

return Notebook
