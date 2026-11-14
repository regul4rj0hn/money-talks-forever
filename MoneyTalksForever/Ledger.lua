-- Money Talks Forever: "profit so far" ledger.
--
-- Tracks real money, per character:
--   * purchases (AH and NPC vendors) put items in stock at what you paid (average cost per item)
--   * crafting a recorded recipe uses its reagents from stock and puts the crafted item in stock at that cost
--   * selling to a vendor realizes profit = vendor money - stock cost
-- Items sold that came from crafting count as "crafts", items sold as bought count as "flips". Items the ledger never
-- saw being bought or crafted (loot, junk) are ignored. Reagents used without stock are valued at the current market
-- price (Auctionator) and counted as "estimated" cost.
local _, ns = ...

local KEEP_DAYS = 90

local function NewBucket()
  return {
    crafts = { earned = 0, cost = 0, qty = 0, estimated = 0 },
    flips = { earned = 0, cost = 0, qty = 0, estimated = 0 },
  }
end
ns.NewLedgerBucket = NewBucket

local function Today() return date("%Y-%m-%d") end

function ns.Ledger()
  local key = ns.CharKey()
  local all = MoneyTalksForeverDB.ledger
  if not all[key] then
    all[key] = { bought = {}, crafted = {}, all = NewBucket(), days = {}, items = {}, since = time() }
  end
  return all[key]
end

ns.session = NewBucket()
ns.sessionStart = nil -- GetTime() of the first ledger event this session

-- Stock entry: qty, total cost, and how much of that cost is estimated (reagents valued at market price).
local function StockAdd(stock, itemID, qty, cost, estimated)
  local s = stock[itemID]
  if not s then
    s = { qty = 0, cost = 0, estimated = 0 }
    stock[itemID] = s
  end
  s.qty = s.qty + qty
  s.cost = s.cost + cost
  s.estimated = (s.estimated or 0) + (estimated or 0)
end

-- Takes up to qty from a stock entry at average cost. Returns taken qty, its cost and estimated part.
local function StockTake(stock, itemID, qty)
  local s = stock[itemID]
  if not s or s.qty <= 0 or qty <= 0 then return 0, 0, 0 end
  local take = math.min(qty, s.qty)
  local share = take / s.qty
  local cost, est = s.cost * share, (s.estimated or 0) * share
  s.qty = s.qty - take
  s.cost = s.cost - cost
  s.estimated = (s.estimated or 0) - est
  if s.qty <= 0 then stock[itemID] = nil end
  return take, cost, est
end

-- channel: "vendor" or "ah" (sold on the auction house); deposit: AH deposit lost, already included in cost.
local function AddTo(b, kind, earned, cost, qty, estimated, channel, deposit)
  local k = b[kind]
  k.earned = k.earned + earned
  k.cost = k.cost + cost
  k.qty = k.qty + qty
  k.estimated = k.estimated + (estimated or 0)
  if channel == "ah" then
    k.ahQty = (k.ahQty or 0) + qty
    k.ahEarned = (k.ahEarned or 0) + earned
  end
  k.deposits = (k.deposits or 0) + (deposit or 0)
end

local function PruneDays(days)
  local cutoff = date("%Y-%m-%d", time() - KEEP_DAYS * 86400)
  for d in pairs(days) do
    if d < cutoff then days[d] = nil end
  end
end

local function Realize(kind, itemID, qty, earned, cost, estimated, channel, deposit)
  local L = ns.Ledger()
  local day = Today()
  if not L.days[day] then
    L.days[day] = NewBucket()
    PruneDays(L.days)
  end
  AddTo(L.all, kind, earned, cost, qty, estimated, channel, deposit)
  AddTo(L.days[day], kind, earned, cost, qty, estimated, channel, deposit)
  AddTo(ns.session, kind, earned, cost, qty, estimated, channel, deposit)
  ns.sessionStart = ns.sessionStart or GetTime()

  local it = L.items[itemID]
  if not it then
    it = { kind = kind, qty = 0, earned = 0, cost = 0 }
    L.items[itemID] = it
  end
  it.kind = kind
  it.qty = it.qty + qty
  it.earned = it.earned + earned
  it.cost = it.cost + cost
  if channel == "ah" then it.ahQty = (it.ahQty or 0) + qty else it.vendorQty = (it.vendorQty or 0) + qty end
  if ns.OnLedgerChanged then ns.OnLedgerChanged() end
end

---------------------------------------------------------------------------
-- Ledger operations (pure bookkeeping, called by the event glue below)
---------------------------------------------------------------------------

