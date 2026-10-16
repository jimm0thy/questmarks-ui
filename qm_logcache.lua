--[[
qm_logcache.lua -- remembers the last 0x056 (quest/mission log) packets per character.

The server only sends the quest log at zone-in, so an addon loaded mid-session never
sees it. questmarks saves what it receives here; questmarks-ui (a separate addon with a
separate Lua state) reads the file back when it starts, so it does not have to wait for
you to zone. Raw packets are stored hex-encoded.

The same file is shipped with both addons; each reads/writes the one in the questmarks
folder (questmarks-ui is given that folder by its `questmarks_path`).
]]

local M = {}

local store = {}          -- name -> {saved = os.time(), packets = {[type] = hex}}
local dirty = false
local last_write = 0
local path = nil

local function hex(s)
    return (s:gsub('.', function(c) return ('%02x'):format(c:byte()) end))
end

local function unhex(h)
    return (h:gsub('%x%x', function(x) return string.char(tonumber(x, 16)) end))
end

-- Sub-type of a 0x056 packet: the int32 at 0x24, low 16 bits (same rule as qm_packets).
local function subtype(data)
    if type(data) ~= 'string' or #data < 0x28 then return nil end
    return data:byte(0x24 + 1) + data:byte(0x24 + 2) * 256
end

function M.set_path(p) path = p end

local function ser()
    local out = {'return {\n'}
    local names = {}
    for n in pairs(store) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        local e = store[n]
        out[#out + 1] = ('  [%q] = {saved = %d, packets = {\n'):format(n, e.saved or 0)
        local ts = {}
        for t in pairs(e.packets) do ts[#ts + 1] = t end
        table.sort(ts)
        for _, t in ipairs(ts) do out[#out + 1] = ('    [%d] = %q,\n'):format(t, e.packets[t]) end
        out[#out + 1] = '  }},\n'
    end
    out[#out + 1] = '}\n'
    return table.concat(out)
end

local function read_file(p)
    local f = io.open(p, 'rb')
    if not f then return nil end
    local src = f:read('*a'); f:close()
    local fn = load and load(src, '=qm_logcache', 't', {}) or loadstring(src)
    if not fn then return nil end
    local ok, t = pcall(fn)
    return ok and type(t) == 'table' and t or nil
end

-- Called for every incoming 0x056. Cheap: one table write, no I/O.
function M.record(name, data)
    if type(name) ~= 'string' or name == '' then return end
    local t = subtype(data)
    if not t then return end
    if not store._loaded then
        -- merge with what is already on disk so other characters are kept
        store._loaded = true
        local disk = path and read_file(path)
        if disk then for n, e in pairs(disk) do if store[n] == nil then store[n] = e end end end
    end
    local e = store[name]
    if not e then e = {packets = {}}; store[name] = e end
    local h = hex(data)
    if e.packets[t] ~= h then e.packets[t] = h; e.saved = os.time(); dirty = true end
end

-- Called from the frame loop; writes at most every 3 s, and only when something changed.
function M.flush(now)
    if not dirty or not path then return end
    now = now or os.clock()
    if now - last_write < 3 then return end
    last_write = now
    dirty = false
    store._loaded = nil
    local copy = {}
    for k, v in pairs(store) do if type(v) == 'table' then copy[k] = v end end
    local saved_store = store
    store = copy
    local text = ser()
    store = saved_store
    store._loaded = true
    local f = io.open(path, 'wb')
    if f then f:write(text); f:close() end
end

-- -> array of raw packet strings, saved-at (os.time) -- or nil when nothing is stored.
function M.load(p, name)
    local disk = read_file(p)
    local e = disk and disk[name]
    if not e or type(e.packets) ~= 'table' then return nil end
    local list = {}
    for t, h in pairs(e.packets) do list[#list + 1] = {t = t, data = unhex(h)} end
    table.sort(list, function(a, b) return a.t < b.t end)
    local out = {}
    for _, x in ipairs(list) do out[#out + 1] = x.data end
    if #out == 0 then return nil end
    return out, e.saved
end

return M
