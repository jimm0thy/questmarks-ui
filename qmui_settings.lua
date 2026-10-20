-- Self-contained settings store (replaces Ashita's `settings` library, whose API differs
-- between Ashita v4 builds -- HorizonXI's copy failed inside load_settings).
-- Saved as a plain Lua table: <Ashita>/config/addons/questmarks-ui/qmui_settings_data.lua
-- (or next to the addon if that folder can't be used; an older copy there is migrated on first load).
local M = {}
local current, path

local function addon_dir()
    local p = (addon and addon.path) or './'
    if not p:match('[\\/]$') then p = p .. '/' end
    return p
end

local function copy(t)
    if type(t) ~= 'table' then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = copy(v) end
    return r
end

-- saved values win; keys missing from the file keep their defaults
local function merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == 'table' and type(dst[k]) == 'table' then merge(dst[k], v)
        else dst[k] = v end
    end
end

local function ser(v, indent, out)
    local t = type(v)
    if t == 'number' then
        out[#out + 1] = (v ~= v or v == math.huge or v == -math.huge) and '0' or tostring(v)
    elseif t == 'boolean' then out[#out + 1] = tostring(v)
    elseif t == 'string' then out[#out + 1] = ('%q'):format(v)
    elseif t == 'table' then
        out[#out + 1] = '{\n'
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local val = v[k]
            if type(val) ~= 'function' and type(val) ~= 'userdata' and type(val) ~= 'thread' then
                local key = type(k) == 'string' and ('[%q]'):format(k) or ('[' .. tostring(k) .. ']')
                out[#out + 1] = indent .. '  ' .. key .. ' = '
                ser(val, indent .. '  ', out)
                out[#out + 1] = ',\n'
            end
        end
        out[#out + 1] = indent .. '}'
    else out[#out + 1] = 'nil' end
end

function M.load(defaults)
    path = require('qm_cfgdir').path('questmarks-ui', 'qmui_settings_data.lua', addon_dir())
    current = copy(defaults)
    local ok, saved = pcall(function()
        local f = io.open(path, 'rb')
        if not f then return nil end
        local src = f:read('*a'); f:close()
        local fn = load(src, '=qm_settings', 't', {})
        return fn and fn() or nil
    end)
    if ok and type(saved) == 'table' then merge(current, saved) end
    current.save = function() return M.save() end   -- keeps `settings:save()` working (skipped when serialised)
    return current
end

function M.save()
    if not current or not path then return false end
    local out = {'return '}
    ser(current, '', out)
    out[#out + 1] = '\n'
    local f = io.open(path, 'wb')
    if not f then return false end
    f:write(table.concat(out)); f:close()
    return true
end

function M.register() end   -- no per-character swap: one file per install

return M
