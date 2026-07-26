--[[--
model/library.lua — all notebooks, plus app-wide state.

Storage layout (under <koreader_data>/fastnote/):
  state.lua           -- app-wide: last_notebook_uuid, last_page_index,
                      -- dark_mode, current_color, pressure_floor
  notebooks/
    <uuid>/           -- one dir per notebook
      notebook.lua    -- per-notebook, incl. last_page (see resolveResume)
      page_001.svg
      ...

Directory scanning uses io.popen("ls") — works on Kobo Linux.

Every path interpolated into a shell command goes through
lib/shell_quote — see that module for why. Paths are machine-generated
UUIDs today, but user-typed folder names are planned, and an unquoted
`rm -rf` is not something to retrofit later.
--]]--

local Notebook    = require("model/notebook")
local shell_quote = require("lib/shell_quote")

local Library = {}
Library.__index = Library

--- Open the library rooted at base_dir (e.g. <datadir>/fastnote).
-- Creates the notebooks sub-directory if missing.
-- @string base_dir  Absolute path (no trailing slash).
function Library.new(base_dir)
    os.execute("mkdir -p " .. shell_quote.quote(base_dir .. "/notebooks"))
    local self = setmetatable({
        base_dir  = base_dir,
        _nbs      = {},   -- uuid -> Notebook
        _order    = {},   -- ordered list of uuids (insertion / mtime order)
    }, Library)
    self:_scan()
    return self
end

-- ---------------------------------------------------------------------------
-- Internal
-- ---------------------------------------------------------------------------

function Library:_nb_dir()
    return self.base_dir .. "/notebooks"
end

function Library:_scan()
    -- Only the directory is quoted; `2>/dev/null | sort` is deliberate shell
    -- syntax, not data.
    local handle = io.popen("ls -1 " .. shell_quote.quote(self:_nb_dir()) ..
                            " 2>/dev/null | sort")
    if not handle then return end
    for entry in handle:lines() do
        local meta = self:_nb_dir() .. "/" .. entry .. "/notebook.lua"
        local f    = io.open(meta, "r")
        if f then
            f:close()
            local nb, err = Notebook.load(entry, self:_nb_dir())
            if nb then
                self._nbs[entry]              = nb
                self._order[#self._order + 1] = entry
            end
        end
    end
    handle:close()
    self:_sortOrder()
end

-- Sort _order by last_edited descending (most recently edited first).
function Library:_sortOrder()
    local nbs = self._nbs
    table.sort(self._order, function(a, b)
        return (nbs[a].last_edited or 0) > (nbs[b].last_edited or 0)
    end)
end

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

function Library:notebookCount()
    return #self._order
end

--- Return notebook by UUID, or nil.
function Library:byUUID(uuid)
    return self._nbs[uuid]
end

--- Return notebook by position (1-indexed), or nil.
function Library:byIndex(idx)
    local uuid = self._order[idx]
    return uuid and self._nbs[uuid]
end

--- Resolve where to resume: which notebook, and which page inside it.
--
-- The single choke-point for "open a notebook" — used by the launch path and
-- by the browser's open callback, so both get the same validation. Returns nil
-- whenever the target cannot be resolved (no stored uuid, notebook deleted,
-- directory moved or renamed, notebook left with no pages); callers fall back
-- to the browser rather than opening a canvas at a dead path.
--
-- Page preference, most to least specific:
--   1. the notebook's own last_page (per-notebook, survives a folder move)
--   2. state.last_page_index, but only when it names *this* notebook — it is a
--      global field and is meaningless for any other one
--   3. page 1
-- The chosen index is clamped to the notebook's real page count.
--
-- @param state  Persisted app state (from readState); may be nil.
-- @param uuid   Notebook to open; defaults to state.last_notebook_uuid.
-- @return Notebook|nil, number|nil, string|nil  (notebook, page index, page path)
function Library:resolveResume(state, uuid)
    state = state or {}
    uuid  = uuid or state.last_notebook_uuid
    if not uuid then return nil end

    local nb = self:byUUID(uuid)
    if not nb then return nil end

    local page_idx = nb.last_page
    if not page_idx and state.last_notebook_uuid == uuid then
        page_idx = state.last_page_index
    end

    local resolved_idx, path = nb:resolvePage(page_idx)
    if not resolved_idx then return nil end
    return nb, resolved_idx, path
end

--- Ordered list of all notebooks.
function Library:all()
    local out = {}
    for _, uuid in ipairs(self._order) do
        out[#out + 1] = self._nbs[uuid]
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Mutations
-- ---------------------------------------------------------------------------

--- Create a new notebook, add it to the library, and return it.
-- @string name  User-visible name (optional, defaults to "Untitled").
function Library:createNotebook(name)
    local nb = Notebook.create(name or "Untitled", self:_nb_dir())
    self._nbs[nb.uuid]            = nb
    self._order[#self._order + 1] = nb.uuid
    self:_sortOrder()
    return nb
end

--- Remove a notebook from the library and delete its directory.
-- @string uuid
function Library:deleteNotebook(uuid)
    local nb = self._nbs[uuid]
    if not nb then return end
    os.execute("rm -rf " .. shell_quote.quote(nb.dir))
    self._nbs[uuid] = nil
    for i, u in ipairs(self._order) do
        if u == uuid then table.remove(self._order, i); break end
    end
end

-- ---------------------------------------------------------------------------
-- App-wide state (last_notebook_uuid, last_page_index)
-- ---------------------------------------------------------------------------

local function _state_path(base_dir)
    return base_dir .. "/state.lua"
end

--- Read persisted state. Returns {} on missing/corrupt file.
function Library:readState()
    local chunk = loadfile(_state_path(self.base_dir))
    if chunk then
        local ok, t = pcall(chunk)
        if ok and type(t) == "table" then return t end
    end
    return {}
end

--- Write state table to disk.
-- Only string and number values are persisted.
function Library:writeState(t)
    local f = io.open(_state_path(self.base_dir), "w")
    if not f then return end
    f:write("return {\n")
    for k, v in pairs(t) do
        local vt = type(v)
        if vt == "string" then
            f:write(string.format("  %s = %q,\n", k, v))
        elseif vt == "number" then
            f:write(string.format("  %s = %d,\n", k, v))
        end
    end
    f:write("}\n")
    f:close()
end

return Library
