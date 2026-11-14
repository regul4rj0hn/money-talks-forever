-- Money Talks Forever: prices (Auctionator), bind checks and the "Shuffle me!" evaluation.
local _, ns = ...

ns.STATUS = {
  SHUFFLE = 1,   -- reagent cost < vendor value  -> "Shuffle me!"
  NOPROFIT = 2,  -- priced, but not profitable
  MISSING = 3,   -- at least one reagent has no AH/vendor price
  LOADING = 4,   -- item data not cached yet
}

-- Enum.ItemBind: None=0, OnAcquire(BoP)=1, OnEquip=2, OnUse=3, Quest=4, ToWoWAccount=7, ToBnetAccount=8, ...
-- Only items that are NOT soulbound once crafted qualify by default.
local TRADEABLE_BIND = {
  [(Enum.ItemBind and Enum.ItemBind.None) or 0] = true,
  [(Enum.ItemBind and Enum.ItemBind.OnEquip) or 2] = true,
  [(Enum.ItemBind and Enum.ItemBind.OnUse) or 3] = true,
}

function ns.AuctionatorAPI()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end

function ns.Money(copper)
  if copper == nil then return "|cff808080--|r" end
  local neg = copper < 0
  local s = GetMoneyString(math.abs(math.floor(copper + 0.5)), true)
  return neg and ("-" .. s) or s
end

ns.AH_CUT = 0.05 -- the auction house keeps 5% of the sale price

local function SafeCall(fn, ...)
  if not fn then return nil end
  local ok, v = pcall(fn, ...)
  if ok and type(v) == "number" and v > 0 then return v end
  return nil
end

-- Cheapest way to acquire one unit of a reagent: AH buyout, or NPC vendor price if Auctionator knows it.
function ns.GetReagentUnitPrice(itemID)
  local api = ns.AuctionatorAPI()
  if not api then return nil end
  local ah = SafeCall(api.GetAuctionPriceByItemID, ns.CALLER_ID, itemID)
  local vendor = ns.Settings().useVendorReagentPrice and SafeCall(api.GetVendorPriceByItemID, ns.CALLER_ID, itemID) or nil
  if ah and vendor then
    if vendor <= ah then return vendor, "vendor" end
    return ah, "AH"
  end
  if ah then return ah, "AH" end
  if vendor then return vendor, "vendor" end
  return nil
end

local function ItemName(itemID)
  local name = C_Item.GetItemInfo(itemID)
  if not name then
    C_Item.RequestLoadItemDataByID(itemID)
    ns.waitingForItems = true
  end
  return name or ("item:" .. itemID)
end

-- Pricing context for one evaluation pass:
--   byOutput[itemID] = { recipe, ... }  recipes you know that produce itemID
--   memo[itemID]     = cached resolved price
--   visiting[itemID] = true while resolving (cycle guard, e.g. cloth <-> bolt conversions)
local function NewContext()
  local ctx = { byOutput = {}, memo = {}, visiting = {} }
  for _, r in pairs(ns.CharStore().recipes) do
    if r.outputItemID then
      ctx.byOutput[r.outputItemID] = ctx.byOutput[r.outputItemID] or {}
      table.insert(ctx.byOutput[r.outputItemID], r)
    end
  end
  return ctx
end

local CostReagents -- forward declaration (mutual recursion)

-- Cheapest per-unit price for a reagent: buy it (AH / vendor) or craft it from your own known recipes.
-- Returns a table { unit, source, buyUnit, buySource, craftUnit, craftName } (unit may be nil) and a
-- "cut" flag that is true when a recipe cycle was cut short (such results are not memoized).
local function ResolveUnitPrice(itemID, ctx)
  local cached = ctx.memo[itemID]
  if cached then return cached, false end

  local p = {}
  p.buyUnit, p.buySource = ns.GetReagentUnitPrice(itemID)

  local cut = false
  local recipes = ns.Settings().craftReagents and ctx.byOutput[itemID]
  if recipes then
    if ctx.visiting[itemID] then
      cut = true
    else
      ctx.visiting[itemID] = true
      for _, rec in ipairs(recipes) do
        local cost, _, missing, subCut = CostReagents(rec, ctx)
        cut = cut or subCut
        if cost and #missing == 0 then
          local perUnit = cost / math.max(1, rec.qtyMin or 1)
          if not p.craftUnit or perUnit < p.craftUnit then
            p.craftUnit, p.craftName, p.craftRecipe = perUnit, rec.name, rec
          end
        end
      end
      ctx.visiting[itemID] = nil
    end
  end

  if p.craftUnit and (not p.buyUnit or p.craftUnit < p.buyUnit) then
    p.unit, p.source = p.craftUnit, "craft"
  else
    p.unit, p.source = p.buyUnit, p.buySource
  end

  if not cut then ctx.memo[itemID] = p end
  return p, cut
end

-- Cheapest priced option for a reagent slot (slots can accept several interchangeable items).
local function BestOption(slot, ctx)
  local best, bestID, cut = nil, nil, false
  for _, id in ipairs(slot.items) do
    local p, subCut = ResolveUnitPrice(id, ctx)
    cut = cut or subCut
    if p.unit and (not best or p.unit < best.unit) then best, bestID = p, id end
  end
  return best, bestID, cut
