-- Money Talks Forever: core (saved variables, events, slash commands)
local ADDON_NAME, ns = ...

ns.CALLER_ID = "MoneyTalksForever"
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (GetMeta and GetMeta(ADDON_NAME, "Version")) or "?"
ns.results = {}          -- evaluated recipe rows (see Pricing.lua)
ns.flaggedByItem = {}    -- [outputItemID] = result row, only for "Shuffle me!" items

local DEFAULTS = {
  useVendorReagentPrice = true, -- reagent price = min(AH price, NPC vendor buy price known to Auctionator)
  craftReagents = true,         -- reagents you can craft yourself are priced at min(buy price, craft cost)
  includeSoulbound = false,     -- also evaluate Bind-on-Pickup / account-bound crafted items
  onlyShuffle = false,          -- UI filter: show only "Shuffle me!" rows
  minProfit = 1,                -- copper; vendor value - reagent cost must be >= this to be flagged
  flipMinProfit = 1,            -- copper; a listing must make at least this when vendored to count as a flip
  ahDuration = 1,               -- auction duration used for deposits: 1 = 12h, 2 = 24h, 3 = 48h
  chatAlert = true,             -- print a summary after each Auctionator scan
}

local function Print(...)
  print("|cff33ff99Money Talks|r:", ...)
end
ns.Print = Print

function ns.CharKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Per-character storage of known recipes: MoneyTalksForeverDB.chars[charKey].recipes[recipeID]
function ns.CharStore()
  local key = ns.CharKey()
  MoneyTalksForeverDB.chars[key] = MoneyTalksForeverDB.chars[key] or { recipes = {} }
  return MoneyTalksForeverDB.chars[key]
end

function ns.Settings()
  return MoneyTalksForeverDB.settings
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
      -- After a full scan the game still holds every listing; look for ones below vendor price.
      if ns.ahOpen then
        C_Timer.After(1, function()
          if not ns.ScanReplicateForFlips() then
            -- Prices were updated by an incremental scan, which has no individual listings.
            ns.lastScanIncremental = true
            if ns.RefreshUI then ns.RefreshUI() end
          end
        end)
      end
    end)
    if not ok then Print("Could not register for Auctionator updates:", tostring(err)) end
  end
end

-- One-time import from the addon's previous name, CraftShuffler. Its saved variables only exist if that addon is
-- still installed and enabled (OptionalDeps makes it load first). Only imports when we have no data of our own.
local OLD_ADDON = "CraftShuffler"
local function MigrateFromOldName()
  local old = CraftShufflerDB
  if type(old) ~= "table" then return false end
  local db = MoneyTalksForeverDB
  if db and (db.migratedFrom or (db.chars and next(db.chars))) then return false end
  MoneyTalksForeverDB = old
  old.migratedFrom = OLD_ADDON
  return true
end

local function DisableOldAddon()
  local disable = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
  if disable then pcall(disable, OLD_ADDON) end
end

frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    ns.migrated = MigrateFromOldName()
    MoneyTalksForeverDB = MoneyTalksForeverDB or {}
    MoneyTalksForeverDB.chars = MoneyTalksForeverDB.chars or {}
    MoneyTalksForeverDB.settings = MoneyTalksForeverDB.settings or {}
    MoneyTalksForeverDB.deposits = MoneyTalksForeverDB.deposits or {}   -- [itemID][duration] = per-unit deposit
    MoneyTalksForeverDB.flips = MoneyTalksForeverDB.flips or {}         -- [realm] = last vendor flips scan
    MoneyTalksForeverDB.ledger = MoneyTalksForeverDB.ledger or {}       -- [charKey] = profit-so-far ledger
    for k, v in pairs(DEFAULTS) do
      if MoneyTalksForeverDB.settings[k] == nil then MoneyTalksForeverDB.settings[k] = v end
    end
  elseif event == "PLAYER_LOGIN" then
    if ns.migrated then
      DisableOldAddon()
      Print("imported your CraftShuffler data (recipes, deposits, flips, profit history). CraftShuffler is now "
        .. "disabled: /reload, then you can delete its folder from Interface/AddOns.")
    end
    RegisterAuctionatorCallback()
    ns.InstallTooltipHook()
    ns.LoadSavedFlips()
    ns.RequestEvaluate(3)
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE"
      or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    ns.RequestScan()
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if ns.waitingForItems then ns.RequestEvaluate(1) end
  end
end)