function ns.RecordPurchase(itemID, qty, cost)
  if not itemID or not qty or qty <= 0 then return end
  StockAdd(ns.Ledger().bought, itemID, qty, math.max(0, cost or 0))
  ns.sessionStart = ns.sessionStart or GetTime()
  if ns.OnLedgerChanged then ns.OnLedgerChanged() end
end

-- One completed craft of a recorded recipe: use its reagents, stock the output at their cost.
function ns.RecordCraft(recipe)
  local L = ns.Ledger()
  local total, estimated = 0, 0
  for _, slot in ipairs(recipe.reagents or {}) do
    if #slot.items > 0 then
      -- Prefer the slot option we actually have in stock (bought first, then crafted).
      local id = slot.items[1]
      for _, option in ipairs(slot.items) do
        if L.bought[option] or L.crafted[option] then id = option break end
      end
      local need = slot.qty
      local got, cost = StockTake(L.bought, id, need)
      need, total = need - got, total + cost
      local est
      got, cost, est = StockTake(L.crafted, id, need)
      need, total, estimated = need - got, total + cost, estimated + est
      if need > 0 then
        -- Not bought or crafted while tracking (farmed, older stock): value at the cheapest option's price.
        local unit
        for _, option in ipairs(slot.items) do
          local p = ns.GetReagentUnitPrice(option)
          if p and (not unit or p < unit) then unit = p end
        end
        unit = unit or 0
        total = total + unit * need
        estimated = estimated + unit * need
      end
    end
  end
  local outQty = math.max(1, recipe.qtyMin or 1)
  StockAdd(L.crafted, recipe.outputItemID, outQty, total, estimated)
  ns.sessionStart = ns.sessionStart or GetTime()
  if ns.OnLedgerChanged then ns.OnLedgerChanged() end
end

-- Sold qty of itemID to a vendor for `earned` copper. Returns the profit that was tracked (nil if untracked).
-- Sold qty of itemID for `earned` copper via channel ("vendor" | "ah"). extraCost (e.g. a deposit that wasn't
-- refunded) is added to the first part realized. Returns the tracked profit, or nil if the item was untracked.
local function RecordSale(itemID, qty, earned, channel, extraCost)
  local L = ns.Ledger()
  local unitEarned = earned / qty
  local profit
  extraCost = extraCost or 0

  local got, cost, est = StockTake(L.crafted, itemID, qty)
  if got > 0 then
    Realize("crafts", itemID, got, unitEarned * got, cost + extraCost, est, channel, extraCost)
    profit = (profit or 0) + unitEarned * got - cost - extraCost
    extraCost = 0
  end
  local rest = qty - got
  got, cost = StockTake(L.bought, itemID, rest)
  if got > 0 then
    Realize("flips", itemID, got, unitEarned * got, cost + extraCost, 0, channel, extraCost)
    profit = (profit or 0) + unitEarned * got - cost - extraCost
  end
  return profit
end

function ns.RecordVendorSale(itemID, qty, earned)
  return RecordSale(itemID, qty, earned, "vendor")
end

function ns.IsTracked(itemID)
  local L = ns.Ledger()
  return L.bought[itemID] ~= nil or L.crafted[itemID] ~= nil
end

-- AH deposits paid for listings of tracked items, oldest first: L.deposits[itemID] = { {qty, amount}, ... }
function ns.RecordDeposit(itemID, qty, amount)
  local L = ns.Ledger()
  L.deposits = L.deposits or {}
  L.deposits[itemID] = L.deposits[itemID] or {}
  table.insert(L.deposits[itemID], { qty = qty, amount = amount })
end

-- Removes the deposits covering qty listed units (oldest first) and returns their total.
local function TakeDeposit(itemID, qty)
  local L = ns.Ledger()
  local list = L.deposits and L.deposits[itemID]
  local total = 0
  while list and #list > 0 and qty > 0 do
    local d = list[1]
    local take = math.min(qty, d.qty)
    local amount = d.amount * take / d.qty
    total, qty = total + amount, qty - take
    d.qty, d.amount = d.qty - take, d.amount - amount
    if d.qty <= 0 then table.remove(list, 1) end
  end
  if list and #list == 0 then L.deposits[itemID] = nil end
  return total
end

-- An auction sold: `net` = sale price minus the AH cut. depositRefund = deposit paid back with the payout.
function ns.RecordAHSale(itemID, qty, net, depositRefund)
  local deposit = TakeDeposit(itemID, qty)
  local lost = math.max(0, deposit - (depositRefund or 0))
  return RecordSale(itemID, qty, net, "ah", lost)
end

