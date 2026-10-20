--[[
platform.lua -- the rest of the windower.* surface this addon reaches for, on Ashita v4.

compat.lua supplies the game-state calls (get_player, get_info, events). This file adds
the filesystem, viewport and inventory hooks, plus the resource-name lookups that
resnames.lua / model.lua used to get from Windower's res/*.lua files.

Anything here that could not be verified offline is marked ASSUMPTION.
]]

local compat = require('compat')
local windower = compat.windower

local P = {}

-- ---------------------------------------------------------------------------
-- Paths
-- ---------------------------------------------------------------------------

-- Ashita addon.path ends in a separator; make sure of it.
do
    local p = windower.addon_path or './'
    if not p:match('[\\/]$') then p = p .. '/' end
    windower.addon_path = p
end

--[[ The default location of questmarks: the sibling folder `questmarks` next to this
     addon, derived from this addon's own path so a non-standard install root works. ]]
function P.default_questmarks_path()
    local p = windower.addon_path:gsub('[\\/]+$', '')
    local parent = p:match('^(.*)[\\/][^\\/]+$')
    if parent and parent ~= '' then return parent .. '/questmarks/' end
    return '../questmarks/'
end

-- ---------------------------------------------------------------------------
-- Filesystem (used only by the optional notes/description readers)
-- ---------------------------------------------------------------------------

windower.no_shell = true     -- notes.lua must never fall back to io.popen('dir ...') in game

function windower.dir_exists(path)
    -- ASSUMPTION: ashita.fs.exists answers for directories as well as files.
    if ashita and ashita.fs and ashita.fs.exists then
        local ok, r = pcall(ashita.fs.exists, path)
        if ok then return r and true or false end
    end
    return false
end

function windower.get_dir(path)
    -- ASSUMPTION: ashita.fs.get_dir(path, pattern, recurse) -> array of names or paths.
    if ashita and ashita.fs and ashita.fs.get_dir then
        local ok, l = pcall(ashita.fs.get_dir, path, '.*', false)
        if ok and type(l) == 'table' then
            local out = {}
            for _, v in ipairs(l) do
                out[#out + 1] = tostring(v):match('([^\\/]+)$') or tostring(v)
            end
            return out
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Viewport: Windower's "ui" resolution is simply the client size here.
-- ---------------------------------------------------------------------------

function P.viewport()
    local ok_d, d3d8 = pcall(require, 'd3d8')
    if ok_d and d3d8 then
        local ok, res, vp = pcall(function() return d3d8.get_device():GetViewport() end)
        if ok and res == 0 and vp then return vp.Width, vp.Height end
    end
    return nil
end

function windower.get_windower_settings()
    local w, h = P.viewport()
    if not w then return nil end
    return {ui_x_res = w, ui_y_res = h, x_res = w, y_res = h}
end

-- ---------------------------------------------------------------------------
-- Inventory hooks for questmarks' core/inventory.lua (it reaches for these globals)
-- ---------------------------------------------------------------------------

windower.ffxi.get_items       = function(bag) return compat.get_items(bag) end
windower.ffxi.get_key_items   = function() return compat.get_key_items() end
windower.ffxi.get_bag_info    = function(bag) return compat.get_bag_info(bag) end

-- ---------------------------------------------------------------------------
-- Item / key-item names (replaces reading Windower's res/items.lua and key_items.lua)
-- ---------------------------------------------------------------------------

local item_cache, ki_cache = {}, {}

function P.item_name(id)
    if item_cache[id] ~= nil then return item_cache[id] or nil end
    local name
    pcall(function()
        -- ASSUMPTION: Item.Name is an array of localized names; [1] is English on Ashita v4.
        local it = AshitaCore:GetResourceManager():GetItemById(id)
        if it and it.Name then name = it.Name[1] or it.Name[0] end
        if type(name) ~= 'string' or name == '' then name = nil end
    end)
    item_cache[id] = name or false
    return name
end

function P.key_item_name(id)
    if ki_cache[id] ~= nil then return ki_cache[id] or nil end
    local name
    pcall(function()
        -- ASSUMPTION: the string table is called 'keyitems.names'.
        local s = AshitaCore:GetResourceManager():GetString('keyitems.names', id)
        if type(s) == 'string' and s ~= '' then name = s end
    end)
    ki_cache[id] = name or false
    return name
end

return P
