--[[
compat.lua -- a small Windower-shaped facade over Ashita v4.

questmarks was written against Windower 4's `windower.*` API. Rather than
rewrite ~2,000 lines of logic, this module exposes the handful of `windower.*`
calls the logic actually uses, implemented on Ashita's memory manager. Every
Ashita-specific assumption in the port that could not be verified offline is
in THIS file, so if something misbehaves in game, start here.

Entity coordinates: Windower's mob.x / mob.y / mob.z has z = vertical. FFXI keeps
positions in memory as (east, vertical, north), and Ashita's GetLocalPositionX/Y/Z
read those three floats in order, so the default mapping is
    mob.x = Ashita X,  mob.y = Ashita Z,  mob.z = Ashita Y
which is exactly the (x, z, y) shuffle the original project.lua applied to Windower's
camera. If markers land in the wrong place, `/qm axes` lets you permute it live.
]]

local compat = {}

local ffi_ok, ffi = pcall(require, 'ffi')
local bit_ok, bit = pcall(require, 'bit')

-- ---------------------------------------------------------------------------
-- Plain helpers
-- ---------------------------------------------------------------------------

local windower = {ffxi = {}}
compat.windower = windower

function windower.from_shift_jis(s) return s end

windower.addon_path = (addon and addon.path) or './'
windower.windower_path = windower.addon_path   -- res/ lookups are replaced below

-- Chat output. Colour is ignored: Ashita's print() goes to the chat log as-is.
function windower.add_to_chat(_, text)
    if type(print) == 'function' then print(tostring(text)) end
end

-- Append-only log next to the addon. Best effort.
function compat.flog(file, text)
    pcall(function()
        local f = io.open(windower.addon_path .. file, 'a')
        if f then f:write(os.date('%Y-%m-%d %H:%M:%S '), tostring(text), '\n'); f:close() end
    end)
end

function windower.send_command(cmd)
    -- 'lua reload questmarks' -> '/addon reload questmarks'
    local name = cmd:match('^lua%s+reload%s+(%S+)')
    if name and AshitaCore then
        AshitaCore:GetChatManager():QueueCommand(-1, '/addon reload ' .. name)
    end
end

-- ---------------------------------------------------------------------------
-- Scheduler (coroutine.schedule replacement), pumped from the frame tick
-- ---------------------------------------------------------------------------

