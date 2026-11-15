-- Tests: saved data setup on load
local T = ...
local Fire = T.Fire

T.Test("saved data: fresh start and defaults filled in", function()
  local function Load() Fire("ADDON_LOADED", "MoneyTalksForever") end
  local savedDB = MoneyTalksForeverDB

  -- No saved data: fresh start
  MoneyTalksForeverDB = nil
  Load()
  assert(type(MoneyTalksForeverDB.chars) == "table" and type(MoneyTalksForeverDB.ledger) == "table")
  assert(MoneyTalksForeverDB.settings.minProfit == 1)

  -- Existing data: kept, missing settings filled in
  MoneyTalksForeverDB = { chars = { ["Mine-Realm"] = { recipes = {} } }, settings = { minProfit = 50 } }
  Load()
  assert(MoneyTalksForeverDB.chars["Mine-Realm"], "chars kept")
  assert(MoneyTalksForeverDB.settings.minProfit == 50, "settings kept")
  assert(MoneyTalksForeverDB.settings.flipMinProfit == 1, "new defaults filled in")

  MoneyTalksForeverDB = savedDB
end)
