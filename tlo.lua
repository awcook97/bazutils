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
        Item = function(idx, d)
            if not d or not idx then return 'string', nil end
            return BazUtilsItemType, d.tracking.Items[idx]
        end,
        QueryCount = function(_, d)
            if not d then return 'int', 0 end
            local n = 0
            for _ in pairs(d.tracking.Items) do n = n + 1 end
            return 'int', n
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
