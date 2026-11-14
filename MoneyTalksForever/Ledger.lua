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
  ns.NotifyUI()
end

---------------------------------------------------------------------------
-- Ledger operations (pure bookkeeping, called by the event glue below)
---------------------------------------------------------------------------

function ns.RecordPurchase(itemID, qty, cost)
  if not itemID or not qty or qty <= 0 then return end
  StockAdd(ns.Ledger().bought, itemID, qty, math.max(0, cost or 0))
  ns.sessionStart = ns.sessionStart or GetTime()
  ns.NotifyUI()
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
  ns.NotifyUI()
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
  ns.NotifyUI()
end

function ns.BucketProfit(b)
  return (b.crafts.earned - b.crafts.cost) + (b.flips.earned - b.flips.cost)
end

-- Crafting a recorded recipe. Profession recipe IDs are the spell IDs of the craft.
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit ~= "player" or not MoneyTalksForeverDB then return end
  local recipe = ns.CharStore().recipes[spellID]
  if recipe then ns.RecordCraft(recipe) end
end)
