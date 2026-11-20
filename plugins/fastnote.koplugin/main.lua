--[[--
FastNote entry point.

Routing on open (Stage 9, resume added in W2):
  • 0 notebooks  → create "My Notebook", open canvas directly (first launch)
  • 1 notebook   → open canvas directly (skip browser)
  • 2+ notebooks → resume the last-used notebook + page if it still resolves,
                   otherwise show the notebook browser

Fallback rule: whenever a notebook or page fails to resolve — moved, renamed,
deleted, or simply stale — fall back to the browser, quietly. Never open a
canvas at a dead path and never surface a traceback. The single validation
point is Library:resolveResume; every open path goes through it.
--]]--

local Dispatcher      = require("dispatcher")  -- luacheck:ignore
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DrawingCanvas   = require("drawingcanvas")
local _               = require("gettext")

local FastNote = WidgetContainer:extend{
    name        = "fastnote",
    is_doc_only = false,
}

function FastNote:onDispatcherRegisterActions()
    Dispatcher:registerAction("open_fnote_canvas", {
        category = "none",
        event    = "OpenFnoteCanvas",
        title    = _("Open Fast Note Canvas"),
        general  = true,
    })
end

function FastNote:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function FastNote:addToMainMenu(menu_items)
    menu_items.fast_note = {
        text         = _("Fast Note"),
        sorting_hint = "more_tools",
        callback     = function() self:onOpenFnoteCanvas() end,
    }
end

-- ---------------------------------------------------------------------------
-- Internal: remember where the user is
-- ---------------------------------------------------------------------------

--- Persist the current position, per notebook and app-wide.
-- nb.last_page is the authoritative field (it travels with the notebook
-- directory and works for any number of notebooks). state.last_notebook_uuid /
-- state.last_page_index are still written during the transition so a downgrade
-- doesn't lose the user's place.
local function _rememberPosition(lib, state, nb, page_idx)
    nb:setLastPage(page_idx)          -- also flushes notebook.lua
    state.last_notebook_uuid = nb.uuid
    state.last_page_index    = page_idx
    lib:writeState(state)
end

-- ---------------------------------------------------------------------------
-- Internal: open a canvas for a specific notebook + page
-- ---------------------------------------------------------------------------

