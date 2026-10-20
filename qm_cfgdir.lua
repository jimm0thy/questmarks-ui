--[[ qm_cfgdir.lua -- where this addon keeps its saved data.

     Ashita addons conventionally save under <Ashita>/config/addons/<name>/, which survives deleting or
     re-extracting the addon folder. This returns that folder (created on demand, with a trailing
     separator), or nil when it can't be used, in which case callers fall back to the addon's own folder.
     migrate() copies a file saved by an older version from the addon folder into the config folder the
     first time, and never deletes the old copy. ]]
local M = {}
local cache = {}

local function exists(p)
    local f = io.open(p, 'rb')
    if f then f:close() return true end
    return false
end

function M.dir(name)
    if cache[name] ~= nil then return cache[name] or nil end
    local ok, d = pcall(function()
        local base = AshitaCore:GetInstallPath()
        if type(base) ~= 'string' or base == '' then return nil end
        local sep = (base:find('/', 1, true) and not base:find('\\', 1, true)) and '/' or '\\'
        if not base:match('[\\/]$') then base = base .. sep end
        local dir = base .. 'config' .. sep .. 'addons' .. sep .. name .. sep
        if ashita and ashita.fs and ashita.fs.create_dir then ashita.fs.create_dir(dir) end
        local probe = dir .. '.write_test'
        local f = io.open(probe, 'wb')
        if not f then return nil end
        f:close(); os.remove(probe)
        return dir
    end)
    cache[name] = (ok and d) or false
    return cache[name] or nil
end

-- -> path to use for `file`: the config folder's copy (migrated from the addon folder on first use), else the old path.
function M.path(name, file, old_dir)
    local d = M.dir(name)
    local old = (old_dir or '') .. file
    if not d then return old end
    local new = d .. file
    if not exists(new) and exists(old) then
        pcall(function()
            local i = io.open(old, 'rb'); local data = i:read('*a'); i:close()
            local o = io.open(new, 'wb'); if o then o:write(data); o:close() end
        end)
    end
    return new
end

return M
