--[[--
model/notebook.lua — one notebook: an ordered list of pages in a UUID directory.

Storage layout:
  <base_dir>/<uuid>/
    notebook.lua      -- metadata: name, created_at, last_edited, last_page, pages
    page_001.svg
    page_002.svg
    ...

notebook.lua is a plain Lua table returned by a Lua chunk (loadfile-compatible).

The one shell-out here (`mkdir -p`) quotes its path via lib/shell_quote.
--]]--

local shell_quote = require("lib/shell_quote")
local page_nav    = require("lib/page_nav")

local Notebook = {}
Notebook.__index = Notebook

local function _file_exists(path)
    local f = io.open(path, "r")
    if not f then return false end
    f:close()
    return true
end

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
    os.execute("mkdir -p " .. shell_quote.quote(dir))

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

--- Pick a page file name that no page uses and no file on disk occupies.
-- A page's position in the list is separate from its file name, so after a
-- delete or an insert the count no longer identifies a free name. Numbering
-- continues from the highest number in use, and skips any name whose file
-- still exists (a removed page's SVG must never come back as a new blank page).
local function _free_page_file(nb)
    local in_use  = {}
    local highest = #nb._pages
    for __, fname in ipairs(nb._pages) do
        in_use[fname] = true
        local number = tonumber(fname:match("^page_(%d+)%.svg$"))
        if number and number > highest then highest = number end
    end
    local number = highest + 1
    while true do
        local fname = string.format("page_%03d.svg", number)
        if not in_use[fname] and not _file_exists(nb.dir .. "/" .. fname) then
            return fname
        end
        number = number + 1
    end
end

--- Insert a new blank page after page after_idx and return its index and path.
-- after_idx 0 inserts at the front; an index past the end appends.
-- last_page follows the page it pointed at, so an insert before it shifts it.
-- @number after_idx  Page to insert after (0..pageCount()).
-- @return number, string  (new_index, absolute_path)
function Notebook:insertPage(after_idx)
    local count    = #self._pages
    local position = 0
    if type(after_idx) == "number" then
        position = math.max(0, math.min(math.floor(after_idx), count))
    end
    local fname   = _free_page_file(self)
    local new_idx = position + 1
    table.insert(self._pages, new_idx, fname)
    if self.last_page and self.last_page >= new_idx then
        self.last_page = self.last_page + 1
    end
    _write_meta(self)
    return new_idx, self.dir .. "/" .. fname
end

--- Append a new blank page and return its index and path.
-- @return number, string  (new_index, absolute_path)
function Notebook:addPage()
    return self:insertPage(#self._pages)
end

--- Move a page's SVG into <notebook>/removed/ so a removal can be undone by hand.
-- A name already taken there gets a numeric suffix, so an earlier removal is
-- never overwritten.
-- @return string|nil  New path, or nil when the file could not be moved.
local function _move_to_removed(nb, fname)
    local removed_dir = nb.dir .. "/removed"
    os.execute("mkdir -p " .. shell_quote.quote(removed_dir))
    local stem   = fname:gsub("%.svg$", "")
    local target = removed_dir .. "/" .. fname
    local suffix = 0
    while _file_exists(target) do
        suffix = suffix + 1
        target = string.format("%s/%s_%d.svg", removed_dir, stem, suffix)
    end
    if not os.rename(nb.dir .. "/" .. fname, target) then return nil end
    return target
end

--- Remove page idx from the notebook, keeping its drawing recoverable.
-- The SVG moves to <notebook>/removed/ instead of being deleted. The only page
-- cannot be removed (a notebook with no pages cannot be opened). If the file
-- cannot be moved nothing changes, so a failed removal never loses a drawing.
-- last_page follows the page it pointed at.
-- @number idx  Page to remove (1-based).
-- @return number|nil, string|nil
--   (page to show next, path the SVG was kept at or nil if it was never saved)
--   or (nil, "out_of_range"|"only_page"|"move_failed").
function Notebook:removePage(idx)
    local count = #self._pages
    if type(idx) ~= "number" or idx ~= math.floor(idx)
            or idx < 1 or idx > count then
        return nil, "out_of_range"
    end
    local next_idx = page_nav.page_after_remove(idx, count)
    if not next_idx then return nil, "only_page" end

    local fname   = self._pages[idx]
    local kept_at = nil
    if _file_exists(self.dir .. "/" .. fname) then
        kept_at = _move_to_removed(self, fname)
        if not kept_at then return nil, "move_failed" end
    end

    table.remove(self._pages, idx)
    if self.last_page then
        if self.last_page > idx then self.last_page = self.last_page - 1 end
        self.last_page = math.max(1, math.min(self.last_page, #self._pages))
    end
    _write_meta(self)
    return next_idx, kept_at
end

--- Remove the page at index idx (1-indexed) from the list only.
-- Low-level: does not touch the SVG file and permits an empty notebook. UI
-- code uses removePage(), which keeps the drawing and refuses the last page.
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
