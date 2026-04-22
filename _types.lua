---@meta

---@class BazUtilsItemType
---@field LastSeen MQString # Date the item was last seen in the bazaar
---@field Sellers MQInt # Number of sellers for this item
---@field CheapestPlat MQInt # Cheapest platinum price seen
---@field HasBuyRule MQBoolean # Whether item has an auto-buy rule configured

---@class TLO.BazUtils
---@field Item fun(name: string): BazUtilsItemType # Get tracking info for a specific item
---@field QueryCount MQInt # Number of saved queries
--- Methods (called as Lua functions):
---@field Search fun(itemName: string) # Search and print results to console
---@field BuyIfLessThan fun(maxPlat: number, itemName: string) | fun(maxPlat: number, count: number, itemName: string) # Buy listings under plat
---@field BuyAllIfLessThan fun(maxPlat: number, itemName: string) | fun(maxPlat: number, count: number, itemName: string) # Buy all listings under plat
---@field SaveQuery fun(itemName: string, buyIfLessThan?: number, buyAllIfLessThan?: number) # Save a tracking query
---@field RemoveQuery fun(itemName: string) # Remove a saved query
---@field RunQuery fun(itemName: string) # Run a saved query now
---@field RunAll fun() # Run all saved queries now
---@field ListQueries fun() # Print all saved queries to console

--- Extend the TLO class to include BazUtils
---@class TLO
---@field BazUtils TLO.BazUtils
