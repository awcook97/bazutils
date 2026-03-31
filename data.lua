---@type Mq
local mq = require('mq')
local fs = require('lib.lawlgames.lg-fs')()
local logger = require('lib.lawlgames.lg-logger')

local MODULE_NAME = 'BazUtils'

local data = {}

--- Relative path (from mq.configDir) for tracking data.
local function trackingRelPath()
    local server = mq.TLO.EverQuest.Server() or 'Unknown'
    return 'bazUtils/' .. server .. '_itemtracking.lua'
end

--- Load tracking data from disk, returning a default table if missing or corrupt.
---@return table
function data.load()
    local relPath = trackingRelPath()
    local fullPath = mq.configDir .. '/' .. relPath
    if not fs.file_exists(fullPath) then return { Items = {} } end

    local ok, loaded = pcall(mq.unpickle, relPath)
    if ok and type(loaded) == 'table' then
        loaded.Items = loaded.Items or {}
        return loaded
    end

    logger.Warn(MODULE_NAME, 'Failed to load tracking data')
    return { Items = {} }
end

--- Persist tracking data to disk.
---@param tracking table
function data.save(tracking)
    fs.ensure_dir(mq.configDir .. '/bazUtils')
    mq.pickle(trackingRelPath(), tracking)
end

return data
