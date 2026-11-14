-- Money Talks Forever: slash commands (/mtf, and /shuffle from the CraftShuffler days) and the debug dump.
local _, ns = ...

local function Toggle(key, label)
  return function()
    local s = ns.Settings()
    s[key] = not s[key]
    ns.Print(label .. " " .. ns.OnOff(s[key]))
    ns.Evaluate()
  end
end

local function SetGold(key, command, label, example, after)
  return function(arg)
    local copper = ns.ParseGold(arg)
    if not copper then
      ns.Print(("usage: /mtf %s <gold>  (e.g. %s)"):format(command, example))
      return
    end
    ns.Settings()[key] = copper
    ns.Print(label .. " set to " .. ns.Money(copper) .. (after or ""))
    ns.Evaluate()
  end
end

local function PrintShuffleList()
  ns.Evaluate()
  local n = 0
  for _, r in ipairs(ns.results) do
    if r.status == ns.STATUS.SHUFFLE then
      n = n + 1
      print(("  %s x%d  cost %s  vendor %s  %s%s"):format(
        r.itemLink or r.name, r.qty, ns.Money(r.cost), ns.Money(r.vendorValue),
        ns.Colorize("+" .. ns.Money(r.profit), ns.COLOR.GREEN),
        r.usesCrafting and ("  " .. ns.Colorize("(buy + craft)", ns.COLOR.BLUE)) or ""))
    end
  end
  ns.Print(n .. " item(s) flagged 'Shuffle me!'")
end