end

-- Total cost of one craft of recipe r. Returns cost (nil if anything is unpriced), breakdown, missing, cut.
CostReagents = function(r, ctx)
  local cost, breakdown, missing, cut = 0, {}, {}, false
  for _, slot in ipairs(r.reagents) do
    if slot.currencyID and #slot.items == 0 then
      local cinfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(slot.currencyID)
      local label = (cinfo and cinfo.name) or ("currency:" .. slot.currencyID)
      table.insert(missing, label)
      table.insert(breakdown, { name = label, qty = slot.qty })
    else
      local best, bestID, subCut = BestOption(slot, ctx)
      cut = cut or subCut
      local shownID = bestID or slot.items[1]
      local line = { itemID = shownID, name = ItemName(shownID), qty = slot.qty }
      if best then
        line.unit, line.source = best.unit, best.source
        line.buyUnit, line.buySource = best.buyUnit, best.buySource
        line.craftUnit, line.craftName = best.craftUnit, best.craftName
        line.total = best.unit * slot.qty
        cost = cost + line.total
      else
        table.insert(missing, line.name)
      end
      table.insert(breakdown, line)
    end
  end
  return (#missing == 0) and cost or nil, breakdown, missing, cut
end

-- Turns the cheapest pricing decisions into concrete steps for one craft of `r`:
--   plan.buys      = { {itemID, name, qty, unit, source, total}, ... }  everything to purchase, summed over all levels
--   plan.crafts    = { {itemID, name, count}, ... }  intermediate crafts in the order to perform them
--   plan.choices   = { {itemID, name, buyUnit, craftUnit, source}, ... }  reagents where crafting was an option
--   plan.leftovers = { {itemID, name, qty}, ... }  surplus from crafts that yield more than needed
-- Integer craft counts are used here, while res.cost amortizes per unit, so plan.buyTotal may be slightly higher.
local function BuildPlan(r, ctx)
  local plan = { buys = {}, crafts = {}, choices = {}, leftovers = {}, buyTotal = 0 }
  local buyIdx, craftIdx, choiceSeen, surplus = {}, {}, {}, {}

  local function Need(itemID, qty, p)
    if p.craftUnit and not choiceSeen[itemID] then
      choiceSeen[itemID] = true
      table.insert(plan.choices, { itemID = itemID, name = ItemName(itemID),
        buyUnit = p.buyUnit, craftUnit = p.craftUnit, source = p.source })
    end

    -- Use surplus from an earlier craft first.
    local have = surplus[itemID] or 0
    local used = math.min(have, qty)
    surplus[itemID] = have - used
    qty = qty - used
    if qty <= 0 then return end

    local rec = p.source == "craft" and p.craftRecipe
    if rec and not ctx.visiting[itemID] then
      local yield = math.max(1, rec.qtyMin or 1)
      local count = math.ceil(qty / yield)
      surplus[itemID] = (surplus[itemID] or 0) + count * yield - qty
      ctx.visiting[itemID] = true
      for _, slot in ipairs(rec.reagents) do
        local best, bestID = BestOption(slot, ctx)
        if best then Need(bestID, slot.qty * count, best) end
      end
      ctx.visiting[itemID] = nil
      -- Appended after its own reagents, so the list is already in crafting order.
      local c = craftIdx[itemID]
      if not c then
        c = { itemID = itemID, name = ItemName(itemID), count = 0 }
        craftIdx[itemID] = c
        table.insert(plan.crafts, c)
      end
      c.count = c.count + count
    else
      local b = buyIdx[itemID]
      if not b then
        b = { itemID = itemID, name = ItemName(itemID), qty = 0, unit = p.buyUnit, source = p.buySource }
        buyIdx[itemID] = b
        table.insert(plan.buys, b)
      end
      b.qty = b.qty + qty
    end
  end

  for _, slot in ipairs(r.reagents) do
    local best, bestID = BestOption(slot, ctx)
    if best then Need(bestID, slot.qty, best) end
  end

  for _, b in ipairs(plan.buys) do
    b.total = (b.unit or 0) * b.qty
    plan.buyTotal = plan.buyTotal + b.total
  end
  for itemID, qty in pairs(surplus) do
    if qty > 0 then table.insert(plan.leftovers, { itemID = itemID, name = ItemName(itemID), qty = qty }) end
  end
  return plan
end

-- Returns a result row, or nil if the recipe is excluded (soulbound output).
function ns.EvaluateRecipe(recipeID, r, ctx)
  local S = ns.STATUS
  ctx = ctx or NewContext()
  local res = {
    recipeID = recipeID,
    name = r.name,
    profession = r.profession,
    itemID = r.outputItemID,
    qty = r.qtyMin or 1,     -- conservative: the guaranteed minimum output
    breakdown = {},
    missing = {},
  }

  local itemName, itemLink, _, _, _, _, _, _, _, icon, sellPrice, _, _, bindType = C_Item.GetItemInfo(r.outputItemID)
  if not itemName then
    C_Item.RequestLoadItemDataByID(r.outputItemID)
    ns.waitingForItems = true
    res.status = S.LOADING
    res.icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(r.outputItemID) or nil
    return res
  end

  if not ns.Settings().includeSoulbound and not TRADEABLE_BIND[bindType or 0] then
    return nil
  end

  res.itemLink, res.icon, res.bindType = itemLink, icon, bindType
  res.vendorValue = (sellPrice or 0) * res.qty

  -- What the output would fetch on the AH instead (Auctionator's last-scan price; nil if never seen listed).
  local api = ns.AuctionatorAPI()
  local ahUnit = api and SafeCall(api.GetAuctionPriceByItemID, ns.CALLER_ID, r.outputItemID)
  if ahUnit then
    res.auctionValue = ahUnit * res.qty
    res.auctionNet = res.auctionValue * (1 - ns.AH_CUT)
  end
  -- AH-or-vendor verdict does not depend on reagent cost, so it is known even for unpriced recipes.
  local depositUnit
  depositUnit, res.depositEstimated = ns.GetDeposit(r.outputItemID, sellPrice)
  res.deposit = depositUnit * res.qty
  res.saleVerdict, res.breakEvenSell = ns.SaleVerdict(res)

  -- Don't let a reagent be priced by crafting it back out of this recipe's own output.
  local wasVisiting = ctx.visiting[r.outputItemID]
  ctx.visiting[r.outputItemID] = true
  local cost
  cost, res.breakdown, res.missing = CostReagents(r, ctx)
  if cost then
    res.plan = BuildPlan(r, ctx)
    res.usesCrafting = #res.plan.crafts > 0
  end
  ctx.visiting[r.outputItemID] = wasVisiting

  if not cost then
    res.status = S.MISSING
    return res
  end

  res.cost = cost
  res.profit = res.vendorValue - cost
  if res.auctionNet then res.auctionProfit = res.auctionNet - cost end

  -- Highest price per bought reagent that still leaves the minimum profit (others at current price).
  local slack = res.vendorValue - res.plan.buyTotal - ns.Settings().minProfit
  for _, b in ipairs(res.plan.buys) do
    if b.unit and slack >= 0 then b.maxPrice = math.floor(b.unit + slack / b.qty) end
  end
  if res.vendorValue > 0 and res.profit >= ns.Settings().minProfit then
    res.status = S.SHUFFLE
  else
    res.status = S.NOPROFIT
  end
  return res
end

local function SortResults(a, b)
  if a.status ~= b.status then return a.status < b.status end
  local pa, pb = a.profit or -math.huge, b.profit or -math.huge
  if pa ~= pb then return pa > pb end
  return (a.recipeID or 0) < (b.recipeID or 0)
end

function ns.Evaluate()
  if not MoneyTalksForeverDB then return end
  ns.waitingForItems = false
  local results, flagged, shuffleCount = {}, {}, 0
  local ctx = NewContext()
  for recipeID, r in pairs(ns.CharStore().recipes) do
    local res = ns.EvaluateRecipe(recipeID, r, ctx)
    if res then
      table.insert(results, res)
      if res.status == ns.STATUS.SHUFFLE then
        shuffleCount = shuffleCount + 1
        local prev = flagged[res.itemID]
        if not prev or res.profit > prev.profit then flagged[res.itemID] = res end
      end
    end
  end
  table.sort(results, SortResults)
  ns.results, ns.flaggedByItem = results, flagged

  if ns.announceNextEval then
    ns.announceNextEval = false
    if ns.Settings().chatAlert then
      ns.Print(("Auctionator prices updated - %d item(s) flagged |cff00ff00Shuffle me!|r (/mtf)"):format(shuffleCount))
    end
  end
  if ns.RefreshUI then ns.RefreshUI() end
end

---------------------------------------------------------------------------
-- Tooltip: add "Shuffle me!" to any item tooltip for a flagged crafted item.
---------------------------------------------------------------------------
local function AddTooltipLine(tooltip, itemID)
  local res = itemID and ns.flaggedByItem[itemID]
  if not res then return end
  tooltip:AddLine(" ")
  tooltip:AddDoubleLine("|cff00ff00Money Talks: Shuffle me!|r", "+" .. ns.Money(res.profit) .. " / craft")
  tooltip:AddDoubleLine("  reagents (AH)", ns.Money(res.cost), 0.8, 0.8, 0.8, 1, 1, 1)
  tooltip:AddDoubleLine("  vendor value x" .. res.qty, ns.Money(res.vendorValue), 0.8, 0.8, 0.8, 1, 1, 1)
end

function ns.InstallTooltipHook()
  if TooltipDataProcessor and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if data and data.id then AddTooltipLine(tooltip, data.id) end
    end)
  elseif GameTooltip:HasScript("OnTooltipSetItem") then
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
      local _, link = tooltip:GetItem()
      local id = link and C_Item.GetItemInfoInstant(link)
      AddTooltipLine(tooltip, id)
    end)
  end
end
