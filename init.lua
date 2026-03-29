local mq = require('mq')
local logger = require('lib.lawlgames.lg-logger')

local Bazaar = require('bazutils.bazaar')
local Binds  = require('bazutils.binds')

local MODULE_NAME = 'BazUtils'
local TICK_MS = 300
local SCHEDULE_CHECK_S = 60 -- how often (seconds) we check for due queries

local bazaar = Bazaar.new()
bazaar:registerTLO()
Binds.setup(bazaar)

local function main()
    logger.Info(MODULE_NAME, 'Loaded — /bzz --help for commands')

    local lastCheck = 0

    while mq.TLO.EverQuest.GameState() == 'INGAME' do
        mq.doevents()

        -- Periodically fire any saved auto-buy queries whose timer expired
        local now = os.time()
        if now - lastCheck >= SCHEDULE_CHECK_S then
            lastCheck = now
            bazaar:runDueQueries()
        end

        mq.delay(TICK_MS)
    end

    Binds.teardown()
    bazaar:unregisterTLO()
end

main()