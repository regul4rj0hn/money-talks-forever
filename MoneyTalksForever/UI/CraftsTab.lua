-- Money Talks Forever: Crafts tab - every recorded recipe, its cost, values and the "Shuffle me!" verdict.
local _, ns = ...
local UI = ns.UI
local C, Colorize, Money = ns.COLOR, ns.Colorize, ns.Money

local COLUMNS = {
  { key = "item",    label = "Crafted item",  width = 210, justify = "LEFT" },
  { key = "prof",    label = "Profession",    width = 80,  justify = "LEFT" },
  { key = "method",  label = "Reagents",      width = 90,  justify = "LEFT" },
  { key = "cost",    label = "Reagent cost",  width = 110, justify = "RIGHT" },
  { key = "vendor",  label = "Vendor value",  width = 110, justify = "RIGHT" },
  { key = "auction", label = "Auction value", width = 110, justify = "RIGHT" },
  { key = "sellvia", label = "Sell via",      width = 80,  justify = "CENTER" },
  { key = "profit",  label = "Profit",        width = 110, justify = "RIGHT" },
  { key = "status",  label = "",              width = 90,  justify = "CENTER" },
}

local STATUS_TEXT = {
  [ns.STATUS.SHUFFLE] = Colorize("Shuffle me!", C.GREEN),
  [ns.STATUS.NOPROFIT] = Colorize("no profit", C.GREY),
  [ns.STATUS.MISSING] = Colorize("no price", C.ORANGE),
  [ns.STATUS.LOADING] = Colorize("loading...", C.GREY),
}

local function Percent(chance) return math.ceil((chance or 0) * 100) end

---------------------------------------------------------------------------
-- Row tooltip: selling options, then the buy/craft plan
---------------------------------------------------------------------------
local function AddSellingLines(d)
  local function ProfitText(p) return p and (ns.ProfitMoney(p) .. " profit") or "" end
  GameTooltip:AddDoubleLine("Sell to vendor: " .. Money(d.vendorValue), ProfitText(d.profit), 1, 1, 1)
  if d.auctionValue then
    GameTooltip:AddDoubleLine(("Sell on AH: %s (%s after %d%% cut)"):format(
      Money(d.auctionValue), Money(d.auctionNet), ns.AH_CUT * 100), ProfitText(d.auctionProfit), 1, 1, 1)
  else
    UI.TipNote("Sell on AH: no Auctionator price for this item")
  end
  if d.saleVerdict == "ah" then
    local deposit = Money(d.deposit) .. (d.depositEstimated and " est." or "")
    GameTooltip:AddLine(("%s if it sells at least %d%% of the time (deposit %s, %dh)."):format(
      Colorize("List it on the AH", C.GOLD), Percent(d.breakEvenSell), deposit,
      ns.DURATION_HOURS[ns.Settings().ahDuration]), 0.9, 0.9, 0.9, true)
    UI.TipNote("Unsold auctions come back by mail and can still be vendored.")
  elseif d.auctionValue then
    GameTooltip:AddLine("Vendor it: the AH price after the cut doesn't beat the vendor price.", 0.9, 0.9, 0.9, true)
  end
end

local function AddPlanLines(d, plan)
  GameTooltip:AddLine("1. Buy:", 1, 0.82, 0)
  for _, b in ipairs(plan.buys) do
    local tag = " " .. Colorize(b.source == "vendor" and "(vendor)" or "(AH)", C.DIM)
    if b.maxPrice and b.source ~= "vendor" then tag = tag .. " " .. Colorize("max " .. Money(b.maxPrice), C.GOLD) end
    UI.TipPair(("    %dx %s"):format(b.qty, b.name or "?"), Money(b.total) .. tag)
  end
  if d.cost and plan.buyTotal > d.cost + 0.5 then
    UI.TipNote(("    Spend for one craft: %s. The listed cost of %s counts leftovers as savings for repeat crafts.")
      :format(Money(plan.buyTotal), Money(d.cost)))
  end

  GameTooltip:AddLine("2. Craft, in this order:", 1, 0.82, 0)
  for _, c in ipairs(plan.crafts) do
    GameTooltip:AddLine("    " .. Colorize(("%dx %s"):format(c.count, c.name or "?"), C.BLUE))
  end
  local sell = d.saleVerdict == "ah" and "<- sell this (see above)" or "<- vendor this"
  GameTooltip:AddLine(("    %s  %s"):format(Colorize("1x " .. (d.name or "?"), C.GREEN), sell))
  if #plan.leftovers > 0 then
    local parts = {}
    for _, l in ipairs(plan.leftovers) do table.insert(parts, l.qty .. "x " .. (l.name or "?")) end
    UI.TipNote("    leftover: " .. table.concat(parts, ", "))
  end

  if #plan.choices > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Craftable reagents", "buy / craft each", 1, 0.82, 0, 1, 0.82, 0)
    for _, c in ipairs(plan.choices) do
      local buy, craft = Money(c.buyUnit), Money(c.craftUnit)
      -- The cheaper option is shown in brackets.
      if c.source == "craft" then craft = Colorize("[" .. craft .. "]", C.BLUE) else buy = Colorize("[" .. buy .. "]", C.GREEN) end
      UI.TipPair("    " .. (c.name or "?"), buy .. "  /  " .. craft)
    end
  end
