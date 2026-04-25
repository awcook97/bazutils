local mq = require('mq')
local logger = require('bazutils.lib.logger')
local data = require('bazutils.data')

local MODULE_NAME = 'BazUtils'

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local C = {
    -- Bazaar search window
    BZR_WND         = 'BazaarSearchWnd',
    BZR_NAME_INPUT  = 'BZR_ItemNameInput',
    BZR_SLOT_COMBO  = 'BZR_ItemSlotCombobox',
    BZR_STAT_COMBO  = 'BZR_StatSlotCombobox',
    BZR_RACE_COMBO  = 'BZR_RaceSlotCombobox',
    BZR_CLASS_COMBO = 'BZR_ClassSlotCombobox',
    BZR_TYPE_COMBO  = 'BZR_ItemTypeCombobox',
    BZR_QUERY_BTN   = 'BZR_QueryButton',
    BZR_BUY_BTN     = 'BZR_BuyButton',
    BZR_ITEM_LIST   = 'BZR_ItemList',
    BZR_CONFIRM_WND = 'BazaarConfirmationWnd',
    BZR_USE_PLAT    = 'BZC_UsePlatButton',

    -- Quantity window
    QTY_WND        = 'QuantityWnd',
    QTY_SLIDER     = 'QTYW_Slider',
    QTY_INPUT      = 'QTYW_SliderInput',
    QTY_ACCEPT_BTN = 'QTYW_Accept_Button',

    -- Result list column indices (1-based, matching UI layout)
    COL = {
        ICON     = 1,
        NAME     = 2,
        QUANTITY = 3,
        PLATINUM = 4,
        GOLD     = 5,
        SILVER   = 6,
        COPPER   = 7,
        TRADER   = 8,
    },

    -- How often (seconds) saved auto-buy queries re-execute
    QUERY_INTERVAL = 3600,
}

---------------------------------------------------------------------------
-- Types
---------------------------------------------------------------------------

---@class BazaarFilters
---@field class string|nil
---@field slot  string|nil
---@field stat  string|nil
---@field race  string|nil
---@field type  string|nil

---@class BazaarSeller
---@field sellerName string
---@field quantity   number
---@field platinum   number

---@class BazaarQueryDef
---@field itemName         string
---@field filters          BazaarFilters
---@field buyIfLessThan    number|nil
---@field buyAllIfLessThan number|nil
---@field looseMatch       boolean

---@class BazaarResult
---@field row      number
---@field name     string
---@field quantity number
---@field platinum number
---@field gold     number
---@field silver   number
---@field copper   number
---@field trader   string
---@field totalPlat number

---------------------------------------------------------------------------
-- Bazaar class
---------------------------------------------------------------------------

---@class BazaarUtility
---@field lastResults BazaarResult[]
---@field lastQuery   table
---@field tracking    table
---@field timers      table<string, number>
---@field cmdQueue    table<string, function>
local Bazaar = {}
Bazaar.__index = Bazaar

---@return BazaarUtility
function Bazaar.new()
    local self = setmetatable({}, Bazaar)
    self.lastResults = {}
    self.lastQuery = {}
    self.tracking = data.load()
    self.timers = {}   -- itemName -> os.time() of last scheduled run
    self.cmdQueue = {} -- keyed set: key -> fn (deduped)
    return self
end

---------------------------------------------------------------------------
-- Window helpers (private)
---------------------------------------------------------------------------

---@private
---@return window|fun()
function Bazaar:wnd()
    return mq.TLO.Window(C.BZR_WND)
end

---@private
---@return boolean
function Bazaar:isOpen()
    return mq.TLO.Window(C.BZR_WND).Open()
end

---@private
---@return boolean
function Bazaar:openWindow()
    if not self:isOpen() then
        self:wnd().DoOpen()
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
---@private
---@param childName string
---@param value     string
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

---@private
function Bazaar:resetFilters()
    if not self:isOpen() then return end
    for _, c in ipairs({ C.BZR_SLOT_COMBO, C.BZR_STAT_COMBO, C.BZR_RACE_COMBO, C.BZR_CLASS_COMBO, C.BZR_TYPE_COMBO }) do
        self:wnd().Child(c).Select(1)
    end
    self:wnd().Child(C.BZR_NAME_INPUT).SetText('')
    mq.delay(100)
end

---------------------------------------------------------------------------
-- Command queue (public)
---------------------------------------------------------------------------