-- Diagnostic dump for troubleshooting (no personal data).
function ns.PrintDebug()
  local AH = C_AuctionHouse
  local api = ns.AuctionatorAPI()
  local replicateSetting = "?"
  if Auctionator and Auctionator.Config and Auctionator.Config.Get and Auctionator.Config.Options then
    local ok, v = pcall(Auctionator.Config.Get, Auctionator.Config.Options.REPLICATE_SCAN)
    if ok then replicateSetting = tostring(v) end
  end
  local f = ns.flips or {}
  Print("debug, version " .. ns.VERSION)
  print("  Auctionator API: " .. tostring(api ~= nil) .. ", DB update hook: " .. tostring(api and api.RegisterForDBUpdate ~= nil))
  print("  Auctionator full-scan mode ('alternate scan mode' option): " .. replicateSetting)
  print("  AH open: " .. tostring(ns.ahOpen == true) .. ", replicate listings available: "
    .. tostring(AH and AH.GetNumReplicateItems and AH.GetNumReplicateItems() or "n/a"))
  print("  full scan pending: " .. tostring(ns.fullScanPending == true) .. ", flip scan running: "
    .. tostring(ns.flipScanRunning == true) .. ", last update was incremental: " .. tostring(ns.lastScanIncremental == true))
  print(("  last flips scan: %s, %d listings read, %d flips, %d skipped"):format(
    f.scannedAt and (math.floor((time() - f.scannedAt) / 60) .. " min ago") or "never",
    f.listings or 0, f.items and #f.items or 0, f.skipped or 0))
  local recipes = 0
  for _ in pairs(ns.CharStore().recipes) do recipes = recipes + 1 end
  print(("  recipes recorded: %d, evaluated rows: %d"):format(recipes, #ns.results))
  local L = ns.Ledger()
  local bought, crafted, sold = 0, 0, 0
  for _ in pairs(L.bought) do bought = bought + 1 end
  for _ in pairs(L.crafted) do crafted = crafted + 1 end
  for _ in pairs(L.items) do sold = sold + 1 end
  print(("  ledger: %d bought and %d crafted item types in stock, %d item types sold, all-time profit %s"):format(
    bought, crafted, sold, ns.Money(ns.BucketProfit(L.all))))
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function OnOff(v)
  return v and "|cff00ff00on|r" or "|cffff0000off|r"
end

local function Help()
  local s = ns.Settings()
  Print("commands:")
  print("  /mtf - toggle the window")
  print("  /mtf list - print all 'Shuffle me!' items to chat")
  print("  /mtf vendor - toggle using NPC vendor reagent prices (" .. OnOff(s.useVendorReagentPrice) .. ")")
  print("  /mtf craft - toggle pricing reagents at their own craft cost when cheaper (" .. OnOff(s.craftReagents) .. ")")
  print("  /mtf soulbound - toggle including soulbound crafts (" .. OnOff(s.includeSoulbound) .. ")")
  print("  /mtf minprofit <gold> - minimum profit per craft, e.g. 0.5 = 50s (now " .. ns.Money(s.minProfit) .. ")")
  print("  /mtf shop - create an Auctionator shopping list of reagents with max prices")
  print("  /mtf flips - show AH listings cheaper than their vendor price (needs a full Auctionator scan)")
  print("  /mtf flipmin <gold> - minimum profit per flip listing (now " .. ns.Money(s.flipMinProfit) .. ")")
  print("  /mtf profit - show what you've made (crafts and flips sold to vendors)")
  print("  /mtf profit reset - clear this character's profit history")
  print("  /mtf fullscan - full AH scan for vendor flips (at the AH, once per 15 min)")
  print("  /mtf debug - print diagnostic info")
  print("  /mtf duration 12|24|48 - auction duration for deposits (now " .. ns.DURATION_HOURS[s.ahDuration] .. "h)")
  print("  /mtf reset - forget this character's stored recipes")
  print("Open each profession window once so its recipes are recorded.")
end

SLASH_MONEYTALKSFOREVER1 = "/mtf"
SLASH_MONEYTALKSFOREVER2 = "/shuffle" -- the old command keeps working
SlashCmdList.MONEYTALKSFOREVER = function(msg)
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
      Print("usage: /mtf minprofit <gold>  (e.g. 0.05 = 5 silver)")
    else
      s.minProfit = math.max(1, math.floor(gold * 10000 + 0.5))
      Print("minimum profit set to " .. ns.Money(s.minProfit))
      ns.Evaluate()
    end
  elseif cmd == "shop" then
    ns.CreateShoppingList()
  elseif cmd == "flips" then
    ns.ShowTab("flips")
    if not ns.ScanReplicateForFlips(true) and not ns.flips.scannedAt then
      Print("no full scan data yet - at the AH, run a full scan in Auctionator's Auctionator tab.")
    end
  elseif cmd == "profit" then
    if rest == "reset" then
      StaticPopup_Show("MONEYTALKSFOREVER_RESET_LEDGER")
    else
      ns.ShowTab("profit")
      local b, L = ns.session, ns.Ledger()
      Print(("profit this session %s, all time %s"):format(ns.Money(ns.BucketProfit(b)), ns.Money(ns.BucketProfit(L.all))))
    end
  elseif cmd == "fullscan" then
    ns.ShowTab("flips")
    ns.StartFullScan()
  elseif cmd == "debug" then
    ns.PrintDebug()
  elseif cmd == "flipmin" then
    local gold = tonumber(rest)
    if not gold or gold < 0 then
      Print("usage: /mtf flipmin <gold>  (e.g. 0.01 = 1 silver)")
    else
      s.flipMinProfit = math.max(1, math.floor(gold * 10000 + 0.5))
      Print("minimum flip profit set to " .. ns.Money(s.flipMinProfit) .. " (applies from the next scan)")
    end
  elseif cmd == "duration" then
    local idx = ({ ["12"] = 1, ["24"] = 2, ["48"] = 3 })[rest]
    if not idx then
      Print("usage: /mtf duration 12|24|48")
    else
      s.ahDuration = idx
      Print("auction duration set to " .. rest .. "h")
      ns.CaptureDeposits()
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
