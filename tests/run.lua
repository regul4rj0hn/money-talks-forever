-- Offline tests for Money Talks Forever's scanning/pricing logic, using a mocked WoW API.
-- Run from the repo root:  lua tests/run.lua
local ADDON_DIR = "MoneyTalksForever"

---------------------------------------------------------------------------
-- WoW API mocks
---------------------------------------------------------------------------
local timers = {}
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
local function flush() while #timers > 0 do table.remove(timers, 1)() end end

-- Frames keep their scripts so tests can fire events: frame.scripts.OnEvent(frame, event, ...)
local frameMT = { __index = function(t, k)
  if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
  return function() end
end }
function CreateFrame() return setmetatable({ scripts = {} }, frameMT) end
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end
GetMoneyString = function(c) return c .. "c" end
SlashCmdList = {}
Enum = { ItemBind = { None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3 }, CraftingReagentType = { Basic = 1 } }

local items, ah, vendor, recipes -- per-scenario data, set by Setup()

C_Item = {
  GetItemInfo = function(id)
    local i = items[id]
    if not i then return nil end
    -- name, link, quality, ilvl, minLevel, type, subType, stack, equipLoc, icon, sellPrice, class, subclass, bindType
    return i[1], "[" .. i[1] .. "]", 1, 1, 1, "", "", 1, "", 1, i[2], 0, 0, i[3]
  end,
  RequestLoadItemDataByID = function() end,
  GetItemNameByID = function(id) return items[id] and items[id][1] end,
  GetItemID = function(location) return location.itemID end,
}
local createdLists = {}
time = os.time
GetTime = os.clock
date = os.date

-- Hooks: wrap the table function so the hook runs after it, like WoW's hooksecurefunc.
function hooksecurefunc(t, name, hook)
  local orig = t[name]
  t[name] = function(...) local r = orig(...); hook(...); return r end
end

local money = 0
GetMoney = function() return money end

-- Mailbox: { subject, money, invoice = {type, itemName, bid, deposit, consignment, count}, item = {name, id, count} }
local inbox = {}
GetInboxNumItems = function() return #inbox end
GetInboxHeaderInfo = function(i)
  local m = inbox[i]
  return nil, nil, "Auction House", m.subject, m.money or 0, 0, 30, m.item and 1 or nil
end
GetInboxInvoiceInfo = function(i)
  local v = inbox[i].invoice
  if not v then return nil end
  return v.type, v.itemName, nil, v.bid, v.bid, v.deposit, v.consignment, 0, 0, 0, v.count, true
end
GetInboxItem = function(i)
  local it = inbox[i].item
  if not it then return nil end
  return it.name, it.id, nil, it.count
end
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"

