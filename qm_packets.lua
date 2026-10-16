--[[
qm_packets.lua -- decodes the four incoming packets questmarks reads, into tables
shaped like the ones Windower's `packets.parse` produced, so core/state.lua,
core/keyitems.lua and core/kills.lua run unchanged.

Ashita hands addons the raw packet; offsets here are 0-based packet offsets and the
header (id/size/sequence) occupies bytes 0-3, exactly as in Windower's fields.lua.
Written with plain byte reads so it runs on LuaJIT (no string.unpack there).

Layouts, with where each came from:
  0x056  Windower fields.lua (commit f259197 "Add quest/mission packet mapping" plus
         the later 0xFFFE TVR sub-type, signed int32 at 0x04 per the Chronicle addon).
  0x055  core/keyitems.lua's own header comment (two 64-byte bitfields, Type at 0x84).
  0x02D  from memory of fields.lua; NOT re-checked this session.
  0x028  bit-packed action layout, from memory of Windower's actions library; NOT
         re-checked this session. Used only for the display-only kill tally.
]]

local P = {}

local function u8(d, o) return d:byte(o + 1) or 0 end
local function u16(d, o) return u8(d, o) + u8(d, o + 1) * 256 end
local function u32(d, o) return u16(d, o) + u16(d, o + 2) * 65536 end
local function i32(d, o)
    local v = u32(d, o)
    if v >= 2147483648 then v = v - 4294967296 end
    return v
end
local function blob(d, o, n) return d:sub(o + 1, o + n) end

function P.id_of(d) return u16(d, 0) % 512 end

-- ---------------------------------------------------------------------------
-- 0x056 Quest/Mission Log
-- ---------------------------------------------------------------------------

local function parse_056(d)
    local t = i32(d, 0x24)
    local p = {Type = t}
    local lo = t % 65536       -- sub-type selector (Windower masks to 16 bits too)

    if lo == 0x0080 then
        p['Current TOAU Quests']      = blob(d, 0x04, 16)
        p['Current Assault Mission']  = i32(d, 0x14)
        p['Current TOAU Mission']     = i32(d, 0x18)
        p['Current WOTG Mission']     = i32(d, 0x1C)
        p['Current Campaign Mission'] = i32(d, 0x20)
    elseif lo == 0x00C0 then
        p['Completed TOAU Quests'] = blob(d, 0x04, 16)
        p['Completed Assaults']    = blob(d, 0x14, 16)
    elseif lo == 0x00D0 then
        p["Completed San d'Oria Missions"] = blob(d, 0x04, 8)
        p['Completed Bastok Missions']     = blob(d, 0x0C, 8)
        p['Completed Windurst Missions']   = blob(d, 0x14, 8)
        p['Completed Zilart Missions']     = blob(d, 0x1C, 8)
    elseif lo == 0x00D8 then
        p['Completed TOAU Missions'] = blob(d, 0x04, 8)
        p['Completed WOTG Missions'] = blob(d, 0x0C, 8)
    elseif lo == 0xFFFE then
        p['Current TVR Mission'] = i32(d, 0x04)
    elseif lo == 0xFFFF then
        p['Nation']                = i32(d, 0x04)
        p['Current Nation Mission'] = i32(d, 0x08)
        p['Current ROZ Mission']   = i32(d, 0x0C)
        p['Current COP Mission']   = i32(d, 0x10)
        local b18, b19 = u8(d, 0x18), u8(d, 0x19)
        p['Current ACP Mission']   = b18 % 16
        p['Current MKD Mission']   = math.floor(b18 / 16)
        p['Current ASA Mission']   = b19 % 16
        p['Current SOA Mission']   = i32(d, 0x1C)
        p['Current ROV Mission']   = i32(d, 0x20)
    else
        p['Quest Flags'] = blob(d, 0x04, 32)
    end
    -- Windower keyed BITFIELD_LOGS / FIELD_LOGS by the masked sub-type value.
    p.Type = lo
    return p
end

-- ---------------------------------------------------------------------------
-- 0x055 Key Items
-- ---------------------------------------------------------------------------

local function parse_055(d)
    return {
        ['Key item available'] = blob(d, 0x04, 0x40),
        ['Key item examined']  = blob(d, 0x44, 0x40),
        Type = u32(d, 0x84),
    }
end

-- ---------------------------------------------------------------------------
-- 0x02D Kill message / basic message
-- ---------------------------------------------------------------------------

local function parse_02D(d)
    return {
        Player = u32(d, 0x04), Target = u32(d, 0x08),
        ['Param 1'] = u32(d, 0x0C), ['Param 2'] = u32(d, 0x10),
        Message = u16(d, 0x18) % 32768,
    }
end

local PARSERS = {[0x056] = parse_056, [0x055] = parse_055, [0x02D] = parse_02D}

function P.parse(_, d)
    local f = PARSERS[P.id_of(d)]
    return f and f(d) or nil
end

-- ---------------------------------------------------------------------------
-- 0x028 Action  (bit-packed, little-endian bit order)
-- ---------------------------------------------------------------------------

local function bits(d, pos, n)
    -- `pos` is a bit offset from the start of the packet.
    local v, got = 0, 0
    while got < n do
        local byte = u8(d, math.floor(pos / 8))
        local sh = pos % 8
        local take = math.min(8 - sh, n - got)
        local chunk = math.floor(byte / 2 ^ sh) % 2 ^ take
        v = v + chunk * 2 ^ got
        got, pos = got + take, pos + take
    end
    return v, pos
end

function P.parse_action(d)
    if #d < 12 then return nil end
    local a = {targets = {}}
    a.actor_id = bits(d, 40, 32)
    local ntargets = bits(d, 72, 10)
    if ntargets > 64 then return nil end      -- implausible: layout mismatch
    local pos = 150
    for i = 1, ntargets do
        local t = {actions = {}}
        t.id, pos = bits(d, pos, 32)
        local nact
        nact, pos = bits(d, pos, 4)
        for n = 1, nact do
            local act = {}
            local _
            _, pos = bits(d, pos, 5)              -- reaction
            _, pos = bits(d, pos, 12)             -- animation
            _, pos = bits(d, pos, 7)              -- special effect
            _, pos = bits(d, pos, 3)              -- knockback
            _, pos = bits(d, pos, 17)             -- param
            act.message, pos = bits(d, pos, 10)
            _, pos = bits(d, pos, 31)             -- unknown
            local has_add; has_add, pos = bits(d, pos, 1)
            if has_add == 1 then pos = pos + 41 end   -- animation 10, effect 4, param 17, msg 10
            local has_spike; has_spike, pos = bits(d, pos, 1)
            if has_spike == 1 then pos = pos + 38 end -- animation 10, effect 4, param 14, msg 10
            t.actions[n] = act
            if pos > #d * 8 then return a end     -- ran off the end: keep what parsed
        end
        a.targets[i] = t
    end
    return a
end

return P
