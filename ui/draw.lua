--[[
ui/draw.lua -- the drawing floor: pooled, change-detected rectangles, images and text.

ASHITA PORT. The Windower original created named client-side prims and text objects
and let the game draw them. Ashita has no such objects, so every call that used to
reach the client now just updates a record in a table here, and `draw.flush()` (called
once per frame from d3d_present) paints the visible ones with ImGui:

  * rectangles and images go to the draw list of a transparent, click-through,
    full-screen overlay window, in CREATION order (that is the z-order the panel was
    designed against; texts always sit on top of every rectangle and image);
  * text is imgui.Text at a scaled font size, with an optional 1 px outline and a
    faux-bold second pass.

The API the panel and launcher use is unchanged: Rect / Image / Text objects with the
same change-detected setters, draw.destroy_all(), draw.count().

Nothing named lives in the client any more, so an orphan can no longer outlive the
addon: unloading simply stops flushing.

Unverified against a live Ashita build (see README): the ImGui calls in flush(), the
texture loader, and the font-size handling. `/qmui diag` reports what was found.
]]

local draw = {}

local ok_imgui, imgui = pcall(require, 'imgui')
local ok_ffi, ffi = pcall(require, 'ffi')
local ok_d3d, d3d8 = pcall(require, 'd3d8')

draw.last_error = nil
draw.errors = 0
draw.mode = 'none'                -- which drawing path flush() last used
draw.counts = {rect = 0, image = 0, text = 0}

local prims, texts = {}, {}       -- creation-ordered; dead entries are skipped and compacted
local live = 0
local seq = 0

local function note_err(what, e)
    draw.errors = draw.errors + 1
    draw.last_error = what .. ': ' .. tostring(e)
end

-- ---------------------------------------------------------------------------
-- Colour helpers
-- ---------------------------------------------------------------------------

local function clamp255(v) v = tonumber(v) or 0; if v < 0 then return 0 elseif v > 255 then return 255 end return math.floor(v) end

-- ImGui packs ImU32 as 0xAABBGGRR.
local function abgr(a, r, g, b)
    return clamp255(a) * 16777216 + clamp255(b) * 65536 + clamp255(g) * 256 + clamp255(r)
end

-- ---------------------------------------------------------------------------
-- Textures (same approach as questmarks/render/backend.lua)
-- ---------------------------------------------------------------------------

local texcache = {}      -- path -> {id=, keep=} | false
local cdef_done = false

local function ensure_cdef()
    if cdef_done or not ok_ffi then return end
    cdef_done = true
    -- Ashita's d3d8 module already declares this with typed pointers; only declare it if missing.
    local have = pcall(function() return ffi.C.D3DXCreateTextureFromFileA end)
    if not have then
        pcall(ffi.cdef, [[
            typedef struct IDirect3DDevice8 IDirect3DDevice8;
            typedef struct IDirect3DTexture8 IDirect3DTexture8;
            int32_t __stdcall D3DXCreateTextureFromFileA(IDirect3DDevice8* pDevice, const char* pSrcFile, IDirect3DTexture8** ppTexture);
        ]])
    end
end

local function load_texture(path)
    local hit = texcache[path]
    if hit ~= nil then return hit end
    texcache[path] = false           -- never retry a failure every frame
    if not (ok_ffi and ok_d3d) then note_err('texture', 'ffi or d3d8 unavailable') return false end
    ensure_cdef()
    local ok, res = pcall(function()
        local dev = d3d8.get_device()
        local out = ffi.new('IDirect3DTexture8*[1]')
        local hr = ffi.C.D3DXCreateTextureFromFileA(dev, path, out)
        if hr ~= 0 or out[0] == nil then
            error(('D3DXCreateTextureFromFileA(%s) -> 0x%08X'):format(path, hr % 4294967296))
        end
        local tex = ffi.cast('IDirect3DTexture8*', out[0])
        if d3d8.gc_safe_release then tex = d3d8.gc_safe_release(tex) end
        return {keep = tex, id = tonumber(ffi.cast('uint32_t', tex))}
    end)
    if ok and res then texcache[path] = res return res end
    note_err('texture', res)
    return false
end

-- ---------------------------------------------------------------------------
-- Rectangles
-- ---------------------------------------------------------------------------

local Rect = {}
Rect.__index = Rect

