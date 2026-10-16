-- Headless smoke test: mock Ashita + ImGui, feed a 0x056 packet, open the panel, click around.
-- Run from the addon folder:  texlua tests/smoke_headless.lua   (or any Lua 5.1-5.4 / LuaJIT)
local ADDON = (arg and arg[0] and arg[0]:match('^(.*)tests[/\\]')) or './'
if ADDON == '' then ADDON = './' end
package.path = ADDON .. '?.lua;' .. package.path
local rawprint = print
local out = {}
_G.print = function(...) local t = {} for i = 1, select('#', ...) do t[#t+1] = tostring((select(i, ...))) end out[#out+1] = table.concat(t, ' ') end
_G.addon = {path = ADDON}
local fake_t = 0
os.clock = function() return fake_t end

package.loaded['ffi'] = nil
package.preload['bit'] = function() return {band=function(a,b) return a&b end, bor=function(a,b) return a|b end,
  lshift=function(a,n) return a<<n end, rshift=function(a,n) return a>>n end, bxor=function(a,b) return a~b end} end
package.preload['ffi'] = function()
  local ffi = {C = {}}
  function ffi.cdef() end
  function ffi.new() return {} end
  function ffi.cast(_, v) return type(v) == 'number' and v or 4242 end
  function ffi.C.D3DXCreateTextureFromFileA(dev, path, outp) outp[0] = 1; return 0 end
  return ffi
end
package.preload['d3d8'] = function() return {
  get_device = function() return {GetViewport = function() return 0, {Width = 1920, Height = 1080} end} end,
  gc_safe_release = function(x) return x end} end

local C = {rect = 0, image = 0, text = 0, strings = {}}
local dl = {
  AddRectFilled = function() C.rect = C.rect + 1 end,
  AddImage = function() C.image = C.image + 1 end,
  AddText = function() C.text = C.text + 1 end,
}
dl.__index = dl
local dlobj = setmetatable({}, dl)
local frame_texts = {}
package.preload['imgui'] = function() return {
  Begin = function() return true end, End = function() end,
  GetWindowDrawList = function() return dlobj end,
  SetNextWindowPos = function() end, SetNextWindowSize = function() end,
  GetFontSize = function() return 13 end,
  CalcTextSize = function(s) return #s * 7, 13 end,
  SetWindowFontScale = function() end, SetCursorScreenPos = function() end,
  PushStyleColor = function() end, PopStyleColor = function() end,
  TextUnformatted = function(s) C.text = C.text + 1; frame_texts[#frame_texts+1] = s end,
} end

local H = {}
ashita = {events = {register = function(ev, name, fn) H[ev] = fn return true end}, fs = {exists = function() return false end}}
local ent = {[1] = {name = 'Tester', p = {10, 0, 20}, sid = 1000}}
local mm = {
  GetParty = function() return {GetMemberTargetIndex = function() return 1 end, GetMemberName = function() return 'Tester' end,
    GetMemberZone = function() return 230 end, GetMemberIsActive = function(_, i) return i == 0 and 1 or 0 end,
    GetMemberServerId = function() return 1000 end} end,
  GetPlayer = function() return {GetMainJob = function() return 1 end, GetMainJobLevel = function() return 75 end, HasKeyItem = function() return false end} end,
  GetEntity = function() return {GetName = function(_, i) return ent[i] and ent[i].name or '' end,
    GetLocalPositionX = function() return 0 end, GetLocalPositionY = function() return 0 end, GetLocalPositionZ = function() return 0 end,
    GetRenderFlags0 = function() return 0 end, GetServerId = function() return 0 end} end,
  GetTarget = function() return {GetIsSubTargetActive = function() return 0 end, GetTargetIndex = function() return 0 end} end,
  GetInventory = function() return {GetContainerCountMax = function(_, c) return c == 0 and 80 or 0 end,
    GetContainerItem = function() return {Id = 0, Count = 0, Flags = 0} end} end,
}
AshitaCore = {GetMemoryManager = function() return mm end,
  GetResourceManager = function() return {GetString = function(_, _, id) return 'Zone' .. id end,
    GetItemById = function(_, id) return {Name = {[0] = 'JP', [1] = 'Item' .. id}} end} end,
  GetChatManager = function() return {QueueCommand = function() end} end}

local ok, e = pcall(dofile, ADDON .. 'questmarks-ui.lua')
assert(ok, 'LOAD FAILED: ' .. tostring(e))
rawprint('-- loaded --')

local function pkt(len) local t = {} for i = 1, len do t[i] = '\0' end return t end
local function put32(t, o, v) for i = 0, 3 do t[o+i+1] = string.char((v >> (8*i)) & 255) end end
local function mk(id, len, f) local t = pkt(len) t[1] = string.char(id % 256); t[2] = string.char(id // 256); f(t); return table.concat(t) end
local function frame() fake_t = fake_t + 0.6; frame_texts = {}; C.rect, C.image, C.text = 0, 0, 0; H.d3d_present() end

frame(); frame()
-- LATE LOAD: no live packets. Build a cache the way questmarks would, then expect the UI to replay it.
do
  local lc = dofile(ADDON .. 'qm_logcache.lua')
  lc.set_path(ADDON .. '../questmarks/qm_log_cache.lua')
  local function rec(ty, f) lc.record('Tester', mk(0x56, 0x28, function(t) put32(t, 0x24, ty); f(t) end)) end
  rec(0xFFFF, function(t) put32(t, 0x04, 1) end)
  for _, ty in ipairs{0x50, 0x58, 0x60, 0x68, 0x70, 0x78, 0x88} do rec(ty, function(t) t[5] = '\255'; t[6] = '\15'; t[7] = '\3' end) end
  lc.flush(100)
end
for i = 1, 5 do frame() end
rawprint('state ready after replay:', require('model').state_ready())
assert(require('model').state_ready(), 'replay did not load the quest log')
-- (live packets below are skipped in this variant)
if false then
H.packet_in{id = 0x56, data = mk(0x56, 0x28, function(t) put32(t, 0x24, 0xFFFF) put32(t, 0x04, 1) end)}
for _, ty in ipairs{0x50, 0x58, 0x60, 0x68, 0x70, 0x78, 0x88} do
  H.packet_in{id = 0x56, data = mk(0x56, 0x28, function(t) put32(t, 0x24, ty); t[5] = '\255'; t[6] = '\15'; t[7] = '\3' end)}
end
end
for i = 1, 4 do frame() end
rawprint('after packets: launcher draws image=', C.image, 'rect=', C.rect, 'text=', C.text)

H.command{command = '/qmui show', blocked = false}
for i = 1, 4 do frame() end
rawprint('panel open: rect=', C.rect, 'image=', C.image, 'text=', C.text)
assert(C.rect > 3, 'panel drew no rectangles')
assert(C.text > 0, 'panel drew no text')

-- clicks: press+release on a few spots; wheel
local blocked_any = false
for _, p in ipairs{{70, 120}, {100, 200}, {100, 260}, {300, 300}} do
  local e1 = {message = 513, x = p[1], y = p[2], delta = 0, blocked = false}; H.mouse(e1)
  local e2 = {message = 514, x = p[1], y = p[2], delta = 0, blocked = false}; H.mouse(e2)
  blocked_any = blocked_any or e1.blocked
  frame()
end
H.mouse{message = 522, x = 100, y = 200, delta = -120, blocked = false}
H.mouse{message = 512, x = 120, y = 220, delta = 0, blocked = false}
frame()
rawprint('clicks over panel blocked:', blocked_any)

for _, c in ipairs{'diag', 'list', 'bg parchment', 'opacity 0.8', 'scale 1.2', 'handin', 'here', 'search a', 'search', 'icon', 'icon', 'help', 'hide'} do
  H.command{command = '/qmui ' .. c, blocked = false}
  frame()
end
H.unload()
local bad = 0
for _, l in ipairs(out) do
  if l:find('failed') or l:find('attempt to') or l:find('could not') then bad = bad + 1; rawprint('!!', l) end
end
rawprint('output lines', #out, 'problems', bad)
local f = io.open(ADDON .. 'tests/smoke_out.txt', 'w'); f:write(table.concat(out, '\n')); f:close()
