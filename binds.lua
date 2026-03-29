local mq = require('mq')
local logger = require('lib.lawlgames.lg-logger')

local MODULE_NAME = 'BazUtils'

local Binds = {}

local function showHelp()
    local lines = {
        '--- /bzz Usage ---',
        '/bzz "ItemName"                                 Search the bazaar',
        '/bzz --class WAR --slot Arms --stat HP "Item"   Filtered search',
        '/bzz --buyIfLessThan 100 "Item"                 Buy cheapest exact match under plat',
        '/bzz --buyAllIfLessThan 100 "Item"              Buy ALL exact matches under plat',
        '/bzz --looseMatch --buyIfLessThan 100 "Item"    Substring match instead of exact',
        '/bzz --savequery "Item"                         Save query & record prices',
        '/bzz --savequery --buyAllIfLessThan 10 "Item"   Save auto-buy query (runs hourly)',
        '/bzz --removequery "Item"                       Remove a saved query',
        '/bzz --queries                                  List all saved queries',
        '/bzz --runquery "Item"                          Run a saved query now',
        '/bzz --runall                                   Run all saved queries now',
        '--- Filters: --class --slot --stat --race --type ---',
    }
    for _, l in ipairs(lines) do
        logger.Info(MODULE_NAME, l)
    end
end

--- Parse variadic bind args into a structured options table.
--- Flags are case-insensitive; values and item names preserve case.
local function parseArgs(...)
    local raw = { ... }
    local opts = { filters = {} }
    local nameWords = {}
    local i = 1

    while i <= #raw do
        local flag = raw[i]:lower()

        if     flag == '--class'            then i = i + 1; opts.filters.class = raw[i]
        elseif flag == '--slot'             then i = i + 1; opts.filters.slot  = raw[i]
        elseif flag == '--stat'             then i = i + 1; opts.filters.stat  = raw[i]
        elseif flag == '--race'             then i = i + 1; opts.filters.race  = raw[i]
        elseif flag == '--type'             then i = i + 1; opts.filters.type  = raw[i]
        elseif flag == '--buyiflessthan'    then i = i + 1; opts.buyIfLessThan     = tonumber(raw[i])
        elseif flag == '--buyalliflessthan' then i = i + 1; opts.buyAllIfLessThan  = tonumber(raw[i])
        elseif flag == '--savequery'        then opts.saveQuery    = true
        elseif flag == '--removequery'      then opts.removeQuery  = true
        elseif flag == '--loosematch'       then opts.looseMatch   = true
        elseif flag == '--queries'          then opts.listQueries  = true
        elseif flag == '--runquery'         then opts.runQuery     = true
        elseif flag == '--runall'           then opts.runAll       = true
        elseif flag == '--help'             then opts.help         = true
        else   nameWords[#nameWords + 1] = raw[i]
        end

        i = i + 1
    end

    -- Remaining non-flag tokens form the item name
    opts.itemName = #nameWords > 0 and table.concat(nameWords, ' ') or nil
    return opts
end

--- Register the /bzz bind against a Bazaar instance.
---@param bazaar Bazaar
function Binds.setup(bazaar)
    mq.bind('/bzz', function(...)
        local opts = parseArgs(...)

        -----------------------------------------------------------------
        -- Commands that don't need an item name
        -----------------------------------------------------------------
        if opts.help        then showHelp();                return end
        if opts.listQueries then bazaar:listQueries();      return end
        if opts.runAll      then bazaar:runAllQueries();     return end

        -----------------------------------------------------------------
        -- Commands that require an item name
        -----------------------------------------------------------------
        if opts.runQuery then
            if not opts.itemName then
                logger.Error(MODULE_NAME, 'Usage: /bzz --runquery "ItemName"')
                return
            end
            bazaar:runQuery(opts.itemName)
            return
        end

        if opts.removeQuery then
            if not opts.itemName then
                logger.Error(MODULE_NAME, 'Usage: /bzz --removequery "ItemName"')
                return
            end
            bazaar:removeQuery(opts.itemName)
            return
        end

        if not opts.itemName then
            showHelp()
            return
        end

        -----------------------------------------------------------------
        -- Save query (with optional buy flags for recurring auto-buy)
        -----------------------------------------------------------------
        if opts.saveQuery then
            bazaar:saveQuery(opts.itemName, opts.filters,
                opts.buyIfLessThan, opts.buyAllIfLessThan, opts.looseMatch)
            return
        end

        -----------------------------------------------------------------
        -- One-off buy operations
        -----------------------------------------------------------------
        if opts.buyAllIfLessThan then
            bazaar:buyAllIfLessThan(opts.itemName, opts.buyAllIfLessThan, opts.filters, opts.looseMatch)
            return
        end

        if opts.buyIfLessThan then
            bazaar:buyIfLessThan(opts.itemName, opts.buyIfLessThan, opts.filters, opts.looseMatch)
            return
        end

        -----------------------------------------------------------------
        -- Default: plain search — display results in console
        -----------------------------------------------------------------
        if bazaar:search(opts.itemName, opts.filters) then
            local results = bazaar:getResults()
            for _, r in ipairs(results) do
                logger.Info(MODULE_NAME, '  %s | Qty: %d | %dp %dg %ds %dc | %s',
                    r.name, r.quantity, r.platinum, r.gold, r.silver, r.copper, r.trader)
            end
        end
    end)

    logger.Info(MODULE_NAME, '/bzz registered — type /bzz --help for usage')
end

function Binds.teardown()
    mq.unbind('/bzz')
end

return Binds
