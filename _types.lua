---@meta

---@class BazUtilsItemType
---@field LastSeen MQString # Date the item was last seen in the bazaar
---@field Sellers MQInt # Number of sellers for this item
---@field CheapestPlat MQInt # Cheapest platinum price seen
---@field HasBuyRule MQBoolean # Whether item has an auto-buy rule configured

---@class TLO.BazUtils
---@field Item fun(name: string): BazUtilsItemType # Get tracking info for a specific item
---@field QueryCount MQInt # Number of saved queries

--- Extend the TLO class to include BazUtils
---@class TLO
---@field BazUtils TLO.BazUtils
