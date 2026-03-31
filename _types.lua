---@meta

---@class BazUtilsItemType
---@field LastSeen MQString # Date the item was last seen in the bazaar
---@field Sellers MQInt # Number of sellers for this item
---@field CheapestPlat MQInt # Cheapest platinum price seen
---@field HasBuyRule MQBoolean # Whether item has an auto-buy rule configured

---@class TLO.BazUtils
---@field Item fun(name: string): BazUtilsItemType # Get tracking info for a specific item
---@field QueryCount MQInt # Number of saved queries
---@field Search fun(name: string): MQBoolean # Search and print results to console
---@field BuyIfLessThan fun(platPipeName: string): MQBoolean # Buy cheapest match; index = "maxPlat|Item Name"
---@field BuyAllIfLessThan fun(platPipeName: string): MQInt # Buy all matches; index = "maxPlat|Item Name"
---@field SaveQuery fun(name: string): MQBoolean # Save tracking query (no buy rule)
---@field SaveQueryBuy fun(platPipeName: string): MQBoolean # Save query with buyIfLessThan rule; index = "maxPlat|Item Name"
---@field SaveQueryBuyAll fun(platPipeName: string): MQBoolean # Save query with buyAllIfLessThan rule; index = "maxPlat|Item Name"
---@field RemoveQuery fun(name: string): MQBoolean # Remove a saved query
---@field RunQuery fun(name: string): MQBoolean # Run a saved query now
---@field RunAll MQBoolean # Run all saved queries now
---@field ListQueries MQBoolean # Print all saved queries to console

--- Extend the TLO class to include BazUtils
---@class TLO
---@field BazUtils TLO.BazUtils
