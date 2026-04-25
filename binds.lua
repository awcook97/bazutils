local mq = require('mq')
local logger = require('lib.lawlgames.lg-logger')

local MODULE_NAME = 'BazUtils'

local Binds = {}

---Shows help, if showFlags is true then shows the flags instead.
---@param showFlags boolean?
local function showHelp(showFlags)
    local lines = {
        '--- /bzz Usage ---',
        '/bzz "ItemName"                                 Search the bazaar',
        '/bzz --class WAR --slot Arms --stat HP "Item"   Filtered search',
        '/bzz --buyIfLessThan 100 "Item"                 Buy cheapest exact match under plat',
        '/bzz --buyIfLessThan 100 --count 6 "Item"       Buy up to 6 listings under plat',
        '/bzz --buyAllIfLessThan 100 "Item"              Buy ALL exact matches under plat',
        '/bzz --buyAllIfLessThan 100 --count 6 "Item"    Buy up to 6 listings (all mode) under plat',
        '/bzz --looseMatch --buyIfLessThan 100 "Item"    Substring match instead of exact',
        '/bzz --savequery "Item"                         Save query & record prices',
        '/bzz --savequery --buyAllIfLessThan 10 "Item"   Save auto-buy query (runs hourly)',
        '/bzz --removequery "Item"                       Remove a saved query',
        '/bzz --queries                                  List all saved queries',
        '/bzz --runquery "Item"                          Run a saved query now',
        '/bzz --runall                                   Run all saved queries now',
        '/bzz --help f                                   Shows the list of flags',
        '--- Filters: --class --slot --stat --race --type ---',
    }
    if showFlags then
        lines = {
            '-cl | --class',
            '-i | --slot',
            '-st | --stat',
            '-r | --race',
            '-t | --type',
            '-b | --buyiflessthan',
            '-ba | --buyalliflessthan',
            '-c | --count',
            '-s | --savequery',
            '-rm | --removequery',
            '-l | --loosematch',
            '-q | --queries',
            '-rq | --runquery',
            '-ra | --runall',
            '-h | --help',
        }
    end
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

        if     flag == '-cl' or flag == '--class'            then i = i + 1; opts.filters.class = raw[i]
        elseif flag == '-i' or flag == '--slot'             then i = i + 1; opts.filters.slot  = raw[i]
        elseif flag == '-st' or flag == '--stat'             then i = i + 1; opts.filters.stat  = raw[i]
        elseif flag == '-r' or flag == '--race'             then i = i + 1; opts.filters.race  = raw[i]
        elseif flag == '-t' or flag == '--type'             then i = i + 1; opts.filters.type  = raw[i]
        elseif flag == '-b' or flag == '--buyiflessthan'    then i = i + 1; opts.buyIfLessThan     = tonumber(raw[i])
        elseif flag == '-ba' or flag == '--buyalliflessthan' then i = i + 1; opts.buyAllIfLessThan  = tonumber(raw[i])
        elseif flag == '-c' or flag == '--count'            then i = i + 1; opts.count            = tonumber(raw[i])
        elseif flag == '-s' or flag == '--savequery'        then opts.saveQuery    = true
        elseif flag == '-rm' or flag == '--removequery'      then opts.removeQuery  = true
        elseif flag == '-l' or flag == '--loosematch'       then opts.looseMatch   = true
        elseif flag == '-q' or flag == '--queries'          then opts.listQueries  = true
        elseif flag == '-rq' or flag == '--runquery'         then opts.runQuery     = true
        elseif flag == '-ra' or flag == '--runall'           then opts.runAll       = true
        elseif flag == '-h' or flag == '--help'             then opts.help         = true; if raw[i+1] == 'f' then opts.showFlags = true else opts.showFlags = false end
        else   nameWords[#nameWords + 1] = raw[i]
        end

        i = i + 1
    end

    -- Remaining non-flag tokens form the item name
    opts.itemName = #nameWords > 0 and table.concat(nameWords, ' ') or nil
    return opts
end

--- Register the /bzz bind against a Bazaar instance.
---@param bazaar BazaarUtility
function Binds.setup(bazaar)
    mq.bind('/bzz', function(...)
        local opts = parseArgs(...)

        -----------------------------------------------------------------
        -- Commands that don't need an item name
        -----------------------------------------------------------------
        if opts.help        then showHelp(opts.showFlags);                return end
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
            bazaar:buyAllIfLessThan(opts.itemName, opts.buyAllIfLessThan, opts.filters, opts.looseMatch, opts.count)
            return
        end

        if opts.buyIfLessThan then
            bazaar:buyIfLessThan(opts.itemName, opts.buyIfLessThan, opts.filters, opts.looseMatch, opts.count)
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
