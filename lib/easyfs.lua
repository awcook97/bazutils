--- Minimal filesystem helpers used by BazUtils.
--- Wraps lfs (LuaFileSystem), which ships with MacroQuest.

local lfs = require('lfs')

local easyfs = {}

---@param path string
---@return boolean
function easyfs.file_exists(path)
    return lfs.attributes(path, 'mode') == 'file'
end

--- Create a directory (and any missing parents) if it does not exist.
---@param path string
function easyfs.ensure_dir(path)
    local sep = package.config:sub(1, 1) -- '/' on Linux, '\\' on Windows
    local current = ''
    for segment in path:gmatch('[^' .. sep .. ']+') do
        current = current .. segment .. sep
        if not lfs.attributes(current, 'mode') then
            lfs.mkdir(current)
        end
    end
end

return easyfs
