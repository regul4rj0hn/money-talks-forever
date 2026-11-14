-- Tests: importing data from the old CraftShuffler name
local T = ...
local ns, W, Fire, flush = T.ns, T.W, T.Fire, T.flush
local Setup, ByName, LINEN = T.Setup, T.ByName, T.LINEN

T.Test("migrates CraftShuffler data once, only when there is none of our own", function()
  local function Load() Fire("ADDON_LOADED", "MoneyTalksForever") end
  local savedDB = MoneyTalksForeverDB

  -- Old data, no new data: imported
  CraftShufflerDB = { chars = { ["Tester-Realm"] = { recipes = { [1] = { name = "Bolt" } } } }, settings = { minProfit = 50 } }
  MoneyTalksForeverDB = nil
  Load()
  assert(MoneyTalksForeverDB.chars["Tester-Realm"].recipes[1].name == "Bolt" and ns.migrated)
  assert(MoneyTalksForeverDB.settings.minProfit == 50, "settings kept")
  assert(MoneyTalksForeverDB.settings.flipMinProfit == 1, "new defaults filled in")
  assert(MoneyTalksForeverDB.migratedFrom == "CraftShuffler")

  -- Already migrated: not imported again
  local db = MoneyTalksForeverDB
  CraftShufflerDB = { chars = { ["Other-Realm"] = { recipes = {} } } }
  Load()
  assert(MoneyTalksForeverDB == db and not ns.migrated)

  -- New addon already has its own data: kept
  MoneyTalksForeverDB = { chars = { ["Mine-Realm"] = { recipes = {} } } }
  Load()
  assert(MoneyTalksForeverDB.chars["Mine-Realm"] and not ns.migrated)

  -- No old addon: fresh start
  CraftShufflerDB, MoneyTalksForeverDB = nil, nil
  Load()
  assert(type(MoneyTalksForeverDB.chars) == "table" and not ns.migrated)

  CraftShufflerDB, MoneyTalksForeverDB = nil, savedDB
end)