local function new_prim(kind)
    seq = seq + 1
    local self = setmetatable({kind = kind, seq = seq, p = {}, vis = false,
        x = 0, y = 0, w = 0, h = 0, a = 255, r = 255, g = 255, b = 255}, Rect)
    prims[#prims + 1] = self
    live = live + 1
    return self
end

function draw.rect()
    local self = new_prim('rect')
    self.p.vis = false
    return self
end

function Rect:pos(x, y)
    x, y = math.floor(x), math.floor(y)
    if self.p.x == x and self.p.y == y then return end
    self.p.x, self.p.y = x, y
    self.x, self.y = x, y
end

function Rect:size(w, h)
    w, h = math.floor(w), math.floor(h)
    if w < 0 then w = 0 end
    if h < 0 then h = 0 end
    if self.p.w == w and self.p.h == h then return end
    self.p.w, self.p.h = w, h
    self.w, self.h = w, h
end

function Rect:color(a, r, g, b)
    if self.p.a == a and self.p.r == r and self.p.g == g and self.p.b == b then return end
    self.p.a, self.p.r, self.p.g, self.p.b = a, r, g, b
    self.a, self.r, self.g, self.b = a, r, g, b
end

function Rect:visible(v)
    v = v and true or false
    if self.p.vis == v then return end
    self.p.vis = v
    self.vis = v
end

function Rect:destroy()
    if self.dead then return end
    self.dead = true
    self.vis = false
    live = live - 1
end

-- ---------------------------------------------------------------------------
-- Images (rectangles WITH a texture)
-- ---------------------------------------------------------------------------

local Image = setmetatable({}, {__index = Rect})
Image.__index = Image

function draw.image()
    local self = new_prim('image')
    setmetatable(self, Image)
    return self
end

function Image:texture(path)
    path = tostring(path or '')
    if self.p.tex == path then return end
    self.p.tex = path
    self.tex = path
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

local Text = {}
Text.__index = Text

function draw.text(opts)
    opts = opts or {}
    seq = seq + 1
    local self = setmetatable({seq = seq, p = {}, vis = false, s = '', x = 0, y = 0,
        size = opts.size or 10, bold_ = opts.bold and true or false,
        a = 255, r = 255, g = 255, b = 255, sa = 0, sr = 0, sg = 0, sb = 0,
        stroke_w = opts.stroke or 1}, Text)
    texts[#texts + 1] = self
    live = live + 1
    return self
end

function Text:font(name, size)
    -- The face is whatever ImGui's default font is; only the size is ours to choose.
    self.p.font, self.p.size = name, size
    self.size = size or self.size
end

function Text:bold(v)
    v = v and true or false
    self.p.bold = v
    self.bold_ = v
end

function Text:italic(v) self.p.italic = v and true or false end   -- not available in ImGui

function Text:text(s)
    s = tostring(s or '')
    if self.p.text == s then return end
    self.p.text = s
    self.s = s
end

function Text:pos(x, y)
    x, y = math.floor(x), math.floor(y)
    if self.p.x == x and self.p.y == y then return end
    self.p.x, self.p.y = x, y
    self.x, self.y = x, y
end

function Text:stroke(a, r, g, b)
    if self.p.sa == a and self.p.sr == r and self.p.sg == g and self.p.sb == b then return end
    self.p.sa, self.p.sr, self.p.sg, self.p.sb = a, r, g, b
    self.sa, self.sr, self.sg, self.sb = a, r, g, b
end

function Text:color(a, r, g, b)
    if self.p.a == a and self.p.r == r and self.p.g == g and self.p.b == b then return end
    self.p.a, self.p.r, self.p.g, self.p.b = a, r, g, b
    self.a, self.r, self.g, self.b = a, r, g, b
end

function Text:visible(v)
    v = v and true or false
    if self.p.vis == v then return end
    self.p.vis = v
    self.vis = v
end

function Text:destroy()
    if self.dead then return end
    self.dead = true
    self.vis = false
    live = live - 1
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function draw.destroy_all()
    for _, o in ipairs(prims) do o.dead, o.vis = true, false end
    for _, o in ipairs(texts) do o.dead, o.vis = true, false end
    prims, texts, live = {}, {}, 0
end

function draw.count() return live end

local function compact(list)
    local n, dead = #list, 0
    for i = 1, n do if list[i].dead then dead = dead + 1 end end
    if dead < 64 or dead * 2 < n then return list end
    local out = {}
    for i = 1, n do if not list[i].dead then out[#out + 1] = list[i] end end
    return out
end

-- ---------------------------------------------------------------------------
-- Font metrics, measured from the live ImGui font
-- ---------------------------------------------------------------------------

draw.font_px = 13                 -- ImGui's font size in pixels
draw.advance_em = 7 / 13          -- average glyph advance as a fraction of the em

local function calc(s)
    local a, b = imgui.CalcTextSize(s)
    if type(a) == 'table' then return a[1] or a.x or 0, a[2] or a.y or 0 end
    return a or 0, b or 0
end

-- -> true when the numbers changed (the caller re-lays-out)
function draw.measure_font()
    if not (ok_imgui and imgui.GetFontSize) then return false end
    local ok, changed = pcall(function()
        local fs = imgui.GetFontSize()
        if type(fs) ~= 'number' or fs <= 0 then return false end
        local adv = draw.advance_em
        if imgui.CalcTextSize then
            local w = calc('MMMMMMMMMMmmmmmmmmmmiiiiiiiiii')
            if w and w > 0 then adv = (w / 30) / fs end
        end
        local diff = math.abs(fs - draw.font_px) > 0.01 or math.abs(adv - draw.advance_em) > 0.001
        draw.font_px, draw.advance_em = fs, adv
        return diff
    end)
    return ok and changed or false
end

-- ---------------------------------------------------------------------------
-- Flush
-- ---------------------------------------------------------------------------

local OVERLAY_FLAGS = 1 + 2 + 4 + 8 + 16 + 32 + 128 + 256 + 512 + 4096 + 8192 + 65536 + 131072
local UV0, UV1 = {0, 0}, {1, 1}
local PT_TO_PX = 96 / 72

local function text_u32(a, r, g, b) return {r / 255, g / 255, b / 255, a / 255} end

local function put_text(dl, t, scalable, use_dl_text)
    local px = (t.size or 10) * PT_TO_PX
    if scalable then imgui.SetWindowFontScale(px / draw.font_px) end
    local function one(x, y, a, r, g, b)
        if use_dl_text then
            local ok, e = pcall(dl.AddText, dl, {x, y}, abgr(a, r, g, b), t.s)
            if not ok then note_err('AddText', e) end
            return
        end
        imgui.SetCursorScreenPos({x, y})
        imgui.PushStyleColor(0, text_u32(a, r, g, b))      -- ImGuiCol_Text
        if imgui.TextUnformatted then imgui.TextUnformatted(t.s) else imgui.Text(t.s) end
        imgui.PopStyleColor()
    end
    if t.stroke_w and t.stroke_w > 0 and t.sa and t.sa > 0 then
        local o = 1
        one(t.x - o, t.y, t.sa, t.sr, t.sg, t.sb)
        one(t.x + o, t.y, t.sa, t.sr, t.sg, t.sb)
        one(t.x, t.y - o, t.sa, t.sr, t.sg, t.sb)
        one(t.x, t.y + o, t.sa, t.sr, t.sg, t.sb)
    end
    one(t.x, t.y, t.a, t.r, t.g, t.b)
    if t.bold_ then one(t.x + 1, t.y, t.a, t.r, t.g, t.b) end
    draw.counts.text = draw.counts.text + 1
end

local function paint(dl)
    local scalable = imgui.SetWindowFontScale ~= nil and imgui.SetCursorScreenPos ~= nil
                     and imgui.PushStyleColor ~= nil and imgui.PopStyleColor ~= nil
                     and (imgui.TextUnformatted ~= nil or imgui.Text ~= nil)
    local use_dl_text = not scalable

    for i = 1, #prims do
        local o = prims[i]
        if o.vis and not o.dead and o.w > 0 and o.h > 0 then
            if o.kind == 'image' then
                local tex = o.tex and o.tex ~= '' and load_texture(o.tex)
                if tex then
                    local ok, e = pcall(dl.AddImage, dl, tex.id, {o.x, o.y}, {o.x + o.w, o.y + o.h},
                                        UV0, UV1, abgr(o.a, o.r, o.g, o.b))
                    if ok then draw.counts.image = draw.counts.image + 1 else note_err('AddImage', e) end
                end
            else
                local ok, e = pcall(dl.AddRectFilled, dl, {o.x, o.y}, {o.x + o.w, o.y + o.h}, abgr(o.a, o.r, o.g, o.b))
                if ok then draw.counts.rect = draw.counts.rect + 1 else note_err('AddRectFilled', e) end
            end
        end
    end
    for i = 1, #texts do
        local t = texts[i]
        if t.vis and not t.dead and t.s ~= '' then
            local ok, e = pcall(put_text, dl, t, scalable, use_dl_text)
            if not ok then note_err('text', e) end
        end
    end
    if scalable then pcall(imgui.SetWindowFontScale, 1.0) end
end

function draw.flush()
    if not ok_imgui then draw.mode = 'no imgui' return end
    draw.counts.rect, draw.counts.image, draw.counts.text = 0, 0, 0
    prims, texts = compact(prims), compact(texts)

    if not (imgui.Begin and imgui.GetWindowDrawList) then draw.mode = 'no imgui.Begin' return end

    local w, h = 1920, 1080
    local okv, vw, vh = pcall(function()
        local plat = require('platform')
        return plat.viewport()
    end)
    if okv and vw then w, h = vw, vh end

    pcall(function()
        if imgui.SetNextWindowPos then imgui.SetNextWindowPos({0, 0}) end
        if imgui.SetNextWindowSize then imgui.SetNextWindowSize({w, h}) end
    end)
    local began, e = pcall(imgui.Begin, 'questmarks_ui_overlay', true, OVERLAY_FLAGS)
    if not began then note_err('imgui.Begin', e) draw.mode = 'Begin failed' return end
    local okd, dl = pcall(imgui.GetWindowDrawList)
    if okd and dl then
        draw.mode = 'overlay window'
        paint(dl)
    else
        note_err('GetWindowDrawList', dl)
    end
    pcall(imgui.End)
end

return draw