-- An auction expired or was cancelled and came back by mail: its deposit is lost.
function ns.RecordAuctionReturned(itemID, qty)
  local deposit = TakeDeposit(itemID, qty)
  if deposit <= 0 then return 0 end
  local L = ns.Ledger()
  local kind = L.crafted[itemID] and "crafts" or "flips"
  Realize(kind, itemID, 0, 0, deposit, 0, "ah", deposit)
  return deposit
end

-- Value of everything bought or crafted that hasn't been sold or used yet.
function ns.LedgerStockValue()
  local L = ns.Ledger()
  local value, n = 0, 0
  for _, s in pairs(L.bought) do value, n = value + s.cost, n + s.qty end
  for _, s in pairs(L.crafted) do value, n = value + s.cost, n + s.qty end
  return value, n
end

function ns.ResetLedger()
  MoneyTalksForeverDB.ledger[ns.CharKey()] = nil
  ns.session = NewBucket()
  ns.sessionStart = nil
  if ns.OnLedgerChanged then ns.OnLedgerChanged() end
end

---------------------------------------------------------------------------
-- Event glue
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
ns.ledgerFrame = f

local function BagCounts()
  local counts = {}
  if not C_Container then return counts end
  for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
  end
  return counts
end
ns.BagCounts = BagCounts

-- AH: commodities (stackables). Start -> price update -> confirm -> succeeded/failed.
local commodityStart, commodityConfirm
-- AH: single items bought at buyout, confirmed when the money leaves your bags.
local pendingBuys = {}
local lastMoney

local function OnStartCommoditiesPurchase(itemID, qty)
  commodityStart = { itemID = itemID, qty = qty }
end

local function OnConfirmCommoditiesPurchase(itemID, qty)
  local total
  if commodityStart and commodityStart.itemID == itemID and commodityStart.total then
    total = commodityStart.total * qty / math.max(1, commodityStart.qty)
  end
  commodityConfirm = { itemID = itemID, qty = qty, total = total }
end

local function OnPlaceBid(auctionID, amount)
  local info = C_AuctionHouse.GetAuctionInfoByID and C_AuctionHouse.GetAuctionInfoByID(auctionID)
  if not info or not info.itemKey or not info.buyoutAmount or amount < info.buyoutAmount then return end
  table.insert(pendingBuys, { itemID = info.itemKey.itemID, qty = info.quantity or 1, cost = amount, t = GetTime() })
end

-- Listings of tracked items waiting for their deposit to be paid.
local pendingPosts = {}

local function OnPost(location, _, qty)
  if not location or not C_Item.GetItemID then return end
  local ok, itemID = pcall(C_Item.GetItemID, location)
  if ok and itemID and ns.IsTracked(itemID) then
    table.insert(pendingPosts, { itemID = itemID, qty = qty or 1, t = GetTime() })
  end
end

-- Hooks only observe calls (no taint): they run after the original function.
function ns.InstallLedgerHooks()
  local AH = C_AuctionHouse
  lastMoney = GetMoney()
  if ns.ledgerHooksInstalled or not AH or not hooksecurefunc then return end
  ns.ledgerHooksInstalled = true -- installing twice would record every purchase twice
  if AH.StartCommoditiesPurchase then hooksecurefunc(AH, "StartCommoditiesPurchase", OnStartCommoditiesPurchase) end
  if AH.ConfirmCommoditiesPurchase then hooksecurefunc(AH, "ConfirmCommoditiesPurchase", OnConfirmCommoditiesPurchase) end
  if AH.PlaceBid then hooksecurefunc(AH, "PlaceBid", OnPlaceBid) end
  if AH.PostItem then hooksecurefunc(AH, "PostItem", OnPost) end
  if AH.PostCommodity then hooksecurefunc(AH, "PostCommodity", OnPost) end
  lastMoney = GetMoney()
end

local function MatchPendingBuys()
  local now = GetMoney()
  local spent = (lastMoney or now) - now
  lastMoney = now
  for i = #pendingBuys, 1, -1 do
    local p = pendingBuys[i]
    if GetTime() - p.t > 15 then
      table.remove(pendingBuys, i) -- never paid: outbid or no longer available
    elseif spent >= p.cost then
      spent = spent - p.cost
      ns.RecordPurchase(p.itemID, p.qty, p.cost)
      table.remove(pendingBuys, i)
    end
  end
  -- Whatever was spent beyond purchases while a listing is pending is that listing's deposit.
  while #pendingPosts > 0 do
    local p = pendingPosts[1]
    if GetTime() - p.t > 15 then
      table.remove(pendingPosts, 1) -- never posted (e.g. needed confirmation and was cancelled)
    elseif spent > 0 then
      ns.RecordDeposit(p.itemID, p.qty, spent)
      spent = 0
      table.remove(pendingPosts, 1)
    else
      break
    end
  end
