-- WoW Lua polyfills: the global helpers the game client provides on top of Lua 5.1.
-- Standalone: depends on no other hwc module and works on any env table.
local polyfills = {}

-- WoW strsplit(delims, str [, pieces]): delims is a SET of single characters (not a
-- pattern); empty pieces are kept; with `pieces`, the remainder stays in the last piece.
local function strsplit(delims, str, pieces)
    local set = {}
    for i = 1, #delims do
        set[delims:byte(i)] = true
    end
    local out, n, start = {}, 0, 1
    for i = 1, #str do
        if pieces and n >= pieces - 1 then
            break
        end
        if set[str:byte(i)] then
            n = n + 1
            out[n] = str:sub(start, i - 1)
            start = i + 1
        end
    end
    out[n + 1] = str:sub(start)
    return unpack(out, 1, n + 1)
end

-- WoW strtrim(str [, chars]): default chars are space, tab, CR, LF.
local function strtrim(str, chars)
    local set = {}
    chars = chars or " \t\r\n"
    for i = 1, #chars do
        set[chars:byte(i)] = true
    end
    local first, last = 1, #str
    while first <= last and set[str:byte(first)] do
        first = first + 1
    end
    while last >= first and set[str:byte(last)] do
        last = last - 1
    end
    return str:sub(first, last)
end

local function strjoin(sep, ...)
    return table.concat({ ... }, sep, 1, select("#", ...))
end

local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

function polyfills.install(env)
    -- Process-wide on purpose: WoW exposes these as string methods; idempotent.
    string.split = strsplit
    string.trim = strtrim

    env.strsplit, env.strtrim, env.strjoin, env.wipe = strsplit, strtrim, strjoin, wipe
    env.tinsert, env.tremove, env.sort = table.insert, table.remove, table.sort
    env.floor, env.ceil, env.abs, env.max, env.min, env.sqrt =
        math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt
    env.format, env.strupper, env.strlower, env.strsub, env.strlen =
        string.format, string.upper, string.lower, string.sub, string.len
    env.strfind, env.strmatch, env.gsub = string.find, string.match, string.gsub
    env.date, env.time = os.date, os.time
    env.debugstack = function()
        return debug.traceback()
    end
    env.debuglocals = function()
        return ""
    end
end

return polyfills