function FastNote:_openCanvas(lib, state, nb, page_idx)
    local load_path = nb:pagePath(page_idx)

    -- Load user config (lib/config.lua): finger_draw / rotation_mode /
    -- tighten_delay / tighten_enabled / live_color_refresh / eraser_button /
    -- live_ink_style / debug_input_log.
    -- Missing file or keys fall back to Config.DEFAULTS -- see
    -- .agents/notes/tech-debt.md.
    local Config      = require("lib/config")
    local DataStorage = require("datastorage")
    local conf_path   = DataStorage:getDataDir() .. "/settings/fastnote.conf"
    local cfg         = Config.load(conf_path)

    UIManager:show(DrawingCanvas:new{
        load_path      = load_path,
        page_index     = page_idx,
        page_count     = nb:pageCount(),
        dark_mode      = state.dark_mode == 1,
        current_color  = state.current_color,
        pressure_floor = state.pressure_floor,
        chrome_hidden    = state.chrome_hidden == 1,
        margin_page_turn = state.margin_page_turn == 1,

        finger_draw         = cfg.finger_draw,
        init_rotation_mode  = cfg.rotation_mode,
        tighten_delay       = cfg.tighten_delay,
        tighten_enabled     = cfg.tighten_enabled,
        live_color_refresh  = cfg.live_color_refresh,
        eraser_button       = cfg.eraser_button,
        live_ink_style      = cfg.live_ink_style,
        debug_input_log     = cfg.debug_input_log,

        on_save_callback = function(path)
            nb.last_edited = os.time()
            _rememberPosition(lib, state, nb, page_idx)
        end,

        on_dark_mode_change = function(dm)
            state.dark_mode = dm and 1 or 0
            lib:writeState(state)
        end,

        on_chrome_hidden_change = function(hidden)
            state.chrome_hidden = hidden and 1 or 0
            lib:writeState(state)
        end,

        on_margin_turn_change = function(enabled)
            state.margin_page_turn = enabled and 1 or 0
            lib:writeState(state)
        end,

        on_color_change = function(hex)
            state.current_color = hex
            lib:writeState(state)
        end,

        on_pressure_change = function(val)
            state.pressure_floor = val
            lib:writeState(state)
        end,

        on_show_browser = function()
            self:_showBrowser(lib, state)
        end,

        on_page_forward = function()
            page_idx = page_idx + 1
            if page_idx > nb:pageCount() then
                nb:addPage()
            end
            page_idx = math.min(page_idx, nb:pageCount())
            local path = nb:pagePath(page_idx)
            _rememberPosition(lib, state, nb, page_idx)
            return page_idx, nb:pageCount(), path
        end,

        on_page_back = function()
            if page_idx <= 1 then return nil end
            page_idx = page_idx - 1
            local path = nb:pagePath(page_idx)
            _rememberPosition(lib, state, nb, page_idx)
            return page_idx, nb:pageCount(), path
        end,

        -- Page picker (onPageNumberTap). Unlike on_page_forward, never
        -- extends the notebook -- clamped to existing pages only (the
        -- SpinWidget caller already clamps its value to [1, page_count],
        -- this is a defensive second clamp).
        on_page_jump = function(idx)
            page_idx = nb:clampPage(idx)
            local path = nb:pagePath(page_idx)
            _rememberPosition(lib, state, nb, page_idx)
            return page_idx, nb:pageCount(), path
        end,

        -- Insert a blank page after the given page and open it (hamburger
        -- menu "Insert page after").
        on_page_insert = function(after_idx)
            local new_idx, path = nb:insertPage(after_idx)
            page_idx = new_idx
            _rememberPosition(lib, state, nb, page_idx)
            return page_idx, nb:pageCount(), path
        end,

        -- Remove a page (hamburger menu "Delete page"); the notebook keeps its
        -- SVG under removed/. Returns nil when the removal is refused (only
        -- page, out of range, or the file could not be moved).
        on_page_remove = function(idx)
            local next_idx, kept_path = nb:removePage(idx)
            if not next_idx then return nil end
            page_idx = next_idx
            local path = nb:pagePath(page_idx)
            _rememberPosition(lib, state, nb, page_idx)
            return page_idx, nb:pageCount(), path, kept_path
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Internal: show the notebook browser
-- ---------------------------------------------------------------------------

function FastNote:_showBrowser(lib, state)
    local Browser = require("ui/browser")
    Browser.show(lib, function(nb)
        -- Same validation as the launch path: a row in the browser can hold a
        -- stale reference too (deleted on another device, folder moved).
        self:_resumeOrBrowse(lib, state, nb.uuid)
    end)
end

-- ---------------------------------------------------------------------------
-- Internal: open a notebook if it still resolves, else fall back to the browser
-- ---------------------------------------------------------------------------

--- Resume into uuid (or the last-used notebook when uuid is nil).
-- Returns true when a canvas was opened, false when the browser was shown
-- instead. This is the only place the fallback rule is applied.
function FastNote:_resumeOrBrowse(lib, state, uuid)
    local nb, page_idx = lib:resolveResume(state, uuid)
    if nb then
        self:_openCanvas(lib, state, nb, page_idx)
        return true
    end

    local logger = require("logger")
    logger.info("FastNote: cannot resolve notebook", tostring(uuid or state.last_notebook_uuid),
                "- falling back to the browser")
    self:_showBrowser(lib, state)
    return false
end

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

function FastNote:onOpenFnoteCanvas()
    local DataStorage = require("datastorage")
    local base_dir    = DataStorage:getDataDir() .. "/fastnote"

    local logger = require("logger")
    logger.info("FastNote: data directory =", base_dir)

    local Library = require("model/library")
    local lib     = Library.new(base_dir)
    local state   = lib:readState()

    local count = lib:notebookCount()

    if count == 0 then
        -- First launch: create a default notebook and go straight to canvas.
        local nb = lib:createNotebook("My Notebook")
        self:_openCanvas(lib, state, nb, 1)

    elseif count == 1 then
        -- Single notebook: skip the browser, resume inside it.
        self:_resumeOrBrowse(lib, state, lib:byIndex(1).uuid)

    else
        -- 2+ notebooks: resume the last-used one; the browser is the fallback
        -- when nothing was stored or the stored notebook no longer resolves.
        self:_resumeOrBrowse(lib, state, nil)
    end
end

return FastNote
