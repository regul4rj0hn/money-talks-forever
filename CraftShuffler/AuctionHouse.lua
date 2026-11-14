-- CraftShuffler: AH-vs-vendor verdict (deposits) and Auctionator shopping list with max prices.
local _, ns = ...

-- Durations as used by C_AuctionHouse: 1 = 12h, 2 = 24h, 3 = 48h.
ns.DURATION_HOURS = { 12, 24, 48 }

-- Fallback when no real deposit has been recorded yet: a fraction of the vendor price per 12h.
-- This is a rough estimate; real values are recorded whenever you visit the AH.
local ESTIMATE_RATE_PER_12H = 0.15

---------------------------------------------------------------------------
-- Deposits
---------------------------------------------------------------------------

-- Per-unit deposit for listing itemID at the configured duration. Returns deposit, isEstimate.
function ns.GetDeposit(itemID, unitSellPrice)
  local duration = ns.Settings().ahDuration
  local rec = CraftShufflerDB.deposits[itemID]
  if rec and rec[duration] then return rec[duration], false end
  local hours = ns.DURATION_HOURS[duration] or 12
  return (unitSellPrice or 0) * ESTIMATE_RATE_PER_12H * (hours / 12), true
end

local function FindInBags(wanted)
  local found = {}
  if not C_Container then return found end
  for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local id = C_Container.GetContainerItemID(bag, slot)
      if id and wanted[id] and not found[id] then found[id] = { bag = bag, slot = slot } end
    end
  end
  return found
end

local function TryCall(fn, ...)
  if not fn then return nil end
  local ok, v = pcall(fn, ...)
  if ok and type(v) == "number" then return v end
  return nil
end

-- While the AH is open, ask the game for the real deposit of every crafted item we show.
-- Items in your bags are measured exactly (commodity or not); others are tried as commodities.
function ns.CaptureDeposits()
  local AH = C_AuctionHouse
  if not ns.ahOpen or not AH then return end
  local duration = ns.Settings().ahDuration
  local QTY = 20 -- measure on a stack and divide, so rounding doesn't dominate cheap items

  local wanted = {}
  for _, r in ipairs(ns.results) do
    if r.auctionValue then wanted[r.itemID] = true end
  end
  local inBags = FindInBags(wanted)

  local changed = false
  for itemID in pairs(wanted) do
    local perUnit
    local where = inBags[itemID]
    if where and ItemLocation then
      local loc = ItemLocation:CreateFromBagAndSlot(where.bag, where.slot)
      local status = TryCall(AH.GetItemCommodityStatus, loc)
      local commodity = Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity
      if status and status == commodity then
        local d = TryCall(AH.CalculateCommodityDeposit, itemID, duration, QTY)
        perUnit = d and d / QTY
      elseif status then
        perUnit = TryCall(AH.CalculateItemDeposit, loc, duration, 1)
      end
    else
      local d = TryCall(AH.CalculateCommodityDeposit, itemID, duration, QTY)
      perUnit = d and d / QTY
    end
    if perUnit then
      local rec = CraftShufflerDB.deposits[itemID] or {}
      if rec[duration] ~= perUnit then
        rec[duration] = perUnit
        CraftShufflerDB.deposits[itemID] = rec
        changed = true
      end
    end
  end
  if changed then ns.RequestEvaluate(0.5) end
end

---------------------------------------------------------------------------
-- AH vs vendor verdict
---------------------------------------------------------------------------
-- An unsold auction comes back by mail and can still be vendored, so listing risks only the deposit.
-- With sell chance p:  EV(list) = p * net + (1 - p) * (vendor - deposit),  EV(vendor) = vendor.
-- Listing wins when  p > deposit / (net - vendor + deposit).
-- Returns "ah" | "vendor", break-even sell chance (0..1) for "ah".
function ns.SaleVerdict(res)
  if not res.auctionNet then return "vendor", nil end
  local gain = res.auctionNet - (res.vendorValue or 0)
  if gain <= 0 then return "vendor", nil end
  local deposit = res.deposit or 0
  return "ah", deposit / (gain + deposit)
end

---------------------------------------------------------------------------
-- Shopping list
---------------------------------------------------------------------------
ns.SHOPPING_LIST_NAME = "CraftShuffler"

-- Highest price per reagent you can pay and still make the minimum profit, over all "Shuffle me!" recipes.
-- Returns sorted list of { itemID, name, maxPrice, unit, recipes = n } plus vendor-bought reagents.
function ns.CollectShoppingCaps()
  local caps, vendorItems = {}, {}
  for _, r in ipairs(ns.results) do
    if r.status == ns.STATUS.SHUFFLE and r.plan then
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

function ns.CreateShoppingList()
  local api = ns.AuctionatorAPI()
  if not api or not api.CreateShoppingList or not api.ConvertToSearchString then
    ns.Print("Auctionator shopping lists are not available.")
    return
  end
  ns.Evaluate()
  local caps, vendorItems = ns.CollectShoppingCaps()

  local searchStrings = {}
  for _, c in ipairs(caps) do
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(c.itemID) or C_Item.GetItemInfo(c.itemID)
    if name then
      local ok, s = pcall(api.ConvertToSearchString, ns.CALLER_ID,
        { searchString = name, isExact = true, maxPrice = c.maxPrice })
      if ok and type(s) == "string" then table.insert(searchStrings, s) end
    end
  end
  if #searchStrings == 0 then
    ns.Print("nothing to buy - no 'Shuffle me!' recipe has room to pay more than current prices.")
    return
  end

  local ok, err = pcall(api.CreateShoppingList, ns.CALLER_ID, ns.SHOPPING_LIST_NAME, searchStrings)
  if not ok then
    ns.Print("could not create shopping list: " .. tostring(err))
    return
  end
  ns.Print(("created Auctionator shopping list '%s' with %d reagent(s). Buy every listing up to:")
    :format(ns.SHOPPING_LIST_NAME, #searchStrings))
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

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_SHOW" then
    ns.ahOpen = true
    C_Timer.After(1, ns.CaptureDeposits)
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ns.ahOpen = false
    ns.CancelFullScan()
  elseif event == "BAG_UPDATE_DELAYED" and ns.ahOpen then
    ns.CaptureDeposits()
  end
end)
