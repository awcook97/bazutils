# BazUtils

A MacroQuest Lua script that automates EverQuest Bazaar searching, price tracking, and purchasing.

## Features

- **Search** the Bazaar with optional filters (class, slot, stat, race, type)
- **Buy** the cheapest listing or all listings under a platinum cap
- **Save queries** to track prices over time
- **Auto-buy** — saved queries with buy rules re-run automatically every hour
- **`${BazUtils}` TLO** — exposes tracking data to macros and other scripts

## Installation

Place the `bazutils` folder in your MacroQuest `lua/` directory, then run:

```
/lua run bazutils
```

## Command Reference

All commands use the `/bzz` bind.

```
/bzz --help
```

| Command | Description |
|---|---|
| `/bzz "Item Name"` | Search the Bazaar and print results |
| `/bzz --class WAR --slot Arms --stat HP "Item"` | Filtered search |
| `/bzz --buyIfLessThan <plat> "Item"` | Buy the cheapest exact match under `<plat>` |
| `/bzz --buyAllIfLessThan <plat> "Item"` | Buy **all** exact matches under `<plat>` |
| `/bzz --looseMatch --buyIfLessThan <plat> "Item"` | Same, but substring match instead of exact |
| `/bzz --savequery "Item"` | Save query and record current prices |
| `/bzz --savequery --buyAllIfLessThan <plat> "Item"` | Save auto-buy query (re-runs hourly) |
| `/bzz --removequery "Item"` | Remove a saved query |
| `/bzz --queries` | List all saved queries |
| `/bzz --runquery "Item"` | Run a saved query immediately |
| `/bzz --runall` | Run all saved queries immediately |

### Filters

`--class`, `--slot`, `--stat`, `--race`, `--type` — match the display text in the Bazaar UI comboboxes.

## TLO: `${BazUtils}`

| Expression | Type | Description |
|---|---|---|
| `${BazUtils.QueryCount}` | int | Number of saved queries |
| `${BazUtils.Item[Name].LastSeen}` | string | Timestamp of last price check |
| `${BazUtils.Item[Name].Sellers}` | int | Number of sellers seen |
| `${BazUtils.Item[Name].CheapestPlat}` | int | Cheapest price in platinum |
| `${BazUtils.Item[Name].HasBuyRule}` | bool | Whether an auto-buy rule is saved |

## Persistence

Tracking data is saved per-server to:

```
<MQ Config Dir>/bazUtils/<ServerName>_itemtracking.lua
```

## Dependencies

- [`lg-logger`](https://github.com/lawlgames/lg-logger) (`lib.lawlgames.lg-logger`)
- [`lg-fs`](https://github.com/lawlgames/lg-fs) (`lib.lawlgames.lg-fs`)
