-- CraftShuffler: core (saved variables, events, slash commands)
local ADDON_NAME, ns = ...

ns.CALLER_ID = "CraftShuffler"
ns.results = {}          -- evaluated recipe rows (see Pricing.lua)
ns.flaggedByItem = {}    -- [outputItemID] = result row, only for "Shuffle me!" items

local DEFAULTS = {
  useVendorReagentPrice = true, -- reagent price = min(AH price, NPC vendor buy price known to Auctionator)
  craftReagents = true,         -- reagents you can craft yourself are priced at min(buy price, craft cost)
  includeSoulbound = false,     -- also evaluate Bind-on-Pickup / account-bound crafted items
  onlyShuffle = false,          -- UI filter: show only "Shuffle me!" rows
  minProfit = 1,                -- copper; vendor value - reagent cost must be >= this to be flagged
  chatAlert = true,             -- print a summary after each Auctionator scan
}

local function Print(...)
  print("|cff33ff99CraftShuffler|r:", ...)
end
ns.Print = Print

function ns.CharKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Per-character storage of known recipes: CraftShufflerDB.chars[charKey].recipes[recipeID]
function ns.CharStore()
  local key = ns.CharKey()
  CraftShufflerDB.chars[key] = CraftShufflerDB.chars[key] or { recipes = {} }
  return CraftShufflerDB.chars[key]
end

function ns.Settings()
  return CraftShufflerDB.settings
end

-- Debounced re-evaluation so bursts of events (item cache, scans) only trigger one pass.
local evalPending = false
function ns.RequestEvaluate(delay)
  if evalPending then return end
  evalPending = true
  C_Timer.After(delay or 0.5, function()
    evalPending = false
    ns.Evaluate()
  end)
end

local frame = CreateFrame("Frame")
ns.eventFrame = frame

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
frame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

local function RegisterAuctionatorCallback()
  local api = ns.AuctionatorAPI()
  if not api then
    Print("Auctionator not found - reagent prices are unavailable. Install/enable Auctionator and do a full scan.")
    return
  end
  if api.RegisterForDBUpdate then
    local ok, err = pcall(api.RegisterForDBUpdate, ns.CALLER_ID, function()
      ns.announceNextEval = true
      ns.RequestEvaluate(1)
    end)
    if not ok then Print("Could not register for Auctionator updates:", tostring(err)) end
  end
end

frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    CraftShufflerDB = CraftShufflerDB or {}
    CraftShufflerDB.chars = CraftShufflerDB.chars or {}
    CraftShufflerDB.settings = CraftShufflerDB.settings or {}
    for k, v in pairs(DEFAULTS) do
      if CraftShufflerDB.settings[k] == nil then CraftShufflerDB.settings[k] = v end
    end
  elseif event == "PLAYER_LOGIN" then
    RegisterAuctionatorCallback()
    ns.InstallTooltipHook()
    ns.RequestEvaluate(3)
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE"
      or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    ns.RequestScan()
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if ns.waitingForItems then ns.RequestEvaluate(1) end
  end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function OnOff(v)
  return v and "|cff00ff00on|r" or "|cffff0000off|r"
end

local function Help()
  local s = ns.Settings()
  Print("commands:")
  print("  /shuffle - toggle the window")
  print("  /shuffle list - print all 'Shuffle me!' items to chat")
  print("  /shuffle vendor - toggle using NPC vendor reagent prices (" .. OnOff(s.useVendorReagentPrice) .. ")")
  print("  /shuffle craft - toggle pricing reagents at their own craft cost when cheaper (" .. OnOff(s.craftReagents) .. ")")
  print("  /shuffle soulbound - toggle including soulbound crafts (" .. OnOff(s.includeSoulbound) .. ")")
  print("  /shuffle minprofit <gold> - minimum profit per craft, e.g. 0.5 = 50s (now " .. ns.Money(s.minProfit) .. ")")
  print("  /shuffle reset - forget this character's stored recipes")
  print("Open each profession window once so its recipes are recorded.")
end

SLASH_CRAFTSHUFFLER1 = "/shuffle"
SLASH_CRAFTSHUFFLER2 = "/craftshuffler"
SlashCmdList.CRAFTSHUFFLER = function(msg)
  local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  local s = ns.Settings()
  if cmd == "" then
    ns.ToggleUI()
  elseif cmd == "help" then
    Help()
  elseif cmd == "list" then
    ns.Evaluate()
    local n = 0
    for _, r in ipairs(ns.results) do
      if r.status == ns.STATUS.SHUFFLE then
        n = n + 1
        print(("  %s x%d  cost %s  vendor %s  |cff00ff00+%s|r%s"):format(
          r.itemLink or r.name, r.qty, ns.Money(r.cost), ns.Money(r.vendorValue), ns.Money(r.profit),
          r.usesCrafting and "  |cff66ccff(buy + craft)|r" or ""))
      end
    end
    Print(n .. " item(s) flagged 'Shuffle me!'")
  elseif cmd == "vendor" then
    s.useVendorReagentPrice = not s.useVendorReagentPrice
    Print("vendor reagent prices " .. OnOff(s.useVendorReagentPrice))
    ns.Evaluate()
  elseif cmd == "craft" then
    s.craftReagents = not s.craftReagents
    Print("craft-your-own reagents " .. OnOff(s.craftReagents))
    ns.Evaluate()
  elseif cmd == "soulbound" then
    s.includeSoulbound = not s.includeSoulbound
    Print("include soulbound crafts " .. OnOff(s.includeSoulbound))
    ns.Evaluate()
  elseif cmd == "minprofit" then
    local gold = tonumber(rest)
    if not gold or gold < 0 then
      Print("usage: /shuffle minprofit <gold>  (e.g. 0.05 = 5 silver)")
    else
      s.minProfit = math.max(1, math.floor(gold * 10000 + 0.5))
      Print("minimum profit set to " .. ns.Money(s.minProfit))
      ns.Evaluate()
    end
  elseif cmd == "reset" then
    ns.CharStore().recipes = {}
    Print("stored recipes cleared for " .. ns.CharKey())
    ns.Evaluate()
  else
    Help()
  end
end