local tasks = {}
function windower.schedule(fn, delay)
    tasks[#tasks + 1] = {at = os.clock() + (delay or 0), fn = fn}
end

local function run_tasks()
    if #tasks == 0 then return end
    local now, keep = os.clock(), {}
    for _, t in ipairs(tasks) do
        if t.at <= now then pcall(t.fn) else keep[#keep + 1] = t end
    end
    tasks = keep
end

-- ---------------------------------------------------------------------------
-- Memory-manager accessors (all pcall'd by callers)
-- ---------------------------------------------------------------------------

local function mm() return AshitaCore:GetMemoryManager() end

local JOB = {'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG',
             'SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN'}

local function me_index()
    local i = mm():GetParty():GetMemberTargetIndex(0)
    return (type(i) == 'number' and i > 0) and i or nil
end

local function player_name()
    local n = mm():GetParty():GetMemberName(0)
    return (type(n) == 'string' and n ~= '') and n or nil
end

local function zone_id()
    local z = mm():GetParty():GetMemberZone(0)
    return (type(z) == 'number' and z > 0) and z or nil
end

-- ---------------------------------------------------------------------------
-- windower.ffxi.*
-- ---------------------------------------------------------------------------

function windower.ffxi.get_info()
    local name = player_name()
    local z = zone_id()
    return {
        zone = z,
        logged_in = (name ~= nil and z ~= nil),
        mog_house = false,    -- not exposed; Mog House-only entries stay unmatched
        -- menu_open / chat_open / day / weather are not read. menu_open being nil is
        -- handled by questmarks: an unknown flag never suppresses markers.
    }
end

function windower.ffxi.get_player()
    local name = player_name()
    if not name then return nil end
    local pl = mm():GetPlayer()
    local jid = pl:GetMainJob()
    return {
        name = name,
        main_job = JOB[jid],
        main_job_level = pl:GetMainJobLevel(),
        skills = nil,         -- core/skills reads packet 0x062 directly instead
    }
end

-- Raw (X, Y, Z) -> Windower-style (x, y, z). See header.
compat.axes = {1, 2, 3}   -- verified in game on HorizonXI: mob.x,y,z = raw X,Y,Z (the old {1,3,2} guess was wrong)

local function entity(i)
    local e = mm():GetEntity()
    local name = e:GetName(i)
    if type(name) ~= 'string' or name == '' then return nil end
    local raw = {e:GetLocalPositionX(i), e:GetLocalPositionY(i), e:GetLocalPositionZ(i)}
    local rf = e:GetRenderFlags0(i) or 0
    local ax = compat.axes
    return {
        index = i,
        id = e:GetServerId(i),
        name = name,
        x = raw[ax[1]], y = raw[ax[2]], z = raw[ax[3]],
        race = e:GetRace(i),
        status = e:GetStatus(i),
        hpp = e:GetHPPercent(i),
        -- ASSUMPTION (unverified): render flag 0x200 means "spawned and rendered", which
        -- is what Windower's valid_target tracked. If no marker ever shows, try
        -- `/qm visible off`.
        valid_target = (bit and bit.band(rf, 0x200) ~= 0) or false,
        model_size = 0,
    }
end

function windower.ffxi.get_mob_by_index(i)
    if type(i) ~= 'number' then return nil end
    return entity(i)
end

function windower.ffxi.get_mob_list()
    local list, e = {}, mm():GetEntity()
    for i = 0, 0x8FF do
        local n = e:GetName(i)
        if type(n) == 'string' and n ~= '' then list[i] = n end
    end
    return list
end

function windower.ffxi.get_mob_by_target(which)
    if which == 'me' then
        local i = me_index()
        return i and entity(i) or nil
    elseif which == 't' or which == 'st' then
        local t = mm():GetTarget()
        local sub = t:GetIsSubTargetActive()
        local slot = (which == 'st' or sub == 1 or sub == true) and 1 or 0
        local i = t:GetTargetIndex(slot)
        return (type(i) == 'number' and i > 0) and entity(i) or nil
    end
    return nil
end

function windower.ffxi.get_mob_by_id(sid)
    local e = mm():GetEntity()
    for i = 0, 0x8FF do
        if e:GetServerId(i) == sid then return entity(i) end
    end
    return nil
end

function windower.ffxi.get_party()
    local out, p = {}, mm():GetParty()
    for i = 0, 17 do
        if p:GetMemberIsActive(i) == 1 then
            out[#out + 1] = {mob = {id = p:GetMemberServerId(i)}}
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Bags and key items (installed into core/inventory via set_api in questmarks.lua)
-- ---------------------------------------------------------------------------

-- Ashita container ids.
local CONTAINER = {
    inventory = 0, safe = 1, storage = 2, temporary = 3, locker = 4, satchel = 5,
    sack = 6, case = 7, wardrobe = 8, safe2 = 9, wardrobe2 = 10, wardrobe3 = 11,
    wardrobe4 = 12, wardrobe5 = 13, wardrobe6 = 14, wardrobe7 = 15, wardrobe8 = 16,
}

function compat.get_bag_info(bag)
    local c = CONTAINER[bag]
    if not c then return nil end
    local max = mm():GetInventory():GetContainerCountMax(c)
    if type(max) ~= 'number' then return nil end
    -- Wardrobes the character has not bought report 0 slots.
    return {max = max, enabled = max > 0}
end

function compat.get_items(bag)
    local c = CONTAINER[bag]
    if not c then return nil end
    local inv = mm():GetInventory()
    local max = inv:GetContainerCountMax(c)
    local out = {}
    for slot = 0, (max or 0) do
        local it = inv:GetContainerItem(c, slot)
        if it and it.Id and it.Id ~= 0 and it.Id ~= 65535 then
            -- ASSUMPTION (unverified): Flags == 5 is "equipped", as Windower's itemstat.
            out[#out + 1] = {id = it.Id, count = it.Count or 1, status = it.Flags, slot = slot}
        end
    end
    return out
end

-- Ground truth for core/keyitems.verify. HasKeyItem is read in bulk; ids past the
-- highest known key item are simply false.
function compat.get_key_items()
    local pl, out = mm():GetPlayer(), {}
    for id = 0, 3600 do
        if pl:HasKeyItem(id) then out[#out + 1] = id end
    end
    return out
end

-- Display-only name lookups (zones). Everything else resolves to the raw id.
function compat.res_name(file, id)
    if file ~= 'zones' or type(id) ~= 'number' then return nil end
    local ok, s = pcall(function()
        return AshitaCore:GetResourceManager():GetString('zones.names', id)
    end)
    return (ok and type(s) == 'string' and s ~= '') and s or nil
end

-- ---------------------------------------------------------------------------
-- Event registry. Ashita callbacks in questmarks.lua call compat.fire().
-- ---------------------------------------------------------------------------

local handlers = {}
function windower.register_event(name, fn)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], fn)
end

function compat.fire(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do
        local ok, e = pcall(fn, ...)
        if not ok then
            compat.flog('questmarks-ui.log', 'handler ' .. name .. ' failed: ' .. tostring(e))
            if type(print) == 'function' then print('questmarks-ui: handler ' .. name .. ' failed: ' .. tostring(e)) end
        end
    end
end

-- Like fire(), but reports whether any handler returned true (used for 'mouse': true = block).
function compat.fire_ret(name, ...)
    local blocked = false
    for _, fn in ipairs(handlers[name] or {}) do
        local ok, r = pcall(fn, ...)
        if not ok then
            compat.flog('questmarks-ui.log', 'handler ' .. name .. ' failed: ' .. tostring(r))
        elseif r then blocked = true end
    end
    return blocked
end

-- ---------------------------------------------------------------------------
-- Per-frame state polling: zone change, login/logout, job change
-- ---------------------------------------------------------------------------

local last = {zone = nil, name = nil, job = nil, lvl = nil}

function compat.tick()
    run_tasks()
    local ok, name = pcall(player_name)
    name = ok and name or nil

    if name ~= last.name then
        if last.name and not name then compat.fire('logout') end
        last.name = name
        if name then
            last.zone, last.job, last.lvl = nil, nil, nil
            compat.fire('login')
        end
    end
    if not name then return end

    local zok, z = pcall(zone_id)
    z = zok and z or nil
    if z and z ~= last.zone then
        last.zone = z
        compat.fire('zone change', z)
    end

    local jok, pl = pcall(function()
        local p = mm():GetPlayer()
        return {p:GetMainJob(), p:GetMainJobLevel()}
    end)
    if jok and pl and (pl[1] ~= last.job or pl[2] ~= last.lvl) then
        local had = last.job ~= nil
        last.job, last.lvl = pl[1], pl[2]
        if had then compat.fire('job change') end
    end
end

return compat