end

-- Vendor: compare bag contents and gold while the merchant window is open.
-- Waits until both have changed, since bag and money updates can arrive in different frames.
local merchant -- { counts, money, earned, profit, untracked } while a vendor window is open

local function MerchantDiff()
  if not merchant then return end
  local counts, money = BagCounts(), GetMoney()
  local dMoney = money - merchant.money
  local decreased, increased = {}, {}
  for id, n in pairs(merchant.counts) do
    local now = counts[id] or 0
    if now < n then decreased[id] = n - now end
  end
  for id, n in pairs(counts) do
    local before = merchant.counts[id] or 0
    if n > before then increased[id] = n - before end
  end
  local itemsChanged = next(decreased) ~= nil or next(increased) ~= nil
  if not itemsChanged then
    merchant.money = money -- e.g. repairs: no items involved
    merchant.waitStart = nil
    return
  end
  if dMoney == 0 then
    -- Items changed but no money (yet). Usually the money update is a frame behind; if it doesn't come,
    -- this wasn't a sale (crafting or looting with the vendor open), so accept the new bag contents.
    if not merchant.waitStart then
      merchant.waitStart = GetTime()
      C_Timer.After(1.2, MerchantDiff)
    elseif GetTime() - merchant.waitStart > 1 then
      merchant.counts, merchant.waitStart = counts, nil
    end
    return
  end
  merchant.waitStart = nil

  if dMoney > 0 then
    for id, q in pairs(decreased) do
      local _, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(id)
      if sellPrice and sellPrice > 0 then
        local earned = sellPrice * q
        local profit = ns.RecordVendorSale(id, q, earned)
        if profit then
          merchant.earned = merchant.earned + earned
          merchant.profit = merchant.profit + profit
        end
      end
    end
  else
    -- Bought from the vendor: split what was paid across the new items by quantity.
    local totalQty = 0
    for _, q in pairs(increased) do totalQty = totalQty + q end
    for id, q in pairs(increased) do ns.RecordPurchase(id, q, -dMoney * q / totalQty) end
  end
  merchant.counts, merchant.money = counts, money
end
ns.MerchantDiff = MerchantDiff

local merchantDiffPending = false
local function RequestMerchantDiff()
  if merchantDiffPending then return end
  merchantDiffPending = true
  C_Timer.After(0.3, function()
    merchantDiffPending = false
    MerchantDiff()
  end)
end

function ns.OnMerchantShow()
  merchant = { counts = BagCounts(), money = GetMoney(), earned = 0, profit = 0 }
end

function ns.OnMerchantClosed()
  if not merchant then return end
  MerchantDiff()
  if merchant.earned > 0 and ns.Settings().chatAlert then
    ns.Print(("vendor visit: sold %s of tracked items, |cff00ff00%s profit|r (session %s)"):format(
      ns.Money(merchant.earned), ns.Money(merchant.profit), ns.Money(ns.BucketProfit(ns.session))))
  end
  merchant = nil
end

function ns.BucketProfit(b)
  return (b.crafts.earned - b.crafts.cost) + (b.flips.earned - b.flips.cost)
end

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("COMMODITY_PRICE_UPDATED")
f:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
f:RegisterEvent("COMMODITY_PURCHASE_FAILED")
f:RegisterEvent("PLAYER_MONEY")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    ns.InstallLedgerHooks()
  elseif event == "COMMODITY_PRICE_UPDATED" then
    local _, totalPrice = ...
    if commodityStart then commodityStart.total = totalPrice end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    local c = commodityConfirm
    commodityConfirm = nil
    if c then
      local cost = c.total or ((ns.GetReagentUnitPrice(c.itemID) or 0) * c.qty)
      ns.RecordPurchase(c.itemID, c.qty, cost)
    end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    commodityConfirm = nil
  elseif event == "PLAYER_MONEY" then
    if #pendingBuys > 0 or #pendingPosts > 0 then MatchPendingBuys() else lastMoney = GetMoney() end
    if merchant then RequestMerchantDiff() end
  elseif event == "BAG_UPDATE_DELAYED" then
    if merchant then RequestMerchantDiff() end
  elseif event == "MERCHANT_SHOW" then
    ns.OnMerchantShow()
  elseif event == "MERCHANT_CLOSED" then
    ns.OnMerchantClosed()
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spellID = ...
    -- Profession recipe IDs are the spell IDs of the craft.
    local recipe = unit == "player" and MoneyTalksForeverDB and ns.CharStore().recipes[spellID]
    if recipe then ns.RecordCraft(recipe) end
  end
end)
