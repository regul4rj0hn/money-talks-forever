-- Money Talks Forever: AH deposits, the AH-vs-vendor verdict and the reagent shopping list.
local _, ns = ...

-- Durations as used by C_AuctionHouse: 1 = 12h, 2 = 24h, 3 = 48h.
ns.DURATION_HOURS = { 12, 24, 48 }

-- Fallback until a real deposit is measured at the AH: a fraction of the vendor price per 12h (a rough guess).
local ESTIMATE_RATE_PER_12H = 0.15
-- Commodity deposits are measured on a stack and divided, so rounding doesn't dominate cheap items.
local MEASURE_QTY = 20

ns.ahOpen = false
ns.On("AUCTION_HOUSE_SHOW", function() ns.ahOpen = true end)
ns.On("AUCTION_HOUSE_CLOSED", function() ns.ahOpen = false end)

---------------------------------------------------------------------------
-- Deposits
---------------------------------------------------------------------------

-- Per-unit deposit for listing itemID at the configured duration. Returns deposit, isEstimate.
function ns.GetDeposit(itemID, unitSellPrice)
  local duration = ns.Settings().ahDuration
  local known = MoneyTalksForeverDB.deposits[itemID]
  if known and known[duration] then return known[duration], false end
  local hours = ns.DURATION_HOURS[duration] or 12
  return (unitSellPrice or 0) * ESTIMATE_RATE_PER_12H * (hours / 12), true
end

-- Measures one item's per-unit deposit. Items in your bags are measured exactly (commodity or not);
-- others can only be measured if they are commodities.
local function MeasureDeposit(itemID, duration, bagSlot)
  local AH = C_AuctionHouse
  if bagSlot and ItemLocation then
    local loc = ItemLocation:CreateFromBagAndSlot(bagSlot.bag, bagSlot.slot)
    local status = ns.SafeNumber(AH.GetItemCommodityStatus, loc)
    local commodity = Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity
    if status and status ~= commodity then
      return ns.SafeNumber(AH.CalculateItemDeposit, loc, duration, 1)
    end
  end
  local d = ns.SafeNumber(AH.CalculateCommodityDeposit, itemID, duration, MEASURE_QTY)
  return d and d / MEASURE_QTY
end

-- While the AH is open, records the real deposit of every crafted item we show that isn't known yet.
function ns.CaptureDeposits()
  if not ns.ahOpen or not C_AuctionHouse then return end
  local duration = ns.Settings().ahDuration
  local deposits = MoneyTalksForeverDB.deposits

  local wanted = {}
  for _, r in ipairs(ns.results) do
    local known = deposits[r.itemID]
    if r.auctionValue and not (known and known[duration]) then wanted[r.itemID] = true end
  end
  if not next(wanted) then return end

  local inBags = {}
  ns.ForEachBagItem(function(bag, slot, itemID)
    if wanted[itemID] and not inBags[itemID] then inBags[itemID] = { bag = bag, slot = slot } end
  end)

  local changed = false
  for itemID in pairs(wanted) do
    local perUnit = MeasureDeposit(itemID, duration, inBags[itemID])
    if perUnit then
      deposits[itemID] = deposits[itemID] or {}
      deposits[itemID][duration] = perUnit
      changed = true
    end
  end
  if changed then ns.RequestEvaluate(0.5) end
end

ns.On("AUCTION_HOUSE_SHOW", function() C_Timer.After(1, ns.CaptureDeposits) end)
-- New crafted items in your bags can be measured exactly; bursts of bag updates (buying) collapse into one.
ns.On("BAG_UPDATE_DELAYED", function()
  if ns.ahOpen then ns.Debounce("deposits", 1, ns.CaptureDeposits) end
end)

---------------------------------------------------------------------------
-- AH vs vendor verdict
---------------------------------------------------------------------------
-- An unsold auction comes back by mail and can still be vendored, so listing risks only the deposit.
-- With sell chance p:  EV(list) = p * net + (1 - p) * (vendor - deposit),  EV(vendor) = vendor.
-- Listing wins when  p > deposit / (net - vendor + deposit).
-- Returns "ah" | "vendor", and the break-even sell chance (0..1) for "ah".
function ns.SaleVerdict(res)
  if not res.auctionNet then return "vendor", nil end
  local gain = res.auctionNet - (res.vendorValue or 0)
  if gain <= 0 then return "vendor", nil end
  local deposit = res.deposit or 0
  return "ah", deposit / (gain + deposit)