end

local function ShowRowTooltip(row)
  local d = row.data
  if not d then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(d.itemID)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(("Recipe: %s (yields %d)"):format(d.name or "?", d.qty or 1), 1, 0.82, 0)
  AddSellingLines(d)
  GameTooltip:AddLine(" ")
  if d.plan then
    AddPlanLines(d, d.plan)
  else
    -- No complete plan (some reagent has no price): show what is known and what is missing.
    for _, b in ipairs(d.breakdown or {}) do
      UI.TipPair(("  %dx %s"):format(b.qty, b.name or "?"), b.total and Money(b.total) or Colorize("no price", C.ORANGE))
    end
  end
  GameTooltip:AddLine("Shift-click to link in chat.", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function InitRow(row, d)
  if not row.cells then UI.BuildCells(row, COLUMNS, ShowRowTooltip) end
  local cells = row.cells
  row.data = d
  row.icon:SetTexture(UI.ItemIcon(d.itemID, d.icon))
  cells.item:SetText(d.itemLink or d.name or ("item:" .. d.itemID))
  cells.prof:SetText(d.profession or "")
  cells.method:SetText(d.plan and (d.usesCrafting and Colorize("buy + craft", C.BLUE) or Colorize("buy all", C.LIGHT)) or "")
  cells.cost:SetText(d.status == ns.STATUS.MISSING and Colorize("?", C.ORANGE) or Money(d.cost))
  cells.vendor:SetText(Money(d.vendorValue))

  -- Gold when selling on the AH (after the cut) beats vendoring.
  local ahBetter = d.auctionNet and d.auctionNet > (d.vendorValue or 0)
  cells.auction:SetText(ahBetter and Colorize(Money(d.auctionValue), C.GOLD) or Money(d.auctionValue))
  if d.saleVerdict == "ah" then
    cells.sellvia:SetText(Colorize(("AH %d%%+"):format(Percent(d.breakEvenSell)), C.GOLD))
  elseif d.saleVerdict == "vendor" then
    cells.sellvia:SetText(Colorize("vendor", C.LIGHT))
  else
    cells.sellvia:SetText("")
  end
  cells.profit:SetText(d.profit and ns.ProfitMoney(d.profit) or Money(nil))
  cells.status:SetText(STATUS_TEXT[d.status] or "")
end

---------------------------------------------------------------------------
-- Tab
---------------------------------------------------------------------------
local function BuildFilter(panel)
  local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("LEFT", panel.footer, "LEFT", 0, 0)
  cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb.text:SetText("Only show Shuffle me!")
  cb:SetScript("OnClick", function(self)
    ns.Settings().onlyShuffle = self:GetChecked() and true or false
    ns.RefreshUI()
  end)
  panel.onlyShuffle = cb
end

local function EmptyText()
  if #ns.results == 0 then return "No recipes recorded yet.\nOpen each of your profession windows once." end
  if not ns.AuctionatorAPI() then return "Auctionator is not loaded." end
  return "Nothing to shuffle right now.\nScan the auction house with Auctionator."
end

local function Summary()
  local S, counts = ns.STATUS, {}
  for _, r in ipairs(ns.results) do counts[r.status] = (counts[r.status] or 0) + 1 end
  return ("%s  |  %d no profit  |  %s"):format(
    Colorize((counts[S.SHUFFLE] or 0) .. " shuffle", C.GREEN), counts[S.NOPROFIT] or 0,
    Colorize((counts[S.MISSING] or 0) .. " no price", C.ORANGE))
end

local function Refresh(panel)
  local onlyShuffle = ns.Settings().onlyShuffle
  panel.onlyShuffle:SetChecked(onlyShuffle)

  local list = {}
  for _, r in ipairs(ns.results) do
    if not onlyShuffle or r.status == ns.STATUS.SHUFFLE then table.insert(list, r) end
  end
  UI.SetRows(panel, list)
  panel.empty:SetText(#list > 0 and "" or EmptyText())
  return Summary()
end

UI.RegisterTab({
  key = "crafts", label = "Crafts", icon = "Interface\\Icons\\Trade_BlackSmithing",
  columns = COLUMNS, initRow = InitRow,
  Summary = Summary, EmptyText = EmptyText, ShowTooltip = ShowRowTooltip,
  Build = BuildFilter,
  Refresh = Refresh,
  OnRefreshButton = function()
    ns.ScanOpenProfession()
    ns.Evaluate()
  end,
  OnShoppingList = function() ns.CreateReagentShoppingList() end,
  shoppingTip = "Creates the 'Money Talks Forever' list: every AH reagent of your Shuffle me! recipes, capped at the "
    .. "most you can pay and still profit. Buy every listing up to the cap.",
})
