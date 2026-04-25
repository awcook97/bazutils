# BazUtils

A MacroQuest Lua script that automates EverQuest Bazaar searching, price tracking, and purchasing.

## Features

- **Search** the Bazaar with optional filters (class, slot, stat, race, type)
- **Buy** the cheapest listing or all listings under a platinum cap
- **Save queries** to track prices over time
- **Auto-buy** — saved queries with buy rules re-run automatically every hour
- **`${BazUtils}` TLO** — exposes tracking data and all commands to macros and other scripts

## File Structure

| File | Purpose |
|---|---|
| `init.lua` | Entry point — main loop, wires everything together |
| `bazaar.lua` | `Bazaar` class — all window interaction, search, buy, query logic |
| `data.lua` | Persistence — `data.load()` / `data.save()` for tracking file |
| `tlo.lua` | `${BazUtils}` TLO registration and DataType definitions |
| `binds.lua` | `/bzz` slash command parsing and dispatch |
| `_types.lua` | LuaLS `---@meta` annotations for IDE support |

## Installation

Place the `bazutils` folder in your MacroQuest `lua/` directory, then run:

```
/lua run bazutils
```

## Slash Commands

All commands use the `/bzz` bind.

```
/bzz --help
```

| Command | Description |
|---|---|
| `/bzz "Item Name"` | Search the Bazaar and print results |
| `/bzz --class WAR --slot Arms --stat HP "Item"` | Filtered search |
| `/bzz --buyIfLessThan <plat> "Item"` | Buy the cheapest exact match under `<plat>` |
| `/bzz --buyIfLessThan <plat> --count <n> "Item"` | Buy up to `<n>` listings under `<plat>` |
| `/bzz --buyAllIfLessThan <plat> "Item"` | Buy **all** exact matches under `<plat>` |
| `/bzz --buyAllIfLessThan <plat> --count <n> "Item"` | Buy all, capped at `<n>` listings |
| `/bzz --looseMatch --buyIfLessThan <plat> "Item"` | Same, but substring match instead of exact |
| `/bzz --savequery "Item"` | Save query and record current prices |
| `/bzz --savequery --buyIfLessThan <plat> "Item"` | Save auto-buy query (cheapest, re-runs hourly) |
| `/bzz --savequery --buyAllIfLessThan <plat> "Item"` | Save auto-buy query (all, re-runs hourly) |
| `/bzz --removequery "Item"` | Remove a saved query |
| `/bzz --queries` | List all saved queries |
| `/bzz --runquery "Item"` | Run a saved query immediately |
| `/bzz --runall` | Run all saved queries immediately |

### Filters

`--class`, `--slot`, `--stat`, `--race`, `--type` — match the display text in the Bazaar UI comboboxes.

### Flags & Short-hand (Should be self explanatory)

`-cl  | --class`
`-i   | --slot`
`-st  | --stat`
`-r   | --race`
`-t   | --type`
`-b   | --buyiflessthan`
`-ba  | --buyalliflessthan`
`-c   | --count`
`-s   | --savequery`
`-rm  | --removequery`
`-l   | --loosematch`
`-q   | --queries`
`-rq  | --runquery`
`-ra  | --runall`
`-h   | --help`

## TLO: `${BazUtils}`

All TLO members that trigger Bazaar window interaction (search, buy, save, run) are **asynchronous** — they enqueue the work and return `true` immediately. The operation executes on the next main-loop tick.

### Item data

| Expression | Type | Description |
|---|---|---|
| `${BazUtils.QueryCount}` | int | Number of saved queries |
| `${BazUtils.Item[Name].LastSeen}` | string | Timestamp of last price check |
| `${BazUtils.Item[Name].Sellers}` | int | Number of sellers seen |
| `${BazUtils.Item[Name].CheapestPlat}` | int | Cheapest price in platinum |
| `${BazUtils.Item[Name].HasBuyRule}` | bool | Whether an auto-buy rule is saved |

### Commands

| Expression | Type | Description |
|---|---|---|
| `${BazUtils.Search[Item Name]}` | bool | Search and print results to console |
| `${BazUtils.BuyIfLessThan[plat\|Item Name]}` | bool | Buy cheapest match under plat |
| `${BazUtils.BuyIfLessThan[plat\|count\|Item Name]}` | bool | Buy up to `count` listings under plat |
| `${BazUtils.BuyAllIfLessThan[plat\|Item Name]}` | bool | Buy all matches under plat |
| `${BazUtils.BuyAllIfLessThan[plat\|count\|Item Name]}` | bool | Buy all, capped at `count` listings |
| `${BazUtils.SaveQuery[Item Name]}` | bool | Save tracking query (no buy rule) |
| `${BazUtils.SaveQueryBuy[plat\|Item Name]}` | bool | Save query with `buyIfLessThan` rule |
| `${BazUtils.SaveQueryBuyAll[plat\|Item Name]}` | bool | Save query with `buyAllIfLessThan` rule |
| `${BazUtils.RemoveQuery[Item Name]}` | bool | Remove a saved query |
| `${BazUtils.RunQuery[Item Name]}` | bool | Run a saved query now |
| `${BazUtils.RunAll}` | bool | Run all saved queries now |
| `${BazUtils.ListQueries}` | bool | Print all saved queries to console |

For members that take both a plat cap and an item name, the index format is `plat|Item Name`, e.g.:

```
${BazUtils.BuyIfLessThan[500|Water Flask]}
${BazUtils.BuyIfLessThan[500|6|Water Flask]}
${BazUtils.BuyAllIfLessThan[100|Cloth Cap]}
${BazUtils.SaveQueryBuyAll[100|Cloth Cap]}
```

## Persistence

Tracking data is saved per-server to:

```
<MQ Config Dir>/bazUtils/<ServerName>_itemtracking.lua
```

## Dependencies

- [`lg-logger`](https://github.com/lawlgames/lg-logger) (`lib.lawlgames.lg-logger`)
- [`lg-fs`](https://github.com/lawlgames/lg-fs) (`lib.lawlgames.lg-fs`)
