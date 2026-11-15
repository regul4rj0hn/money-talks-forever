-- Money Talks Forever: saved data and settings.
--
-- MoneyTalksForeverDB = {
--   settings = { ... },                              see DEFAULTS
--   chars    = { [charKey] = { recipes = { [recipeID] = recipe } } },   recorded by Scanner.lua
--   deposits = { [itemID] = { [duration] = per-unit deposit } },        measured at the AH
--   flips    = { [realm] = last vendor flips scan },
--   ledger   = { [charKey] = profit-so-far ledger },                    see Ledger.lua
-- }
local _, ns = ...

local DEFAULTS = {
  useVendorReagentPrice = true, -- reagent price = min(AH price, NPC vendor buy price known to Auctionator)
  craftReagents = true,         -- reagents you can craft yourself are priced at min(buy price, craft cost)
  includeSoulbound = false,     -- also evaluate Bind-on-Pickup / account-bound crafted items
  onlyShuffle = false,          -- crafts tab filter: only "Shuffle me!" rows
  minProfit = 1,                -- copper; vendor value - reagent cost must be >= this to be flagged
  flipMinProfit = 1,            -- copper; a listing must make at least this when vendored to count as a flip
  ahDuration = 1,               -- auction duration used for deposits: 1 = 12h, 2 = 24h, 3 = 48h
  chatAlert = true,             -- print summaries (scans, vendor and mailbox visits) to chat
  tab = "crafts",               -- last open tab
}

function ns.Settings()
  return MoneyTalksForeverDB.settings
end

function ns.CharKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- This character's recorded recipes and other per-character data.
function ns.CharStore()
  local chars = MoneyTalksForeverDB.chars
  local key = ns.CharKey()
  chars[key] = chars[key] or { recipes = {} }
  return chars[key]
end

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------
local function InitSavedData()
  MoneyTalksForeverDB = MoneyTalksForeverDB or {}
  local db = MoneyTalksForeverDB
  for _, key in ipairs({ "settings", "chars", "deposits", "flips", "ledger" }) do
    db[key] = db[key] or {}
  end
  for k, v in pairs(DEFAULTS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
end

ns.On("ADDON_LOADED", function(name)
  if name ~= ns.ADDON_NAME then return end
  InitSavedData()
end)

