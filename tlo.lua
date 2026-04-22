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
    },

    Methods = {
        --- mq.TLO.BazUtils.Search("Item Name")
        Search = function(itemName, d)
            if not d or not itemName or itemName == '' then return end
            d:enqueue('search:' .. itemName, function()
                if not d:search(itemName, {}) then return end
                local results = d:getResults()
                for _, r in ipairs(results) do
                    logger.Info(MODULE_NAME, '  %s | Qty: %d | %dp %dg %ds %dc | %s',
                        r.name, r.quantity, r.platinum, r.gold, r.silver, r.copper, r.trader)
                end
            end)
        end,

        --- mq.TLO.BazUtils.BuyIfLessThan(maxPlat, "Item Name")
        --- mq.TLO.BazUtils.BuyIfLessThan(maxPlat, count, "Item Name")
        --- ${BazUtils.BuyIfLessThan[maxPlat,Item Name]}
        --- ${BazUtils.BuyIfLessThan[maxPlat,count,Item Name]}
        BuyIfLessThan = function(...)
            local args = { ... }
            local n = #args
            local d = args[n]
            if not d then return end
            local maxPlat, count, name
            if n == 2 then
                -- bracket syntax: single index string e.g. "100,6,Water Flask"
                local s = tostring(args[1])
                local p, c, nm = s:match('^(%d+),(%d+),(.+)$')
                if p then maxPlat, count, name = tonumber(p), tonumber(c), nm
                else p, nm = s:match('^(%d+),(.+)$'); maxPlat, name = tonumber(p), nm end
            elseif n == 3 then maxPlat, name = args[1], args[2]
            elseif n == 4 then maxPlat, count, name = args[1], args[2], args[3]
            end
            if not maxPlat or not name then return end
            d:enqueue('buy:' .. name, function() d:buyIfLessThan(name, maxPlat, {}, false, count) end)
        end,

        --- mq.TLO.BazUtils.BuyAllIfLessThan(maxPlat, "Item Name")
        --- mq.TLO.BazUtils.BuyAllIfLessThan(maxPlat, count, "Item Name")
        --- ${BazUtils.BuyAllIfLessThan[maxPlat,Item Name]}
        --- ${BazUtils.BuyAllIfLessThan[maxPlat,count,Item Name]}
        BuyAllIfLessThan = function(...)
            local args = { ... }
            local n = #args
            local d = args[n]
            if not d then return end
            local maxPlat, count, name
            if n == 2 then
                local s = tostring(args[1])
                local p, c, nm = s:match('^(%d+),(%d+),(.+)$')
                if p then maxPlat, count, name = tonumber(p), tonumber(c), nm
                else p, nm = s:match('^(%d+),(.+)$'); maxPlat, name = tonumber(p), nm end
            elseif n == 3 then maxPlat, name = args[1], args[2]
            elseif n == 4 then maxPlat, count, name = args[1], args[2], args[3]
            end
            if not maxPlat or not name then return end
            d:enqueue('buyall:' .. name, function() d:buyAllIfLessThan(name, maxPlat, {}, false, count) end)
        end,

        --- mq.TLO.BazUtils.SaveQuery("Item Name")
        --- mq.TLO.BazUtils.SaveQuery("Item Name", buyIfLessThan)
        --- mq.TLO.BazUtils.SaveQuery("Item Name", nil, buyAllIfLessThan)
        SaveQuery = function(...)
            local args = { ... }
            local d = args[#args]
            local itemName, buyIfLessThan, buyAllIfLessThan = args[1], args[2], args[3]
            if not d or not itemName then return end
            d:enqueue('savequery:' .. itemName, function()
                d:saveQuery(itemName, {}, buyIfLessThan, buyAllIfLessThan, false)
            end)
        end,

        --- mq.TLO.BazUtils.RemoveQuery("Item Name")
        RemoveQuery = function(itemName, d)
            if not d or not itemName then return end
            d:removeQuery(itemName)
        end,

        --- mq.TLO.BazUtils.RunQuery("Item Name")
        RunQuery = function(itemName, d)
            if not d or not itemName then return end
            d:enqueue('runquery:' .. itemName, function() d:runQuery(itemName) end)
        end,

        --- mq.TLO.BazUtils.RunAll()
        RunAll = function(_, d)
            if not d then return end
            d:enqueue('runall', function() d:runAllQueries() end)
        end,

        --- mq.TLO.BazUtils.ListQueries()
        ListQueries = function(_, d)
            if not d then return end
            d:listQueries()
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