end

---------------------------------------------------------------------------
-- Sell history: does an item actually sell often enough to be worth listing?
---------------------------------------------------------------------------
-- Units of each item that sold or expired on the AH, from your mail (LedgerMail.lua). Cancelled auctions don't
-- count: that was your decision, not the market's. Once an item has many results, older ones count half, so the
-- rate follows a changing market.
local HALVE_AT = 40
ns.SELL_RATE_MIN = 5 -- results needed before judging an item by its record

local function History()
  local market = MoneyTalksForeverDB.market or {}
  MoneyTalksForeverDB.market = market
  local realm = ns.RealmKey()
  market[realm] = market[realm] or {}
  return market[realm]
end

function ns.RecordAHOutcome(itemID, sold, expired)
  local h = History()
  local e = h[itemID] or { sold = 0, expired = 0 }
  h[itemID] = e
  e.sold, e.expired = e.sold + (sold or 0), e.expired + (expired or 0)
  if e.sold + e.expired > HALVE_AT then e.sold, e.expired = e.sold / 2, e.expired / 2 end
end

-- Share of listed units that sold (0..1), units sold, units with a result. nil without any history.
function ns.SellRate(itemID)
  local e = History()[itemID]
  local total = e and (e.sold + e.expired) or 0
  if total <= 0 then return nil end
  return e.sold / total, e.sold, total
end

-- For a row that says list it on the AH: true if your record for the item beats its break-even sell chance,
-- false if not, nil when there isn't enough history to tell.
function ns.SellRateVerdict(res)
  if res.saleVerdict ~= "ah" or not res.breakEvenSell then return nil end
  local rate, _, total = ns.SellRate(res.itemID)
  if not rate or total < ns.SELL_RATE_MIN then return nil end
  return rate >= res.breakEvenSell
end

---------------------------------------------------------------------------
-- Reagent shopping list
---------------------------------------------------------------------------
ns.SHOPPING_LIST_NAME = "Money Talks Forever"

-- Highest price per reagent you can pay and still make the minimum profit, over all profitable recipes.
-- Returns a list of { itemID, name, maxPrice, unit, recipes } sorted by name, and { [itemID] = name } of
-- reagents bought from NPC vendors.
function ns.CollectShoppingCaps()
  local caps, vendorItems = {}, {}
  for _, r in ipairs(ns.results) do
    if ns.IsProfitable(r) and r.plan then
      for _, b in ipairs(r.plan.buys) do
        if b.source == "vendor" then
          vendorItems[b.itemID] = b.name
        elseif b.maxPrice then
          local c = caps[b.itemID]
          if not c then
            c = { itemID = b.itemID, name = b.name, maxPrice = b.maxPrice, unit = b.unit, recipes = 0 }
            caps[b.itemID] = c
          end
          c.maxPrice = math.max(c.maxPrice, b.maxPrice)
          c.recipes = c.recipes + 1
        end
      end
    end
  end
  local list = {}
  for _, c in pairs(caps) do table.insert(list, c) end
  table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
  return list, vendorItems
end

function ns.CreateReagentShoppingList()
  ns.Evaluate()
  local caps, vendorItems = ns.CollectShoppingCaps()

  local terms = {}
  for _, c in ipairs(caps) do
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(c.itemID) or C_Item.GetItemInfo(c.itemID)
    if name then table.insert(terms, { name = name, maxPrice = c.maxPrice }) end
  end
  if #terms == 0 then
    ns.Print("nothing to buy - no profitable recipe has room to pay more than current prices.")
    return
  end
  local added, err = ns.CreateAuctionatorList(ns.SHOPPING_LIST_NAME, terms)
  if not added then
    ns.Print(err)
    return
  end

  ns.Print(("created Auctionator shopping list '%s' with %d reagent(s). Buy every listing up to:")
    :format(ns.SHOPPING_LIST_NAME, added))
  for _, c in ipairs(caps) do
    print(("  %s  <=  %s each  (now %s, %d recipe%s)"):format(
      c.name, ns.Money(c.maxPrice), ns.Money(c.unit), c.recipes, c.recipes == 1 and "" or "s"))
  end
  local vendorNames = {}
  for _, name in pairs(vendorItems) do table.insert(vendorNames, name) end
  if #vendorNames > 0 then
    table.sort(vendorNames)
    print("  from an NPC vendor: " .. table.concat(vendorNames, ", "))
  end
end
