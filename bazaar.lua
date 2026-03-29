local mq = require('mq')
local logger = require('lib.lawlgames.lg-logger')

local MODULE_NAME = 'BazUtils'

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local BZR_WND         = 'BazaarSearchWnd'
local BZR_NAME_INPUT  = 'BZR_ItemNameInput'
local BZR_SLOT_COMBO  = 'BZR_ItemSlotCombobox'
local BZR_STAT_COMBO  = 'BZR_StatSlotCombobox'
local BZR_RACE_COMBO  = 'BZR_RaceSlotCombobox'
local BZR_CLASS_COMBO = 'BZR_ClassSlotCombobox'
local BZR_TYPE_COMBO  = 'BZR_ItemTypeCombobox'
local BZR_QUERY_BTN   = 'BZR_QueryButton'
local BZR_BUY_BTN     = 'BZR_BuyButton'
local BZR_ITEM_LIST   = 'BZR_ItemList'

-- Result list column indices (1-based, matching UI layout)
local COL = {
    ICON     = 1,
    NAME     = 2,
    QUANTITY = 3,
    PLATINUM = 4,
    GOLD     = 5,
    SILVER   = 6,
    COPPER   = 7,
    TRADER   = 8,
}

-- How often (seconds) saved auto-buy queries re-execute
local QUERY_INTERVAL = 3600

---------------------------------------------------------------------------
-- Lua table serializer (writes loadfile()-compatible .lua files)
---------------------------------------------------------------------------

local serialize -- forward declaration

local function serializeValue(v, indent)
    local t = type(v)
    if t == 'string' then
        return string.format('%q', v)
    elseif t == 'number' or t == 'boolean' then
        return tostring(v)
    elseif t == 'table' then
        return serialize(v, indent)
    end
    return 'nil'
end