-- Diagnostic dump for troubleshooting (no personal data).
function ns.PrintDebug()
  local AH, api, f = C_AuctionHouse, ns.AuctionatorAPI(), ns.flips or {}
  local replicateSetting = "?"
  if Auctionator and Auctionator.Config and Auctionator.Config.Get and Auctionator.Config.Options then
    local ok, v = pcall(Auctionator.Config.Get, Auctionator.Config.Options.REPLICATE_SCAN)
    if ok then replicateSetting = tostring(v) end
  end
  local L = ns.Ledger()
  ns.Print("debug, version " .. ns.VERSION)
  print(("  Auctionator API: %s, DB update hook: %s, full-scan mode ('alternate scan mode' option): %s"):format(
    tostring(api ~= nil), tostring(api ~= nil and api.RegisterForDBUpdate ~= nil), replicateSetting))
  print(("  AH open: %s, replicate listings available: %s"):format(
    tostring(ns.ahOpen), tostring(AH and AH.GetNumReplicateItems and AH.GetNumReplicateItems() or "n/a")))
  print(("  full scan pending: %s, flip scan running: %s, last update was incremental: %s"):format(
    tostring(ns.fullScanPending == true), tostring(ns.flipScanRunning == true), tostring(ns.lastScanIncremental == true)))
  print(("  last flips scan: %s, %d listings read, %d flips, %d skipped"):format(
    f.scannedAt and (math.floor((time() - f.scannedAt) / 60) .. " min ago") or "never",
    f.listings or 0, f.items and #f.items or 0, f.skipped or 0))
  print(("  recipes recorded: %d, evaluated rows: %d"):format(ns.CountKeys(ns.CharStore().recipes), #ns.results))
  print(("  ledger: %d bought and %d crafted item types in stock, %d item types sold, all-time profit %s"):format(
    ns.CountKeys(L.bought), ns.CountKeys(L.crafted), ns.CountKeys(L.items), ns.Money(ns.BucketProfit(L.all))))
end

-- In the order shown by /mtf help. `usage` is what follows /mtf; `help` may be a function for live values.
local COMMANDS = {
  { name = "", help = "toggle the window", run = function() ns.ToggleUI() end },
  { name = "list", help = "print all 'Shuffle me!' items to chat", run = PrintShuffleList },
  { name = "shop", help = "create an Auctionator shopping list of reagents with max prices",
    run = function() ns.CreateReagentShoppingList() end },
  { name = "flips", help = "show AH listings cheaper than their vendor price",
    run = function()
      ns.ShowTab("flips")
      if not ns.ScanReplicateForFlips(true) and not ns.flips.scannedAt then
        ns.Print("no full scan data yet - at the AH, click Full scan on the Vendor flips tab.")
      end
    end },
  { name = "fullscan", help = "full AH scan for vendor flips (at the AH, once per 15 min)",
    run = function() ns.ShowTab("flips"); ns.StartFullScan() end },
  { name = "profit", usage = "profit [reset]", help = "show what you've made; 'reset' clears this character's history",
    run = function(arg)
      if arg == "reset" then
        StaticPopup_Show("MONEYTALKSFOREVER_RESET_LEDGER")
        return
      end
      ns.ShowTab("profit")
      ns.Print(("profit this session %s, all time %s"):format(
        ns.ProfitMoney(ns.BucketProfit(ns.session)), ns.ProfitMoney(ns.BucketProfit(ns.Ledger().all))))
    end },
  { name = "vendor", help = function(s) return "use NPC vendor prices for reagents (" .. ns.OnOff(s.useVendorReagentPrice) .. ")" end,
    run = Toggle("useVendorReagentPrice", "vendor reagent prices") },
  { name = "craft", help = function(s) return "price reagents at their own craft cost when cheaper (" .. ns.OnOff(s.craftReagents) .. ")" end,
    run = Toggle("craftReagents", "craft-your-own reagents") },
  { name = "soulbound", help = function(s) return "include soulbound crafts (" .. ns.OnOff(s.includeSoulbound) .. ")" end,
    run = Toggle("includeSoulbound", "include soulbound crafts") },
  { name = "minprofit", usage = "minprofit <gold>",
    help = function(s) return "minimum profit per craft, e.g. 0.5 = 50s (now " .. ns.Money(s.minProfit) .. ")" end,
    run = SetGold("minProfit", "minprofit", "minimum profit", "0.05 = 5 silver") },
  { name = "flipmin", usage = "flipmin <gold>",
    help = function(s) return "minimum profit per flip listing (now " .. ns.Money(s.flipMinProfit) .. ")" end,
    run = SetGold("flipMinProfit", "flipmin", "minimum flip profit", "0.01 = 1 silver", " (applies from the next scan)") },
  { name = "duration", usage = "duration 12|24|48",
    help = function(s) return "auction duration for deposits (now " .. ns.DURATION_HOURS[s.ahDuration] .. "h)" end,
    run = function(arg)
      local index = ({ ["12"] = 1, ["24"] = 2, ["48"] = 3 })[arg]
      if not index then
        ns.Print("usage: /mtf duration 12|24|48")
        return
      end
      ns.Settings().ahDuration = index
      ns.Print("auction duration set to " .. arg .. "h")
      ns.CaptureDeposits()
      ns.Evaluate()
    end },
  { name = "reset", help = "forget this character's recorded recipes",
    run = function()
      ns.CharStore().recipes = {}
      ns.Print("recorded recipes cleared for this character")
      ns.Evaluate()
    end },
  { name = "debug", help = "print diagnostic info", run = function() ns.PrintDebug() end },
}

local byName = {}
for _, c in ipairs(COMMANDS) do byName[c.name] = c end

local function PrintHelp()
  local s = ns.Settings()
  ns.Print("commands:")
  for _, c in ipairs(COMMANDS) do
    local help = type(c.help) == "function" and c.help(s) or c.help
    print(("  /mtf%s - %s"):format(c.name == "" and "" or (" " .. (c.usage or c.name)), help))
  end
  print("Open each profession window once so its recipes are recorded.")
end

SLASH_MONEYTALKSFOREVER1 = "/mtf"
SLASH_MONEYTALKSFOREVER2 = "/shuffle" -- the old CraftShuffler command keeps working
SlashCmdList.MONEYTALKSFOREVER = function(msg)
  local name, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
  local command = byName[name]
  if command then command.run(arg) else PrintHelp() end
end