--- Queue a function keyed by a unique string. If the same key is already
--- pending, the new function replaces it (last-write-wins dedup).
--- Required for TLO callbacks, which run on a non-yieldable thread.
---@param key string
---@param fn  function
function Bazaar:enqueue(key, fn)
    self.cmdQueue[key] = fn
end

--- Drain and execute all queued commands. Call once per main-loop tick.
function Bazaar:drainQueue()
    for key, fn in pairs(self.cmdQueue) do
        self.cmdQueue[key] = nil
        fn()
    end
end

---------------------------------------------------------------------------
-- Search (public)
---------------------------------------------------------------------------

--- Execute a bazaar search with optional filters.
---@param itemName string
---@param filters  BazaarFilters|nil
---@return boolean success
function Bazaar:search(itemName, filters)
    filters = filters or {}
    if not self:openWindow() then return false end

    self:resetFilters()

    if itemName and itemName ~= '' then
        self:wnd().Child(C.BZR_NAME_INPUT).SetText(itemName)
        mq.delay(100)
    end

    if filters.class then self:selectCombo(C.BZR_CLASS_COMBO, filters.class) end
    if filters.slot  then self:selectCombo(C.BZR_SLOT_COMBO,  filters.slot)  end
    if filters.stat  then self:selectCombo(C.BZR_STAT_COMBO,  filters.stat)  end
    if filters.race  then self:selectCombo(C.BZR_RACE_COMBO,  filters.race)  end
    if filters.type  then self:selectCombo(C.BZR_TYPE_COMBO,  filters.type)  end

    self.lastQuery = { itemName = itemName, filters = filters }
    mq.delay(3000, function()
        return self:wnd().Child(C.BZR_QUERY_BTN).Enabled() 
    end)
    self:wnd().Child(C.BZR_QUERY_BTN).LeftMouseUp()

    mq.delay(7000, function()
        return (self:wnd().Child(C.BZR_ITEM_LIST).Items() or 0) > 0
    end)
    mq.delay(1000) -- extra settle time

    local count = self:wnd().Child(C.BZR_ITEM_LIST).Items() or 0
    logger.Info(MODULE_NAME, 'Search returned %d result(s)', count)
    return true
end

---------------------------------------------------------------------------
-- Results (public)
---------------------------------------------------------------------------

---@param list any
---@param row  number
---@param col  number
---@return number
local function readNum(list, row, col)
    local raw = list.List(row, col)() or '0'
    logger.Trace('BazaarUtility', "Row: %d, Col: %d, Raw:%s.", row, col, raw)
    return tonumber(raw:gsub(',', ''), 10) or 0
end

--- Read every row from the bazaar result list.
---@return BazaarResult[]
function Bazaar:getResults()
    if not self:openWindow() then return {} end
    local results = {}
    local list  = self:wnd().Child(C.BZR_ITEM_LIST)
    local count = list.Items() or 0

    for row = 1, count do
        local pp = readNum(list, row, C.COL.PLATINUM)
        local gp = readNum(list, row, C.COL.GOLD)
        local sp = readNum(list, row, C.COL.SILVER)
        local cp = readNum(list, row, C.COL.COPPER)

        results[#results + 1] = {
            row       = row,
            name      = list.List(row, C.COL.NAME)()   or '',
            quantity  = readNum(list, row, C.COL.QUANTITY),
            platinum  = pp,
            gold      = gp,
            silver    = sp,
            copper    = cp,
            trader    = list.List(row, C.COL.TRADER)() or '',
            totalPlat = pp + gp / 10 + sp / 100 + cp / 1000,
        }
    end

    self.lastResults = results
    return results
end

--- Sort a results table in-place by field.
---@param results   BazaarResult[]
---@param field     string
---@param ascending boolean|nil  defaults true
---@return BazaarResult[]
function Bazaar:sortResults(results, field, ascending)
    if ascending == nil then ascending = true end
    table.sort(results, function(a, b)
        if ascending then return (a[field] or 0) < (b[field] or 0) end
        return (a[field] or 0) > (b[field] or 0)
    end)
    return results
end

---------------------------------------------------------------------------
-- Buying (public)
---------------------------------------------------------------------------