serialize = function(tbl, indent)
    indent = indent or ''
    local ni = indent .. '    '
    local parts = { '{\n' }
    local n = #tbl

    -- Array part
    for i = 1, n do
        parts[#parts + 1] = ni .. serializeValue(tbl[i], ni) .. ',\n'
    end

    -- Hash part (sorted keys for stable output)
    local hashKeys = {}
    for k in pairs(tbl) do
        if type(k) ~= 'number' or k < 1 or k > n or k ~= math.floor(k) then
            hashKeys[#hashKeys + 1] = k
        end
    end
    table.sort(hashKeys, function(a, b) return tostring(a) < tostring(b) end)

    for _, k in ipairs(hashKeys) do
        local ks
        if type(k) == 'string' and k:match('^[%a_][%w_]*$') then
            ks = k
        else
            ks = '[' .. serializeValue(k, ni) .. ']'
        end
        parts[#parts + 1] = ni .. ks .. ' = ' .. serializeValue(tbl[k], ni) .. ',\n'
    end

    parts[#parts + 1] = indent .. '}'
    return table.concat(parts)
end

---------------------------------------------------------------------------
-- Persistence helpers
---------------------------------------------------------------------------

local function trackingDir()
    return mq.configDir .. '/bazUtils'
end

local function trackingPath()
    local server = mq.TLO.EverQuest.Server() or 'Unknown'
    return trackingDir() .. '/' .. server .. '_itemtracking.lua'
end

local function ensureDir(dir)
    os.execute('mkdir -p "' .. dir .. '"')
end

local function loadTracking()
    local path = trackingPath()
    local f = io.open(path, 'r')
    if not f then return { Items = {} } end
    f:close()

    local fn, err = loadfile(path)
    if fn then
        local ok, data = pcall(fn)
        if ok and type(data) == 'table' then
            data.Items = data.Items or {}
            return data
        end
    end
    logger.Warn(MODULE_NAME, 'Failed to load tracking data: %s', err or 'bad data')
    return { Items = {} }
end

local function saveTracking(data)
    ensureDir(trackingDir())
    local path = trackingPath()
    local f, err = io.open(path, 'w')
    if not f then
        logger.Error(MODULE_NAME, 'Cannot write %s: %s', path, err or '')
        return false
    end
    f:write('return ' .. serialize(data) .. '\n')
    f:close()
    return true
end

---------------------------------------------------------------------------
-- Bazaar class
---------------------------------------------------------------------------

---@class Bazaar
---@field lastResults table[]
---@field lastQuery table
---@field tracking table
---@field timers table<string, number>
local Bazaar = {}
Bazaar.__index = Bazaar

function Bazaar.new()
    local self = setmetatable({}, Bazaar)
    self.lastResults = {}
    self.lastQuery = {}
    self.tracking = loadTracking()
    self.timers = {} -- itemName -> os.time() of last scheduled run
    return self
end

---------------------------------------------------------------------------
-- Window helpers
---------------------------------------------------------------------------

function Bazaar:wnd()
    return mq.TLO.Window(BZR_WND)
end

function Bazaar:isOpen()
    return mq.TLO.Window(BZR_WND).Open()
end

function Bazaar:openWindow()
    if not self:isOpen() then
        mq.cmd('/baz')
        mq.delay(3000, function() return self:isOpen() end)
    end
    if not self:isOpen() then
        logger.Error(MODULE_NAME, 'Could not open Bazaar window')
        return false
    end
    return true
end

--- Select a value in a combobox by display text.
--- Tries exact match first, then substring/partial.
---@param childName string  UI child control name
---@param value string      Text to look for
---@return boolean
function Bazaar:selectCombo(childName, value)
    if not value or value == '' then return true end
    if not self:isOpen() then return false end
    local combo = self:wnd().Child(childName)

    local idx = combo.List('=' .. value)()
    if not idx or idx <= 0 then
        idx = combo.List(value)()
    end
    if idx and idx > 0 then
        combo.Select(idx)
        mq.delay(100)
        return true
    end

    logger.Warn(MODULE_NAME, 'Value "%s" not found in %s', value, childName)
    return false
end

--- Reset every filter combobox to index 1 ("Any") and clear the name field.
function Bazaar:resetFilters()
    if not self:isOpen() then return end
    for _, c in ipairs({ BZR_SLOT_COMBO, BZR_STAT_COMBO, BZR_RACE_COMBO, BZR_CLASS_COMBO, BZR_TYPE_COMBO }) do
        self:wnd().Child(c).Select(1)
    end
    self:wnd().Child(BZR_NAME_INPUT).SetText('')
    mq.delay(100)
end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------

--- Execute a bazaar search with optional filters.
---@param itemName string
---@param filters table|nil  { class, slot, stat, race, type }
---@return boolean success
function Bazaar:search(itemName, filters)
    filters = filters or {}
    if not self:openWindow() then return false end

    self:resetFilters()

    if itemName and itemName ~= '' then
        self:wnd().Child(BZR_NAME_INPUT).SetText(itemName)
        mq.delay(100)
    end

    if filters.class then self:selectCombo(BZR_CLASS_COMBO, filters.class) end
    if filters.slot  then self:selectCombo(BZR_SLOT_COMBO,  filters.slot)  end
    if filters.stat  then self:selectCombo(BZR_STAT_COMBO,  filters.stat)  end
    if filters.race  then self:selectCombo(BZR_RACE_COMBO,  filters.race)  end
    if filters.type  then self:selectCombo(BZR_TYPE_COMBO,  filters.type)  end

    self.lastQuery = { itemName = itemName, filters = filters }

    -- Fire the query
    self:wnd().Child(BZR_QUERY_BTN).LeftMouseUp()

    -- Wait for results to populate
    mq.delay(5000, function()
        return (self:wnd().Child(BZR_ITEM_LIST).Items() or 0) > 0
    end)
    mq.delay(1000) -- extra settle time

    local count = self:wnd().Child(BZR_ITEM_LIST).Items() or 0
    logger.Info(MODULE_NAME, 'Search returned %d result(s)', count)
    return true
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------

--- Read every row from the bazaar result list.
---@return table[]
function Bazaar:getResults()
    if not self:openWindow() then return {} end
    local results = {}
    local list = self:wnd().Child(BZR_ITEM_LIST)
    local count = list.Items() or 0

    for row = 1, count do
        local pp = tonumber(list.List(row, COL.PLATINUM)()) or 0
        local gp = tonumber(list.List(row, COL.GOLD)())     or 0
        local sp = tonumber(list.List(row, COL.SILVER)())   or 0
        local cp = tonumber(list.List(row, COL.COPPER)())   or 0

        results[#results + 1] = {
            row      = row,
            name     = list.List(row, COL.NAME)()     or '',
            quantity = tonumber(list.List(row, COL.QUANTITY)()) or 0,
            platinum = pp,
            gold     = gp,
            silver   = sp,
            copper   = cp,
            trader   = list.List(row, COL.TRADER)()   or '',
            totalPlat = pp + gp / 10 + sp / 100 + cp / 1000,
        }
    end

    self.lastResults = results
    return results
end

--- Sort a results table in-place by field.
---@param results table[]
---@param field string
---@param ascending boolean|nil  defaults true
---@return table[]
function Bazaar:sortResults(results, field, ascending)
    if ascending == nil then ascending = true end
    table.sort(results, function(a, b)
        if ascending then return (a[field] or 0) < (b[field] or 0) end
        return (a[field] or 0) > (b[field] or 0)
    end)
    return results
end

---------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------

--- Select a row in the result list and click Buy.
---@param row number  1-based row index
function Bazaar:buyItem(row)
    if not self:openWindow() then return end
    local list = self:wnd().Child(BZR_ITEM_LIST)
    list.Select(row)
    mq.delay(500)
    self:wnd().Child(BZR_BUY_BTN).LeftMouseUp()
    mq.delay(2000)
end

--- Buy matching items from the *current* displayed list (no search).
--- Does an exact-name compare before purchasing.
---@param itemName string   Exact item name to match
---@param maxPlat  number   Maximum total price in platinum
---@param buyAll   boolean  true = keep buying all matches; false = first only
---@return number  count of purchases made
function Bazaar:buyFromResults(itemName, maxPlat, buyAll)
    local bought = 0
    local maxIter = 200 -- safety cap

    while bought < maxIter do
        if not self:isOpen() then break end

        local results = self:sortResults(self:getResults(), 'totalPlat', true)
        local found = false

        for _, item in ipairs(results) do
            if item.name == itemName and item.totalPlat <= maxPlat then
                logger.Info(MODULE_NAME, 'Buying "%s" from %s for %.1f plat (qty %d)',
                    item.name, item.trader, item.totalPlat, item.quantity)
                self:buyItem(item.row)
                bought = bought + 1
                found = true
                break -- re-read list; row indices shifted after purchase
            end
        end

        if not found or not buyAll then break end
    end

    if bought > 0 then
        logger.Info(MODULE_NAME, 'Purchased %d listing(s) of "%s" under %d plat', bought, itemName, maxPlat)
    else
        logger.Info(MODULE_NAME, 'No "%s" found at or below %d plat', itemName, maxPlat)
    end
    return bought
end

--- Search then buy the single cheapest exact-match item under maxPlat.
---@return boolean
function Bazaar:buyIfLessThan(itemName, maxPlat, filters)
    if not self:search(itemName, filters) then return false end
    return self:buyFromResults(itemName, maxPlat, false) > 0
end

--- Search then buy ALL exact-match items under maxPlat.
---@return number bought
function Bazaar:buyAllIfLessThan(itemName, maxPlat, filters)
    if not self:search(itemName, filters) then return 0 end
    return self:buyFromResults(itemName, maxPlat, true)
end

---------------------------------------------------------------------------
-- Tracking / Saved Queries
---------------------------------------------------------------------------

--- Record search results for an item into the tracking file.
function Bazaar:recordResults(itemName, results, queryDef)
    local sellers = {}
    for _, r in ipairs(results) do
        if r.name == itemName then
            sellers[#sellers + 1] = {
                sellerName = r.trader,
                quantity   = r.quantity,
                platinum   = r.totalPlat,
            }
        end
    end

    self.tracking.Items[itemName] = self.tracking.Items[itemName] or {}
    self.tracking.Items[itemName].LastSeen = {
        date    = os.date('%Y-%m-%d %H:%M:%S'),
        sellers = sellers,
        query   = queryDef,
    }

    saveTracking(self.tracking)
    logger.Info(MODULE_NAME, 'Recorded %d seller(s) for "%s"', #sellers, itemName)
end

--- Save a query for price tracking (and optional recurring auto-buy).
--- Executes immediately, then schedules for future automatic runs if
--- buyIfLessThan or buyAllIfLessThan is set.
function Bazaar:saveQuery(itemName, filters, buyIfLessThan, buyAllIfLessThan)
    local queryDef = {
        itemName         = itemName,
        filters          = filters or {},
        buyIfLessThan    = buyIfLessThan,
        buyAllIfLessThan = buyAllIfLessThan,
    }

    if self:search(itemName, filters) then
        -- Record prices BEFORE buying so tracking reflects full market
        self:recordResults(itemName, self:getResults(), queryDef)

        -- Execute buy if configured
        if buyAllIfLessThan then
            self:buyFromResults(itemName, buyAllIfLessThan, true)
        elseif buyIfLessThan then
            self:buyFromResults(itemName, buyIfLessThan, false)
        end
    else
        -- Still persist the query definition even if the search couldn't run
        self.tracking.Items[itemName] = {
            LastSeen = { date = os.date('%Y-%m-%d %H:%M:%S'), sellers = {}, query = queryDef },
        }
        saveTracking(self.tracking)
    end

    self.timers[itemName] = os.time()
    logger.Info(MODULE_NAME, 'Saved query for "%s"', itemName)
end

--- Remove a saved query.
---@return boolean
function Bazaar:removeQuery(itemName)
    if self.tracking.Items[itemName] then
        self.tracking.Items[itemName] = nil
        self.timers[itemName] = nil
        saveTracking(self.tracking)
        logger.Info(MODULE_NAME, 'Removed query for "%s"', itemName)
        return true
    end
    logger.Warn(MODULE_NAME, 'No saved query for "%s"', itemName)
    return false
end

--- Print every saved query to the MQ console.
function Bazaar:listQueries()
    local count = 0
    for itemName, data in pairs(self.tracking.Items) do
        count = count + 1
        local ls = data.LastSeen or {}
        local q  = ls.query or {}
        local line = string.format('  [%s] Last: %s | Sellers: %d',
            itemName, ls.date or 'never',
            (ls.sellers and #ls.sellers) or 0)

        if q.buyIfLessThan then
            line = line .. string.format(' | buyIfLessThan=%d', q.buyIfLessThan)
        end
        if q.buyAllIfLessThan then
            line = line .. string.format(' | buyAllIfLessThan=%d', q.buyAllIfLessThan)
        end

        logger.Info(MODULE_NAME, line)
    end
    if count == 0 then
        logger.Info(MODULE_NAME, 'No saved queries')
    end
end

--- Run a single saved query: search, record results, optionally buy.
---@return boolean
function Bazaar:runQuery(itemName)
    local entry = self.tracking.Items[itemName]
    if not entry or not entry.LastSeen or not entry.LastSeen.query then
        logger.Warn(MODULE_NAME, 'No saved query for "%s"', itemName)
        return false
    end

    local q = entry.LastSeen.query
    if not self:search(itemName, q.filters) then return false end

    -- Record market snapshot
    self:recordResults(itemName, self:getResults(), q)

    -- Buy if configured
    if q.buyAllIfLessThan then
        self:buyFromResults(itemName, q.buyAllIfLessThan, true)
    elseif q.buyIfLessThan then
        self:buyFromResults(itemName, q.buyIfLessThan, false)
    end

    self.timers[itemName] = os.time()
    return true
end

--- Run ALL saved queries now (ignoring timers).
function Bazaar:runAllQueries()
    local count = 0
    for itemName in pairs(self.tracking.Items) do
        count = count + 1
        logger.Info(MODULE_NAME, 'Running query: "%s"', itemName)
        self:runQuery(itemName)
    end
    if count == 0 then
        logger.Info(MODULE_NAME, 'No saved queries to run')
    end
end

--- Run only saved queries with buy settings whose timer has expired.
--- Called automatically from the main loop.
function Bazaar:runDueQueries()
    local now = os.time()
    for itemName, data in pairs(self.tracking.Items) do
        local q = data.LastSeen and data.LastSeen.query
        if q and (q.buyIfLessThan or q.buyAllIfLessThan) then
            local last = self.timers[itemName] or 0
            if now - last >= QUERY_INTERVAL then
                logger.Info(MODULE_NAME, 'Scheduled query: "%s"', itemName)
                self:runQuery(itemName)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Data accessors ("TLO" replacement)
--
-- MQ Top-Level Objects cannot be created from Lua; they require a C++
-- plugin.  These methods provide the equivalent programmatic interface.
-- Other scripts can require('bazutils.bazaar'), call Bazaar.new() or
-- share an instance, and use these accessors to read/write query data.
---------------------------------------------------------------------------

--- Get tracking data for a single item.
---@param itemName string
---@return table|nil
function Bazaar:getQueryData(itemName)
    return self.tracking.Items[itemName]
end

--- Get the full tracking table ({ Items = { ... } }).
---@return table
function Bazaar:getTrackingData()
    return self.tracking
end

--- Reload tracking data from disk (useful after external edits).
function Bazaar:reloadTracking()
    self.tracking = loadTracking()
    logger.Info(MODULE_NAME, 'Reloaded tracking data from disk')
end

return Bazaar