-- Bags: one bag holding { [itemID] = count }
local bag = {}
C_Container = {
  GetContainerNumSlots = function(b)
    if b ~= 0 then return 0 end
    local n = 0
    for _ in pairs(bag) do n = n + 1 end
    return n
  end,
  GetContainerItemInfo = function(b, slot)
    local ids = {}
    for id in pairs(bag) do ids[#ids + 1] = id end
    table.sort(ids)
    local id = ids[slot]
    return id and { itemID = id, stackCount = bag[id] } or nil
  end,
}

-- Replicate (full scan) listings: { itemID, count, buyout, owner }
local replicate = {}
local replicateRequests = 0
C_AuctionHouse = {
  ReplicateItems = function() replicateRequests = replicateRequests + 1 end,
  StartCommoditiesPurchase = function() end,
  ConfirmCommoditiesPurchase = function() end,
  PlaceBid = function() end,
  PostItem = function() return true end,
  PostCommodity = function() return true end,
  GetAuctionInfoByID = function(id) return auctionsByID and auctionsByID[id] end,
  GetNumReplicateItems = function() return #replicate end,
  GetReplicateItemInfo = function(i) -- 0-based, like the real API
    local l = replicate[i + 1]
    return "name", 1, l[2], 1, true, 1, 0, 0, 0, l[3], 0, false, nil, l[4], nil, 0, l[1], true
  end,
}
Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, id) return ah[id] end,
  GetVendorPriceByItemID = function(_, id) return vendor[id] end,
  -- Same shape as Auctionator's real search strings; maxPrice is stored in gold.
  ConvertToSearchString = function(_, t)
    return ('"%s";;;;;;;;%s;;;;'):format(t.searchString, t.maxPrice and tostring(t.maxPrice / 10000) or "")
  end,
  CreateShoppingList = function(_, name, strings) createdLists[name] = strings end,
} } }
C_TradeSkillUI = {
  IsTradeSkillReady = function() return true end,
  GetBaseProfessionInfo = function() return { professionName = "Tailoring" } end,
  GetAllRecipeIDs = function()
    local t = {}
    for id in pairs(recipes) do t[#t + 1] = id end
    table.sort(t)
    return t
  end,
  GetRecipeInfo = function(id) return { name = recipes[id].name, learned = true } end,
  GetRecipeSchematic = function(id)
    local r, slots = recipes[id], {}
    for _, g in ipairs(r.reagents) do
      table.insert(slots, { required = true, quantityRequired = g[2], reagents = { { itemID = g[1] } } })
    end
    return { outputItemID = r.out, quantityMin = r.qty or 1, quantityMax = r.qty or 1, reagentSlotSchematics = slots }
  end,
}

local ns = {}
for _, f in ipairs({ "Core.lua", "Pricing.lua", "AuctionHouse.lua", "Flips.lua", "Ledger.lua", "Mail.lua", "Scanner.lua" }) do
  assert(loadfile(ADDON_DIR .. "/" .. f))("MoneyTalksForever", ns)
end
print = function() end -- silence addon chat output

local function Setup(scenario)
  items, ah, vendor, recipes = scenario.items, scenario.ah, scenario.vendor or {}, scenario.recipes
  MoneyTalksForeverDB = { chars = {}, deposits = {}, flips = {}, ledger = {}, settings = {
    useVendorReagentPrice = true, craftReagents = true, includeSoulbound = false, minProfit = 1, ahDuration = 1,
    flipMinProfit = 1 } }
  ns.ScanOpenProfession()
  flush()
end

local function ByName()
  ns.Evaluate()
  local by = {}
  for _, r in ipairs(ns.results) do by[r.name] = r end
  return by
end

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------
local tests = {}

tests["basic shuffle / no profit / missing / soulbound excluded"] = function()
  Setup({
    items = { [100] = { "Bolt", 5, 0 }, [101] = { "Shirt", 120, 0 }, [102] = { "BoP Robe", 900, 1 },
              [103] = { "Belt", 50, 2 }, [200] = { "Cloth", 10, 0 }, [201] = { "Thread", 0, 0 }, [202] = { "Dye", 0, 0 } },
    ah = { [200] = 10, [202] = 500 },
    vendor = { [201] = 1 },
    recipes = {
      [1] = { name = "Shirt", out = 101, reagents = { { 200, 10 }, { 201, 5 } } },  -- 105 < 120
      [2] = { name = "Robe", out = 102, reagents = { { 200, 1 } } },                -- BoP
      [3] = { name = "Belt", out = 103, reagents = { { 200, 4 }, { 202, 1 } } },    -- 540 > 50
      [4] = { name = "Bolt", out = 100, reagents = { { 999, 1 } } },                -- unpriced reagent
      [5] = { name = "Enchant", out = nil, reagents = { { 200, 1 } } },             -- no output item
    },
  })
  local by = ByName()
  assert(#ns.results == 3)
  assert(by.Shirt.status == ns.STATUS.SHUFFLE and by.Shirt.profit == 15)
  assert(by.Belt.status == ns.STATUS.NOPROFIT)
  assert(by.Bolt.status == ns.STATUS.MISSING)
  assert(ns.flaggedByItem[101])

  MoneyTalksForeverDB.settings.useVendorReagentPrice = false
  assert(ByName().Shirt.status == ns.STATUS.MISSING, "thread has no price without vendor prices")

  MoneyTalksForeverDB.settings.useVendorReagentPrice = true
  MoneyTalksForeverDB.settings.includeSoulbound = true
  assert(ByName().Robe and ns.flaggedByItem[102])
end

local LINEN = {
  items = { [2589] = { "Linen Cloth", 1, 0 }, [2996] = { "Bolt of Linen Cloth", 10, 0 }, [2568] = { "Linen Shirt", 200, 2 },
            [300] = { "Pants", 500, 2 }, [400] = { "Thread", 0, 0 } },
  ah = nil, -- set per test
  recipes = {
    [1] = { name = "Bolt", out = 2996, reagents = { { 2589, 2 } } },
    [2] = { name = "Shirt", out = 2568, reagents = { { 2996, 3 } } },
    [3] = { name = "Unbolt", out = 2589, qty = 2, reagents = { { 2996, 1 } } },  -- cycle: bolt -> 2 cloth
    [4] = { name = "Thread", out = 400, qty = 5, reagents = { { 2589, 1 } } },
    [5] = { name = "Pants", out = 300, reagents = { { 400, 2 }, { 2996, 1 }, { 2589, 1 } } },
  },
}

tests["craftable reagents use the cheaper of buy vs craft"] = function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50 }
  Setup(LINEN)
  local by = ByName()
  assert(by.Shirt.cost == 120 and by.Shirt.status == ns.STATUS.SHUFFLE, "crafted bolts: 3 x 40")
  local b = by.Shirt.breakdown[1]
  assert(b.source == "craft" and b.buyUnit == 60 and b.craftUnit == 40)
  assert(by.Bolt.cost == 40, "bolt must not be priced by unbolting its own output")
  assert(by.Unbolt.cost == 40)

  ah[2996] = nil
  by = ByName()
  assert(by.Shirt.cost == 120 and by.Shirt.breakdown[1].buyUnit == nil, "priceable via crafting with no AH listing")

  MoneyTalksForeverDB.settings.craftReagents = false
  assert(ByName().Shirt.status == ns.STATUS.MISSING)

  MoneyTalksForeverDB.settings.craftReagents = true
  ah[2996] = 30
  by = ByName()
  assert(by.Shirt.cost == 90 and by.Shirt.breakdown[1].source == "AH")
end

tests["plan lists buys, crafts in order and leftovers"] = function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50 }
  Setup(LINEN)
  local by = ByName()
  local pl = by.Shirt.plan
  assert(by.Shirt.usesCrafting)
  assert(#pl.buys == 1 and pl.buys[1].name == "Linen Cloth" and pl.buys[1].qty == 6)
  assert(#pl.crafts == 1 and pl.crafts[1].count == 3 and pl.buyTotal == 120)

  local pp = by.Pants.plan -- 2 thread (1 craft, 3 leftover) + 1 bolt (2 cloth) + 1 cloth
  assert(#pp.buys == 1 and pp.buys[1].qty == 4)
  assert(#pp.crafts == 2 and #pp.leftovers == 1 and pp.leftovers[1].qty == 3)
  assert(math.abs(by.Pants.cost - 68) < 1e-9)

  ah[2996], ah[400] = 10, 1
  by = ByName()
  assert(not by.Shirt.usesCrafting and by.Shirt.plan.buys[1].name == "Bolt of Linen Cloth")
end

tests["auction value of the crafted item"] = function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50, [2568] = 400 }
  Setup(LINEN)
  local by = ByName()
  assert(by.Shirt.auctionValue == 400 and by.Shirt.auctionNet == 380)
  assert(by.Shirt.auctionProfit == 380 - by.Shirt.cost)
  assert(by.Thread.auctionValue == 250, "auction value counts the full output quantity (5 x 50)")
  assert(by.Pants.auctionValue == nil and by.Pants.auctionProfit == nil, "never listed -> no auction value")
end

tests["AH vs vendor verdict with estimated and recorded deposits"] = function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50, [2568] = 400, [300] = 100 }
  Setup(LINEN)
  local by = ByName()
  -- Shirt: vendor 200, AH 400 -> net 380; estimated deposit 15% of 200 = 30 -> p = 30 / (180 + 30)
  local shirt = by.Shirt
  assert(shirt.saleVerdict == "ah" and shirt.depositEstimated and shirt.deposit == 30)
  assert(math.abs(shirt.breakEvenSell - 30 / 210) < 1e-9)
  assert(by.Pants.saleVerdict == "vendor", "AH net 95 < vendor 500")
  assert(by.Bolt.saleVerdict == "ah", "verdict is known even though bolt is unprofitable to craft")

  MoneyTalksForeverDB.deposits[2568] = { [1] = 10 }
  shirt = ByName().Shirt
  assert(not shirt.depositEstimated and math.abs(shirt.breakEvenSell - 10 / 190) < 1e-9)

  MoneyTalksForeverDB.settings.ahDuration = 3 -- 48h: no recorded value, estimate x4
  assert(ByName().Shirt.deposit == 120)
end

tests["max reagent prices and Auctionator shopping list"] = function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50 }
  Setup(LINEN)
  local by = ByName()
  -- Shirt: buys 6 cloth for 120, vendor 200, min profit 1 -> slack 79 -> cap floor(20 + 79 / 6) = 33
  assert(by.Shirt.plan.buys[1].maxPrice == 33)
  -- Pants: buys 4 cloth for 80, vendor 500 -> slack 419 -> cap floor(20 + 419 / 4) = 124
  assert(by.Pants.plan.buys[1].maxPrice == 124)
  local caps = ns.CollectShoppingCaps()
  assert(#caps == 1 and caps[1].name == "Linen Cloth" and caps[1].maxPrice == 124 and caps[1].recipes == 2)

  ns.CreateShoppingList()
  local list = createdLists[ns.SHOPPING_LIST_NAME]
  assert(list and #list == 1 and list[1] == '"Linen Cloth";;;;;;;;0.0124;;;;', tostring(list and list[1]))
end

tests["vendor flips from full scan listings"] = function()
  -- vendor prices: Linen Cloth 1, Bolt 10, Shirt 200
  Setup(LINEN)
  replicate = {
    { 2996, 5, 25 },              -- 5 bolts for 25 (5 each) -> vendor 50 -> +25
    { 2996, 2, 30 },              -- 15 each > 10 -> not a flip
    { 2996, 1, 9 },               -- 9 < 10 -> +1
    { 2568, 1, 150 },             -- shirt 150 < 200 -> +50
    { 2568, 1, 0 },               -- bid only -> skipped
    { 2568, 1, 10, "Tester" },    -- own auction -> skipped
    { 2589, 20, 20 },             -- cloth 1 each = vendor -> no profit
    { 9999, 1, 1 },               -- uncached item -> skipped
  }
  assert(ns.ScanReplicateForFlips(true))
  flush()
  local f = ns.flips
  assert(#f.items == 2, "#items " .. #f.items)
  assert(f.items[1].itemID == 2568 and f.items[1].profit == 50, "sorted by profit")
  local bolt = f.items[2]
  assert(bolt.listings == 2 and bolt.qty == 6 and bolt.cost == 34 and bolt.vendor == 60 and bolt.profit == 26)
  assert(bolt.maxUnit == 9 and bolt.vendorUnit == 10)
  assert(f.skipped == 1 and MoneyTalksForeverDB.flips.Realm == f)

  MoneyTalksForeverDB.settings.flipMinProfit = 30
  ns.ScanReplicateForFlips(true); flush()
  assert(#ns.flips.items == 1 and ns.flips.items[1].itemID == 2568)

  ns.CreateFlipsShoppingList()
  local list = createdLists[ns.FLIPS_LIST_NAME]
  assert(list and #list == 1 and list[1] == '"Linen Shirt";;;;;;;;0.015;;;;', tostring(list and list[1]))

  replicate = {}
  assert(ns.ScanReplicateForFlips(true) == false, "no replicate data -> false, keeps last result")
  assert(#ns.flips.items == 1)
end

tests["full scan button, item data retry and timeout"] = function()
  Setup(LINEN)
  ns.flips = { items = {}, listings = 0 }
  replicate = {}

  -- Not at the AH: no request
  ns.ahOpen = false
  ns.StartFullScan()
  assert(replicateRequests == 0 and not ns.fullScanPending)

  -- At the AH: requests a full scan, then reads listings when the game answers
  ns.ahOpen = true
  ns.StartFullScan()
  assert(replicateRequests == 1 and ns.fullScanPending)
  assert(ns.flipProgress and ns.flipProgress.phase == "waiting" and ns.flipProgress.timeout == 90)
  ns.StartFullScan()
  assert(replicateRequests == 1, "no second request while one is pending")

  -- Shirt is not cached yet on the first read, then the game loads it
  local shirt = items[2568]
  items[2568] = nil
  local requestedLoads = {}
  C_Item.RequestLoadItemDataByID = function(id)
    requestedLoads[#requestedLoads + 1] = id
    items[2568] = shirt
  end
  replicate = { { 2568, 1, 150 }, { 2568, 1, 160 } }
  ns.OnReplicateListUpdate()
  assert(not ns.fullScanPending)
  local p = ns.flipProgress
  assert(p and p.phase == "loading" and p.skipped == 1 and p.attempt == 2, "waiting for item details before retry")
  flush() -- runs the retry
  assert(ns.flipProgress == nil, "idle again after the scan")
  C_Item.RequestLoadItemDataByID = function() end
  assert(#requestedLoads == 1, "item data requested once per item, got " .. #requestedLoads)
  assert(#ns.flips.items == 1 and ns.flips.items[1].listings == 2 and ns.flips.skipped == 0)

  -- AH never answers: timeout clears the pending state
  ns.StartFullScan()
  assert(ns.fullScanPending)
  flush() -- runs the timeout callback (mock timers ignore delays)
  assert(not ns.fullScanPending)

  -- Closing the AH cancels a pending scan
  ns.StartFullScan()
  ns.CancelFullScan()
  assert(not ns.fullScanPending and ns.flipProgress == nil)

  -- A timeout left over from an earlier scan must not cancel a newer one
  replicate = { { 2568, 1, 150 } }
  ns.StartFullScan()          -- scan A (its timeout is queued)
  ns.OnReplicateListUpdate()  -- A finishes
  ns.StartFullScan()          -- scan B
  table.remove(timers, 1)()   -- A's timeout fires
  assert(ns.fullScanPending, "stale timeout cancelled the newer scan")
  flush()                     -- B's timeout
  assert(not ns.fullScanPending)

  -- Reading progress reaches the total
  local seen = {}
  ns.OnFlipProgress = function() if ns.flipProgress then seen[#seen + 1] = ns.flipProgress.phase end end
  ns.ScanReplicateForFlips(true)
  flush()
  ns.OnFlipProgress = nil
  assert(seen[1] == "reading" and ns.flipProgress == nil)
  ns.ahOpen = false
end

local function Fire(event, ...) ns.ledgerFrame.scripts.OnEvent(ns.ledgerFrame, event, ...) end

tests["ledger: AH purchases, crafts and vendor sales"] = function()
  -- vendor prices: Linen Cloth 1, Bolt 10, Shirt 200; recipes: Bolt = 2 cloth, Shirt = 3 bolts
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50 }
  Setup(LINEN)
  ns.session = ns.NewLedgerBucket()
  money, bag = 100000, {}
  Fire("PLAYER_LOGIN") -- installs the purchase hooks
  local L = ns.Ledger()

  -- Commodity purchase: 10 cloth for 150 total (price from COMMODITY_PRICE_UPDATED)
  C_AuctionHouse.StartCommoditiesPurchase(2589, 10)
  Fire("COMMODITY_PRICE_UPDATED", 15, 150)
  C_AuctionHouse.ConfirmCommoditiesPurchase(2589, 10)
  Fire("COMMODITY_PURCHASE_SUCCEEDED")
  assert(L.bought[2589].qty == 10 and L.bought[2589].cost == 150)

  -- A failed purchase records nothing
  C_AuctionHouse.StartCommoditiesPurchase(2589, 5)
  Fire("COMMODITY_PRICE_UPDATED", 15, 75)
  C_AuctionHouse.ConfirmCommoditiesPurchase(2589, 5)
  Fire("COMMODITY_PURCHASE_FAILED")
  Fire("COMMODITY_PURCHASE_SUCCEEDED") -- stray event must not reuse the failed purchase
  assert(L.bought[2589].qty == 10)

  -- Craft 2 bolts (spell ID = recipe ID): uses 4 cloth at 15 each
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1)
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1)
  Fire("UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 1) -- someone else's cast
  assert(L.bought[2589].qty == 6 and L.crafted[2996].qty == 2 and L.crafted[2996].cost == 60)

  -- Craft a shirt with only 2 bolts in stock: 3rd bolt valued at market (AH 60) and marked estimated
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2)
  assert(L.crafted[2996] == nil and L.crafted[2568].cost == 120 and L.crafted[2568].estimated == 60)

  -- Sell the shirt (and some loot junk) to a vendor: bags and money change while the merchant is open
  bag = { [2568] = 1, [5000] = 3 }
  items[5000] = { "Junk", 7, 0 }
  Fire("MERCHANT_SHOW")
  bag = {}
  money = money + 200 + 21
  Fire("PLAYER_MONEY")
  ns.MerchantDiff()
  Fire("MERCHANT_CLOSED")
  local c = L.all.crafts
  assert(c.qty == 1 and c.earned == 200 and c.cost == 120 and c.estimated == 60, "crafts bucket")
  assert(L.items[5000] == nil, "untracked junk is ignored")
  assert(ns.BucketProfit(ns.session) == 80)

  -- Single item bought at buyout, confirmed once the money is spent
  auctionsByID = { [77] = { itemKey = { itemID = 2996 }, buyoutAmount = 25, quantity = 5 },
                   [78] = { itemKey = { itemID = 2996 }, buyoutAmount = 99, quantity = 1 } }
  C_AuctionHouse.PlaceBid(78, 50) -- a bid below buyout is not a purchase
  C_AuctionHouse.PlaceBid(77, 25)
  money = money - 25
  Fire("PLAYER_MONEY")
  Fire("PLAYER_MONEY")
  assert(L.bought[2996].qty == 5 and L.bought[2996].cost == 25)

  -- Flip: sell the 5 bolts to a vendor for 10 each
  bag = { [2996] = 5 }
  Fire("MERCHANT_SHOW")
  bag = {}
  money = money + 50
  Fire("PLAYER_MONEY")
  ns.MerchantDiff()
  Fire("MERCHANT_CLOSED")
  local fl = L.all.flips
  assert(fl.qty == 5 and fl.earned == 50 and fl.cost == 25)
  assert(L.items[2996].kind == "flips" and L.items[2568].kind == "crafts")

  -- Buying thread from a vendor puts it in stock at what was paid
  bag = {}
  Fire("MERCHANT_SHOW")
  bag = { [400] = 5 }
  money = money - 30
  Fire("PLAYER_MONEY")
  ns.MerchantDiff()
  Fire("MERCHANT_CLOSED")
  assert(L.bought[400].qty == 5 and L.bought[400].cost == 30)

  -- Only money changing (repairs) or only items changing records nothing yet
  Fire("MERCHANT_SHOW")
  money = money - 500
  Fire("PLAYER_MONEY")
  ns.MerchantDiff()
  Fire("MERCHANT_CLOSED")
  assert(L.all.flips.qty == 5 and L.all.crafts.qty == 1)

  -- Crafting at a vendor (items change, money doesn't) must not later count the used reagents as sold
  local clock = 1000
  local realGetTime = GetTime
  GetTime = function() return clock end
  bag = { [2589] = 6, [2996] = 0 }
  Fire("MERCHANT_SHOW")
  bag = { [2589] = 4, [2996] = 1 }   -- 2 cloth turned into a bolt, no money involved
  ns.MerchantDiff()                    -- starts waiting for money
  clock = clock + 2
  ns.MerchantDiff()                    -- no money came: accepted as not a sale
  bag = { [2589] = 4 }                 -- now sell the bolt
  money = money + 10
  Fire("PLAYER_MONEY")
  ns.MerchantDiff()
  Fire("MERCHANT_CLOSED")
  GetTime = realGetTime
  assert(L.items[2589] == nil, "cloth used in crafting was counted as sold")
  flush()

  local value, n = ns.LedgerStockValue()
  assert(n == 11 and math.abs(value - (6 * 15 + 30)) < 1e-9, "6 cloth + 5 thread still in stock")
  local today = L.days[os.date("%Y-%m-%d")]
  assert(today and today.flips.earned == 50 and today.crafts.earned == 200)

  ns.ResetLedger()
  assert(ns.Ledger().all.crafts.qty == 0 and ns.BucketProfit(ns.session) == 0)
end

local function FireMail(event) ns.mailFrame.scripts.OnEvent(ns.mailFrame, event) end

tests["ledger: AH sales from mail and lost deposits"] = function()
  LINEN.ah = { [2589] = 20, [2996] = 60 }
  Setup(LINEN)
  ns.session = ns.NewLedgerBucket()
  money, bag, inbox = 100000, {}, {}
  Fire("PLAYER_LOGIN")
  Fire("PLAYER_LOGIN") -- a second install must not double-record
  local L = ns.Ledger()

  -- 2 shirts bought for 150 each, listed together: the 30 deposit leaves your gold after posting
  ns.RecordPurchase(2568, 2, 300)
  C_AuctionHouse.PostItem({ itemID = 2568 }, 1, 2, nil, 400)
  money = money - 30
  Fire("PLAYER_MONEY")
  assert(#L.deposits[2568] == 1 and L.deposits[2568][1].amount == 30, "one deposit of 30 recorded")
  -- Listing an untracked item records no deposit
  C_AuctionHouse.PostItem({ itemID = 5000 }, 1, 1, nil, 10)
  money = money - 5
  Fire("PLAYER_MONEY")
  assert(L.deposits[5000] == nil)

  -- Mailbox: one shirt sold (200, AH cut 10, half the deposit paid back), one came back expired, one untracked sale
  inbox = {
    { subject = "Auction successful: Linen Shirt", money = 200 - 10 + 15,
      invoice = { type = "seller", itemName = "Linen Shirt", bid = 200, deposit = 15, consignment = 10, count = 1 } },
    { subject = "Auction expired: Linen Shirt", item = { name = "Linen Shirt", id = 2568, count = 1 } },
    { subject = "Auction successful: Junk", money = 50,
      invoice = { type = "seller", itemName = "Junk", bid = 52, deposit = 0, consignment = 2, count = 1 } },
  }
  FireMail("MAIL_SHOW")
  FireMail("MAIL_INBOX_UPDATE")             -- nothing collected yet
  assert(L.all.flips.qty == 0)
  table.remove(inbox, 1)                    -- take the sale money
  FireMail("MAIL_INBOX_UPDATE")
  local fl = L.all.flips
  assert(fl.qty == 1 and fl.earned == 190 and fl.cost == 150 and (fl.ahQty or 0) == 1 and (fl.deposits or 0) == 0,
    "AH sale: net 190, cost 150, refunded deposit is not a cost")
  table.remove(inbox, 1)                    -- take the expired shirt
  table.remove(inbox, 1)                    -- untracked sale
  FireMail("MAIL_INBOX_UPDATE")
  FireMail("MAIL_CLOSED")
  assert(fl.qty == 1 and fl.cost == 165 and fl.deposits == 15, "expired auction loses the other half of the deposit")
  assert(L.deposits[2568] == nil and L.items[2568].ahQty == 1 and L.bought[2568].qty == 1)
  assert(ns.BucketProfit(ns.session) == 190 - 165)

  -- Two identical sale mails, only one collected -> one sale. Deposit not paid back -> it is a cost.
  ns.RecordPurchase(2996, 2, 20)
  ns.RecordDeposit(2996, 1, 3)
  local mail = { subject = "Auction successful: Bolt of Linen Cloth", money = 14,
    invoice = { type = "seller", itemName = "Bolt of Linen Cloth", bid = 15, deposit = 3, consignment = 1, count = 1 } }
  inbox = { mail, mail }
  FireMail("MAIL_SHOW")
  inbox = { mail }
  FireMail("MAIL_INBOX_UPDATE")
  FireMail("MAIL_CLOSED")
  assert(L.items[2996].ahQty == 1 and L.items[2996].earned == 14 and L.items[2996].cost == 10 + 3)
  inbox = {}
end

tests["migrates CraftShuffler data once, only when there is none of our own"] = function()
  local function Load()
    ns.eventFrame.scripts.OnEvent(ns.eventFrame, "ADDON_LOADED", "MoneyTalksForever")
  end
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
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
local failed = 0
for _, name in ipairs(names) do
  local ok, err = pcall(tests[name])
  io.write((ok and "PASS  " or "FAIL  ") .. name .. (ok and "" or ("\n      " .. tostring(err))) .. "\n")
  if not ok then failed = failed + 1 end
end
io.write(("%d/%d passed\n"):format(#names - failed, #names))
os.exit(failed == 0 and 0 or 1)