--- Select a row in the result list and click Buy.
--- Returns the number of items actually purchased (accounts for quantity window).
---@param row     number  1-based row index
---@param wantQty number  how many to buy from this listing
---@return number purchased
function Bazaar:buyItem(row, wantQty)
    if not self:openWindow() then return 0 end
    local attempts = 0
    :: retry ::
    local list = self:wnd().Child(C.BZR_ITEM_LIST)
    list.Select(row)
    mq.delay(500)
    self:wnd().Child(C.BZR_BUY_BTN).LeftMouseUp()
    attempts = attempts + 1
    -- Stackable items show QuantityWnd; non-stackable go straight to ConfirmWnd
    mq.delay(3000, function()
        return mq.TLO.Window(C.QTY_WND).Open() or mq.TLO.Window(C.BZR_CONFIRM_WND).Open()
    end)

    local purchased = wantQty
    if mq.TLO.Window(C.QTY_WND).Open() then
        local available = tonumber(mq.TLO.Window(C.QTY_WND).Child(C.QTY_SLIDER).Value()) or wantQty
        local qty
        if wantQty == 1 then
            qty = 1
        elseif available > wantQty then
            qty = wantQty
        else
            qty = available -- buy all available
        end
        purchased = qty
        mq.TLO.Window(C.QTY_WND).Child(C.QTY_INPUT).SetText(tostring(qty))
        mq.delay(200)
        mq.TLO.Window(C.QTY_WND).Child(C.QTY_ACCEPT_BTN).LeftMouseUp()
        mq.delay(3000, function()
            return mq.TLO.Window(C.BZR_CONFIRM_WND).Open()
        end)
    end

    if mq.TLO.Window(C.BZR_CONFIRM_WND).Open() then
        mq.TLO.Window(C.BZR_CONFIRM_WND).Child(C.BZR_USE_PLAT).LeftMouseUp()
        mq.delay(2000)
    else
        if attempts < 3 then goto retry end
        logger.Warn(MODULE_NAME, 'Confirmation window did not appear')
        purchased = 0
    end

    return purchased
end

--- Buy matching items from the current displayed list (no search).
---@param itemName  string
---@param maxPlat   number
---@param maxCount  number
---@param looseMatch boolean|nil  true = substring match instead of exact
---@return number total items purchased
function Bazaar:buyFromResults(itemName, maxPlat, maxCount, looseMatch)
    local totalBought = 0
    local nameLower = itemName:lower()

    local function nameMatches(resultName)
        if looseMatch then
            return resultName:lower():find(nameLower, 1, true) ~= nil
        end
        return resultName == itemName
    end

    while totalBought < maxCount do
        if not self:isOpen() then break end

        local results = self:sortResults(self:getResults(), 'totalPlat', true)
        local found = false

        for _, item in ipairs(results) do
            if nameMatches(item.name) and item.totalPlat <= maxPlat then
                local wantQty = math.min(maxCount - totalBought, item.quantity)
                logger.Info(MODULE_NAME, 'Buying %d of "%s" from %s for %.1f plat (available %d)',
                    wantQty, item.name, item.trader, item.totalPlat, item.quantity)
                local got = self:buyItem(item.row, wantQty)
                if got > 0 then
                    totalBought = totalBought + got
                    found = true
                end
                break -- re-read list after purchase; row indices shift
            end
        end

        if not found then break end
    end

    if totalBought > 0 then
        logger.Info(MODULE_NAME, 'Purchased %d of "%s" under %d plat', totalBought, itemName, maxPlat)
    else
        logger.Info(MODULE_NAME, 'No "%s" found at or below %d plat', itemName, maxPlat)
    end
    return totalBought
end

--- Search then buy up to `count` cheapest matches under maxPlat.
---@param itemName  string
---@param maxPlat   number
---@param filters   BazaarFilters|nil
---@param looseMatch boolean|nil
---@param count     number|nil  max to purchase (default 1)
---@return boolean
function Bazaar:buyIfLessThan(itemName, maxPlat, filters, looseMatch, count)
    if not self:search(itemName, filters) then return false end
    return self:buyFromResults(itemName, maxPlat, count or 1, looseMatch) > 0
end

--- Search then buy ALL matches under maxPlat, up to `count` listings.
---@param itemName  string
---@param maxPlat   number
---@param filters   BazaarFilters|nil
---@param looseMatch boolean|nil
---@param count     number|nil  max to purchase (default 200)
---@return number bought
function Bazaar:buyAllIfLessThan(itemName, maxPlat, filters, looseMatch, count)
    if not self:search(itemName, filters) then return 0 end
    return self:buyFromResults(itemName, maxPlat, count or 200, looseMatch)
end

---------------------------------------------------------------------------
-- Tracking / Saved Queries (public)
---------------------------------------------------------------------------

