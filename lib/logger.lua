--- Logger shim for BazUtils.
--- Adapts Write.lua (public) to the lg-logger interface used internally:
---   logger.Info(module, message, ...)
---   logger.Warn(module, message, ...)
---   logger.Error(module, message, ...)

local Write = require('bazutils.lib.Write')

local logger = {}

local function wrap(fn)
    return function(module, message, ...)
        fn(string.format('[%s] %s', module, string.format(message, ...)))
    end
end

logger.Trace = wrap(Write.Debug)
logger.Debug = wrap(Write.Debug)
logger.Info  = wrap(Write.Info)
logger.Warn  = wrap(Write.Warn)
logger.Error = wrap(Write.Error)
logger.Fatal = wrap(Write.Fatal)

return logger
