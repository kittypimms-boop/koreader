--[[--
lib/shell_quote.lua — make an arbitrary string safe to interpolate into a
shell command.

fastnote shells out for three filesystem operations that plain Lua 5.1 can't
do (`mkdir -p`, `rm -rf`, and directory listing via `ls`), so paths get
concatenated into command strings. Every such interpolation must go through
`shell_quote.quote` — see model/library.lua, model/notebook.lua and
drawingcanvas.lua for the call sites.

Why single quotes and nothing else: inside `'...'` POSIX sh performs no
expansion whatsoever — no `$VAR`, no `$(cmd)`, no backticks, no globbing, no
backslash escapes, no word splitting. It is the only quoting form that is
safe for arbitrary bytes. The single quote itself is therefore the one
character that cannot appear inside, and it is closed out and re-inserted:

    it's        ->  'it'\''s'
                     ^^^^  ^^^^^   close, escaped literal quote, reopen

Double quotes would be wrong here: `"$HOME"`, `"$(id)"` and `` "`id`" ``
still expand inside them.

Pure Lua; no KOReader dependencies; fully busted-testable.

@module fastnote.lib.shell_quote
--]]--

local shell_quote = {}

--- Quote a string for safe use as a single POSIX sh word.
--
-- The returned value includes its own surrounding quotes, so concatenate it
-- directly:
--
--     os.execute("mkdir -p " .. shell_quote.quote(dir))
--
-- Raises on a non-string argument: a nil path reaching a shell command is a
-- programming error, and silently quoting `nil` into `''` would turn it into
-- a command that runs against the wrong thing rather than failing loudly.
--
-- @string str  arbitrary text (a path, in practice); may be empty
-- @return string  the quoted word, quotes included
function shell_quote.quote(str)
    if type(str) ~= "string" then
        error("shell_quote.quote: expected string, got " .. type(str), 2)
    end
    -- No '%' in the replacement, so no gsub replacement-escaping to worry
    -- about; the pattern "'" contains no magic characters either.
    local escaped = str:gsub("'", "'\\''")
    return "'" .. escaped .. "'"
end

return shell_quote