---@param itemName string
---@param results  BazaarResult[]
---@param queryDef BazaarQueryDef
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

    data.save(self.tracking)
    logger.Info(MODULE_NAME, 'Recorded %d seller(s) for "%s"', #sellers, itemName)
end

--- Save a query for price tracking (and optional recurring auto-buy).
--- Executes immediately, then re-runs automatically if buyIfLessThan or
--- buyAllIfLessThan is set.
---@param itemName         string
---@param filters          BazaarFilters|nil
---@param buyIfLessThan    number|nil
---@param buyAllIfLessThan number|nil
---@param looseMatch       boolean|nil
function Bazaar:saveQuery(itemName, filters, buyIfLessThan, buyAllIfLessThan, looseMatch)
    local queryDef = {
        itemName         = itemName,
        filters          = filters or {},
        buyIfLessThan    = buyIfLessThan,
        buyAllIfLessThan = buyAllIfLessThan,
        looseMatch       = looseMatch or false,
    }

    if self:search(itemName, filters) then
        -- Record prices BEFORE buying so tracking reflects full market
        self:recordResults(itemName, self:getResults(), queryDef)

        if buyAllIfLessThan then
            self:buyFromResults(itemName, buyAllIfLessThan, 200, looseMatch)
        elseif buyIfLessThan then
            self:buyFromResults(itemName, buyIfLessThan, 1, looseMatch)
        end
    else
        -- Persist the query definition even if the search couldn't run
        self.tracking.Items[itemName] = {
            LastSeen = { date = os.date('%Y-%m-%d %H:%M:%S'), sellers = {}, query = queryDef },
        }
        data.save(self.tracking)
    end

    self.timers[itemName] = os.time()
    logger.Info(MODULE_NAME, 'Saved query for "%s"', itemName)
end

---@param itemName string
---@return boolean
function Bazaar:removeQuery(itemName)
    if self.tracking.Items[itemName] then
        self.tracking.Items[itemName] = nil
        self.timers[itemName] = nil
        data.save(self.tracking)
        logger.Info(MODULE_NAME, 'Removed query for "%s"', itemName)
        return true
    end
    logger.Warn(MODULE_NAME, 'No saved query for "%s"', itemName)
    return false
end

function Bazaar:listQueries()
    local count = 0
    for itemName, entry in pairs(self.tracking.Items) do
        count = count + 1
        local ls = entry.LastSeen or {}
        local q  = ls.query or {}
        local line = string.format('  [%s] Last: %s | Sellers: %d',
            itemName, ls.date or 'never',
            (ls.sellers and #ls.sellers) or 0)

        if q.buyIfLessThan    then line = line .. string.format(' | buyIfLessThan=%d',    q.buyIfLessThan)    end
        if q.buyAllIfLessThan then line = line .. string.format(' | buyAllIfLessThan=%d', q.buyAllIfLessThan) end

        logger.Info(MODULE_NAME, line)
    end
    if count == 0 then
        logger.Info(MODULE_NAME, 'No saved queries')
    end
end

---@param itemName string
---@return boolean
function Bazaar:runQuery(itemName)
    local entry = self.tracking.Items[itemName]
    if not entry or not entry.LastSeen or not entry.LastSeen.query then
        logger.Warn(MODULE_NAME, 'No saved query for "%s"', itemName)
        return false
    end

    local q = entry.LastSeen.query
    if not self:search(itemName, q.filters) then return false end

    self:recordResults(itemName, self:getResults(), q)

    if q.buyAllIfLessThan then
        self:buyFromResults(itemName, q.buyAllIfLessThan, 200, q.looseMatch)
    elseif q.buyIfLessThan then
        self:buyFromResults(itemName, q.buyIfLessThan, 1, q.looseMatch)
    end

    self.timers[itemName] = os.time()
    return true
end

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
    for itemName, entry in pairs(self.tracking.Items) do
        local q = entry.LastSeen and entry.LastSeen.query
        if q and (q.buyIfLessThan or q.buyAllIfLessThan) then
            local last = self.timers[itemName] or 0
            if now - last >= C.QUERY_INTERVAL then
                logger.Info(MODULE_NAME, 'Scheduled query: "%s"', itemName)
                self:runQuery(itemName)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Data accessors (public)
---------------------------------------------------------------------------

---@param itemName string
---@return table|nil
function Bazaar:getQueryData(itemName)
    return self.tracking.Items[itemName]
end

---@return table
function Bazaar:getTrackingData()
    return self.tracking
end

function Bazaar:reloadTracking()
    self.tracking = data.load()
    logger.Info(MODULE_NAME, 'Reloaded tracking data from disk')
end

Bazaar.Constants = C

return Bazaar
