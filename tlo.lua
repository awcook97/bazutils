---@type Mq
local mq = require('mq')
local logger = require('lib.lawlgames.lg-logger')

local MODULE_NAME = 'BazUtils'

local tlo = {}

local bazInstance = nil

---------------------------------------------------------------------------
-- DataTypes
--
-- ${BazUtils.Item[Water Flask].LastSeen}
-- ${BazUtils.Item[Water Flask].Sellers}
-- ${BazUtils.QueryCount}
---------------------------------------------------------------------------

---@diagnostic disable: return-type-mismatch, redundant-parameter
local BazUtilsItemType = mq.DataType.new('BazUtilsItem', {
    Members = {
        LastSeen = function(_, item)
            local ls = item and item.LastSeen
            return 'string', ls and ls.date or 'never'
        end,
        Sellers = function(_, item)
            local ls = item and item.LastSeen
            return 'int', (ls and ls.sellers) and #ls.sellers or 0
        end,
        CheapestPlat = function(_, item)
            local ls = item and item.LastSeen
            if not ls or not ls.sellers or #ls.sellers == 0 then return 'int', 0 end
            local min = ls.sellers[1].platinum or 0
            for i = 2, #ls.sellers do
                local p = ls.sellers[i].platinum or 0
                if p < min then min = p end
            end
            return 'int', min
        end,
        HasBuyRule = function(_, item)
            local q = item and item.LastSeen and item.LastSeen.query
            if not q then return 'bool', false end
            return 'bool', (q.buyIfLessThan or q.buyAllIfLessThan) and true or false
        end,
    },
    ToString = function(item)
        if not item or not item.LastSeen then return 'NULL' end
        return string.format('LastSeen: %s | Sellers: %d',
            item.LastSeen.date or 'never',
            (item.LastSeen.sellers and #item.LastSeen.sellers) or 0)
    end,
})

--- Parse "maxPlat|Item Name" from a TLO index string.
---@return number|nil, string|nil
local function parsePlatItem(idx)
    if not idx or idx == '' then return nil, nil end
    local plat, name = idx:match('^(%d+)|(.+)$')
    return tonumber(plat), name
end

local BazUtilsType = mq.DataType.new('BazUtils', {
    Members = {
        --- ${BazUtils.Item[Item Name]}
        Item = function(idx, d)
            if not d or not idx then return 'string', nil end
            return BazUtilsItemType, d.tracking.Items[idx]
        end,

        --- ${BazUtils.QueryCount}
        QueryCount = function(_, d)
            if not d then return 'int', 0 end
            local n = 0
            for _ in pairs(d.tracking.Items) do n = n + 1 end
            return 'int', n
        end,

        --- ${BazUtils.Search[Item Name]} - Search and print results
        Search = function(idx, d)
            if not d or not idx or idx == '' then return 'bool', false end
            d:enqueue('search:' .. idx, function()
                if not d:search(idx, {}) then return end
                local results = d:getResults()
                for _, r in ipairs(results) do
                    logger.Info(MODULE_NAME, '  %s | Qty: %d | %dp %dg %ds %dc | %s',
                        r.name, r.quantity, r.platinum, r.gold, r.silver, r.copper, r.trader)
                end
            end)
            return 'bool', true
        end,

        --- ${BazUtils.BuyIfLessThan[maxPlat|Item Name]} - Buy cheapest match under plat
        BuyIfLessThan = function(idx, d)
            if not d then return 'bool', false end
            local plat, name = parsePlatItem(idx)
            if not plat or not name then return 'bool', false end
            d:enqueue('buy:' .. name, function() d:buyIfLessThan(name, plat, {}, false) end)
            return 'bool', true
        end,

        --- ${BazUtils.BuyAllIfLessThan[maxPlat|Item Name]} - Buy all matches under plat
        BuyAllIfLessThan = function(idx, d)
            if not d then return 'bool', false end
            local plat, name = parsePlatItem(idx)
            if not plat or not name then return 'bool', false end
            d:enqueue('buyall:' .. name, function() d:buyAllIfLessThan(name, plat, {}, false) end)
            return 'bool', true
        end,

        --- ${BazUtils.SaveQuery[Item Name]} - Save tracking query (no buy rule)
        SaveQuery = function(idx, d)
            if not d or not idx or idx == '' then return 'bool', false end
            d:enqueue('savequery:' .. idx, function() d:saveQuery(idx, {}) end)
            return 'bool', true
        end,

        --- ${BazUtils.SaveQueryBuy[maxPlat|Item Name]} - Save query with buyIfLessThan rule
        SaveQueryBuy = function(idx, d)
            if not d then return 'bool', false end
            local plat, name = parsePlatItem(idx)
            if not plat or not name then return 'bool', false end
            d:enqueue('savequerybuy:' .. name, function() d:saveQuery(name, {}, plat, nil, false) end)
            return 'bool', true
        end,

        --- ${BazUtils.SaveQueryBuyAll[maxPlat|Item Name]} - Save query with buyAllIfLessThan rule
        SaveQueryBuyAll = function(idx, d)
            if not d then return 'bool', false end
            local plat, name = parsePlatItem(idx)
            if not plat or not name then return 'bool', false end
            d:enqueue('savequerybuyall:' .. name, function() d:saveQuery(name, {}, nil, plat, false) end)
            return 'bool', true
        end,

        --- ${BazUtils.RemoveQuery[Item Name]} - Remove a saved query
        RemoveQuery = function(idx, d)
            if not d or not idx or idx == '' then return 'bool', false end
            return 'bool', d:removeQuery(idx)
        end,

        --- ${BazUtils.RunQuery[Item Name]} - Run a saved query now
        RunQuery = function(idx, d)
            if not d or not idx or idx == '' then return 'bool', false end
            d:enqueue('runquery:' .. idx, function() d:runQuery(idx) end)
            return 'bool', true
        end,

        --- ${BazUtils.RunAll} - Run all saved queries now
        RunAll = function(_, d)
            if not d then return 'bool', false end
            d:enqueue('runall', function() d:runAllQueries() end)
            return 'bool', true
        end,

        --- ${BazUtils.ListQueries} - Print all saved queries to console
        ListQueries = function(_, d)
            if not d then return 'bool', false end
            d:listQueries()
            return 'bool', true
        end,
    },
    ToString = function(d)
        if not d then return 'BazUtils (not loaded)' end
        local n = 0
        for _ in pairs(d.tracking.Items) do n = n + 1 end
        return string.format('BazUtils (%d queries)', n)
    end,
})
---@diagnostic enable: return-type-mismatch, redundant-parameter

---------------------------------------------------------------------------
-- Register / Unregister
---------------------------------------------------------------------------

--- Register the ${BazUtils} TLO against a Bazaar instance.
---@param bazaar Bazaar
function tlo.register(bazaar)
    bazInstance = bazaar
    mq.AddTopLevelObject('BazUtils', function(_)
        return BazUtilsType, bazInstance
    end)
    logger.Info(MODULE_NAME, 'Registered ${BazUtils} TLO')
end

--- Unregister the TLO (call on script exit).
function tlo.unregister()
    mq.RemoveTopLevelObject('BazUtils')
    bazInstance = nil
end

return tlo
