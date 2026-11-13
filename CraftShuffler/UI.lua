-- CraftShuffler: results window.
local _, ns = ...

local ROW_H = 20
local COLS = {
  { key = "item",   label = "Crafted item", width = 210, justify = "LEFT" },
  { key = "prof",   label = "Profession",   width = 80,  justify = "LEFT" },
  { key = "method", label = "Reagents",     width = 90,  justify = "LEFT" },
  { key = "cost",   label = "Reagent cost", width = 110, justify = "RIGHT" },
  { key = "vendor", label = "Vendor value", width = 110, justify = "RIGHT" },
  { key = "auction", label = "Auction value", width = 110, justify = "RIGHT" },
  { key = "sellvia", label = "Sell via",     width = 80,  justify = "CENTER" },
  { key = "profit", label = "Profit",       width = 110, justify = "RIGHT" },
  { key = "status", label = "",             width = 90,  justify = "CENTER" },
}
local STATUS_TEXT = {
  [1] = "|cff00ff00Shuffle me!|r",
  [2] = "|cff808080no profit|r",
  [3] = "|cffff9900no price|r",
  [4] = "|cff808080loading...|r",
}

local frame

local function ShowRowTooltip(row)
  local d = row.data
  if not d then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(d.itemID)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(("Recipe: %s (yields %d)"):format(d.name or "?", d.qty or 1), 1, 0.82, 0)
  local function ProfitText(p)
    if not p then return "" end
    return (p > 0 and "|cff00ff00" or "|cffff4040") .. ns.Money(p) .. "|r profit"
  end
  GameTooltip:AddDoubleLine("Sell to vendor: " .. ns.Money(d.vendorValue), ProfitText(d.profit), 1, 1, 1)
  if d.auctionValue then
    GameTooltip:AddDoubleLine(("Sell on AH: %s (%s after %d%% cut)"):format(
      ns.Money(d.auctionValue), ns.Money(d.auctionNet), ns.AH_CUT * 100), ProfitText(d.auctionProfit), 1, 1, 1)
  else
    GameTooltip:AddLine("Sell on AH: no Auctionator price for this item", 0.6, 0.6, 0.6)
  end
  if d.saleVerdict == "ah" then
    local dep = ns.Money(d.deposit) .. (d.depositEstimated and " est." or "")
    GameTooltip:AddLine(("|cffffd100List it on the AH|r if it sells at least %d%% of the time (deposit %s, %dh)."):format(
      math.ceil((d.breakEvenSell or 0) * 100), dep, ns.DURATION_HOURS[ns.Settings().ahDuration]), 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("Unsold auctions come back by mail and can still be vendored.", 0.6, 0.6, 0.6, true)
  elseif d.auctionValue then
    GameTooltip:AddLine("Vendor it: the AH price after the cut doesn't beat the vendor price.", 0.9, 0.9, 0.9, true)
  end
  GameTooltip:AddLine(" ")
  local plan = d.plan
  if plan then
    local W, G = 0.9, 0.6
    GameTooltip:AddLine("1. Buy:", 1, 0.82, 0)
    for _, b in ipairs(plan.buys) do
      local tag = b.source == "vendor" and " |cff999999(vendor)|r" or " |cff999999(AH)|r"
      if b.maxPrice and b.source ~= "vendor" then
        tag = tag .. (" |cffffd100max %s|r"):format(ns.Money(b.maxPrice))
      end
      GameTooltip:AddDoubleLine(("    %dx %s"):format(b.qty, b.name or "?"), ns.Money(b.total) .. tag, W, W, W, 1, 1, 1)
    end
    if d.cost and plan.buyTotal > d.cost + 0.5 then
      GameTooltip:AddLine(("    Spend for one craft: %s. The listed cost of %s counts leftovers as savings for repeat crafts.")
        :format(ns.Money(plan.buyTotal), ns.Money(d.cost)), G, G, G, true)
    end
    GameTooltip:AddLine("2. Craft, in this order:", 1, 0.82, 0)
    for _, c in ipairs(plan.crafts) do
      GameTooltip:AddLine(("    |cff66ccff%dx %s|r"):format(c.count, c.name or "?"))
    end
    GameTooltip:AddLine(("    |cff00ff00%dx %s|r  <- vendor this"):format(1, d.name or "?"))
    if #plan.leftovers > 0 then
      local parts = {}
      for _, l in ipairs(plan.leftovers) do table.insert(parts, l.qty .. "x " .. (l.name or "?")) end
      GameTooltip:AddLine("    leftover: " .. table.concat(parts, ", "), G, G, G, true)
    end
    if #plan.choices > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine("Craftable reagents", "buy / craft each", 1, 0.82, 0, 1, 0.82, 0)
      for _, c in ipairs(plan.choices) do
        local b, k = ns.Money(c.buyUnit), ns.Money(c.craftUnit)
        if c.source == "craft" then k = "|cff66ccff[" .. k .. "]|r" else b = "|cff00ff00[" .. b .. "]|r" end
        GameTooltip:AddDoubleLine("    " .. (c.name or "?"), b .. "  /  " .. k, W, W, W, 1, 1, 1)
      end
    end
  else
    -- No complete plan (some reagent has no price): show what is known and what is missing.
    for _, b in ipairs(d.breakdown or {}) do
      local right = b.total and ns.Money(b.total) or "|cffff9900no price|r"
      GameTooltip:AddDoubleLine(("  %dx %s"):format(b.qty, b.name or "?"), right, 0.9, 0.9, 0.9, 1, 1, 1)
    end
  end
  GameTooltip:AddLine("Shift-click to link in chat.", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

-- Creates the row's icon + one font string per column, once per recycled row frame.
local function BuildCells(row, cols, onEnter)
  row:SetHeight(ROW_H)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ROW_H - 2, ROW_H - 2)
  row.icon:SetPoint("LEFT", 2, 0)

  row.cells = {}
  local x = 0
  for i, col in ipairs(cols) do
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local inset = (i == 1) and (ROW_H + 4) or 0
    fs:SetPoint("LEFT", x + inset, 0)
    fs:SetWidth(col.width - inset - 6)
    fs:SetJustifyH(col.justify)
    fs:SetWordWrap(false)
    row.cells[col.key] = fs
    x = x + col.width
  end

  row:SetScript("OnEnter", onEnter)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnClick", function(self)
    local link = self.data and (self.data.itemLink or self.data.link)
    if IsModifiedClick("CHATLINK") and link then ChatEdit_InsertLink(link) end
  end)
end

local function InitRow(row, d)
  if not row.cells then BuildCells(row, COLS, ShowRowTooltip) end

  row.data = d
  row.icon:SetTexture(d.icon or 134400) -- question mark fallback
  row.cells.item:SetText(d.itemLink or d.name or ("item:" .. d.itemID))
  row.cells.prof:SetText(d.profession or "")
  if d.plan then
    row.cells.method:SetText(d.usesCrafting and "|cff66ccffbuy + craft|r" or "|cffccccccbuy all|r")
  else
    row.cells.method:SetText("")
  end
  row.cells.cost:SetText(d.status == ns.STATUS.MISSING and "|cffff9900?|r" or ns.Money(d.cost))
  row.cells.vendor:SetText(ns.Money(d.vendorValue))
  -- Gold when selling on the AH (after the cut) beats vendoring.
  local ahBetter = d.auctionNet and d.auctionNet > (d.vendorValue or 0)
  if d.saleVerdict == "ah" then
    row.cells.sellvia:SetText(("|cffffd100AH %d%%+|r"):format(math.ceil((d.breakEvenSell or 0) * 100)))
  elseif d.saleVerdict == "vendor" then
    row.cells.sellvia:SetText("|cffccccccvendor|r")
  else
    row.cells.sellvia:SetText("")
  end
  row.cells.auction:SetText((ahBetter and "|cffffd100" or "") .. ns.Money(d.auctionValue) .. (ahBetter and "|r" or ""))
  if d.profit then
    local color = d.profit > 0 and "|cff00ff00" or "|cffff4040"
    row.cells.profit:SetText(color .. ns.Money(d.profit) .. "|r")
  else
    row.cells.profit:SetText(ns.Money(nil))
  end
  row.cells.status:SetText(STATUS_TEXT[d.status] or "")
end

---------------------------------------------------------------------------
-- Vendor flips table
---------------------------------------------------------------------------
local FLIP_COLS = {
  { key = "item",     label = "Item",              width = 250, justify = "LEFT" },
  { key = "listings", label = "Listings",          width = 70,  justify = "RIGHT" },
  { key = "qty",      label = "Quantity",          width = 70,  justify = "RIGHT" },
  { key = "maxbuy",   label = "Buy up to (each)",  width = 120, justify = "RIGHT" },
  { key = "vendor",   label = "Vendor pays (each)", width = 120, justify = "RIGHT" },
  { key = "cost",     label = "Total cost",        width = 110, justify = "RIGHT" },
  { key = "profit",   label = "Profit",            width = 110, justify = "RIGHT" },
}

local function ShowFlipTooltip(row)
  local e = row.data
  if not e then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(e.itemID)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("|cff00ff00Vendor flip|r: buy on the AH, sell to any vendor.")
  GameTooltip:AddDoubleLine(("Buy %d in %d listing(s)"):format(e.qty, e.listings), ns.Money(e.cost), 0.9, 0.9, 0.9, 1, 1, 1)
  GameTooltip:AddDoubleLine("Vendor pays", ns.Money(e.vendor), 0.9, 0.9, 0.9, 1, 1, 1)
  GameTooltip:AddDoubleLine("Profit", ns.Money(e.profit), 0.9, 0.9, 0.9, 0, 1, 0)
  GameTooltip:AddLine(("Only buy listings up to %s each."):format(ns.Money(math.floor(e.maxUnit))), 1, 0.82, 0)
  if ns.flips.scannedAt then
    GameTooltip:AddLine(("From the full scan %d min ago; some listings may be gone."):format(
      math.floor((time() - ns.flips.scannedAt) / 60)), 0.6, 0.6, 0.6, true)
  end
  GameTooltip:AddLine("Shift-click to link in chat.", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

local function InitFlipRow(row, e)
  if not row.cells then BuildCells(row, FLIP_COLS, ShowFlipTooltip) end
  row.data = e
  row.icon:SetTexture(e.icon or 134400)
  row.cells.item:SetText(e.link or e.name)
  row.cells.listings:SetText(e.listings)
  row.cells.qty:SetText(e.qty)
  row.cells.maxbuy:SetText(ns.Money(math.floor(e.maxUnit)))
  row.cells.vendor:SetText(ns.Money(e.vendorUnit))
  row.cells.cost:SetText(ns.Money(e.cost))
  row.cells.profit:SetText("|cff00ff00" .. ns.Money(e.profit) .. "|r")
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function TableWidth(cols)
  local w = 30
  for _, c in ipairs(cols) do w = w + c.width end
  return w
end

-- A panel with column headers and a scrolling list, filling the window between tabs and footer.
local function CreateTable(parent, cols, initializer)
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetPoint("TOPLEFT", 0, -56)
  panel:SetPoint("BOTTOMRIGHT", 0, 40)

  local x = 16
  for _, col in ipairs(cols) do
    local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", x, 0)
    h:SetWidth(col.width - 6)
    h:SetJustifyH(col.justify)
    h:SetText(col.label)
    x = x + col.width
  end

  local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", 12, -16)
  scrollBox:SetPoint("BOTTOMRIGHT", -30, 0)
  local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_H)
  view:SetElementInitializer("Button", initializer)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
  panel.scrollBox = scrollBox

  panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
  panel.empty:SetPoint("CENTER", scrollBox, "CENTER")
  panel.empty:SetWidth(TableWidth(cols) - 80)
  return panel
end

local function SimpleButton(parent, text, width, onClick, tipTitle, tipText)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  if tipTitle then
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(tipTitle)
      GameTooltip:AddLine(tipText, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
  end
  return b
end

local function CreateUI()
  local width = math.max(TableWidth(COLS), TableWidth(FLIP_COLS))

  frame = CreateFrame("Frame", "CraftShufflerFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(width + 20, 480)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:Hide()
  tinsert(UISpecialFrames, "CraftShufflerFrame") -- close with Escape

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOP", 0, -5)
  frame.title:SetText("CraftShuffler v" .. ns.VERSION)

  -- Tabs
  frame.tabButtons = {
    crafts = SimpleButton(frame, "Crafts", 100, function() ns.ShowTab("crafts") end),
    flips = SimpleButton(frame, "Vendor flips", 110, function() ns.ShowTab("flips") end),
  }
  frame.tabButtons.crafts:SetPoint("TOPLEFT", 12, -28)
  frame.tabButtons.flips:SetPoint("LEFT", frame.tabButtons.crafts, "RIGHT", 4, 0)

  frame.panels = {
    crafts = CreateTable(frame, COLS, InitRow),
    flips = CreateTable(frame, FLIP_COLS, InitFlipRow),
  }

  -- Footer (crafts tab): filter checkbox
  local cb = CreateFrame("CheckButton", nil, frame.panels.crafts, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", frame.panels.crafts, "BOTTOMLEFT", 12, -6)
  cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb.text:SetText("Only show Shuffle me!")
  cb:SetScript("OnClick", function(self)
    ns.Settings().onlyShuffle = self:GetChecked() and true or false
    ns.RefreshUI()
  end)
  frame.onlyShuffle = cb

  -- Footer: buttons act on the current tab
  local refresh = SimpleButton(frame, "Refresh", 90, function()
    if ns.Settings().tab == "flips" then
      if not ns.ScanReplicateForFlips(true) then
        ns.Print("no full scan data available - at the AH, run a full scan in Auctionator first.")
      end
    else
      ns.ScanOpenProfession()
      ns.Evaluate()
    end
  end)
  refresh:SetPoint("BOTTOMRIGHT", -12, 10)

  local shop = SimpleButton(frame, "Shopping list", 110, function()
    if ns.Settings().tab == "flips" then ns.CreateFlipsShoppingList() else ns.CreateShoppingList() end
  end, "Auctionator shopping list",
    "Crafts tab: the 'CraftShuffler' list of reagents for your Shuffle me! recipes, capped at the most you can pay. "
    .. "Vendor flips tab: the 'CraftShuffler Flips' list, capped below vendor price. Buy every listing up to the cap.")
  shop:SetPoint("RIGHT", refresh, "LEFT", -6, 0)

  frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.summary:SetPoint("RIGHT", shop, "LEFT", -10, 0)
  frame.summary:SetJustifyH("RIGHT")

  frame:SetScript("OnShow", function() ns.Evaluate() end)
end

local function RefreshCrafts(panel)
  local onlyShuffle = ns.Settings().onlyShuffle
  frame.onlyShuffle:SetChecked(onlyShuffle)

  local list, counts = {}, { 0, 0, 0, 0 }
  for _, r in ipairs(ns.results) do
    counts[r.status] = counts[r.status] + 1
    if not onlyShuffle or r.status == ns.STATUS.SHUFFLE then table.insert(list, r) end
  end
  panel.scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)

  frame.summary:SetText(("|cff00ff00%d shuffle|r  |  %d no profit  |  |cffff9900%d no price|r"):format(
    counts[1], counts[2], counts[3]))

  if #list > 0 then
    panel.empty:SetText("")
  elseif #ns.results == 0 then
    panel.empty:SetText("No recipes recorded yet.\nOpen each of your profession windows once.")
  elseif not ns.AuctionatorAPI() then
    panel.empty:SetText("Auctionator is not loaded.")
  else
    panel.empty:SetText("Nothing to shuffle right now.\nRun a full Auctionator scan at the auction house.")
  end
end

local function RefreshFlips(panel)
  local f = ns.flips
  panel.scrollBox:SetDataProvider(CreateDataProvider(f.items), ScrollBoxConstants.RetainScrollPosition)
  local total = 0
  for _, e in ipairs(f.items) do total = total + e.profit end
  if f.scannedAt then
    frame.summary:SetText(("%d flips  |  |cff00ff00%s|r total  |  scanned %d min ago"):format(
      #f.items, ns.Money(total), math.floor((time() - f.scannedAt) / 60)))
  else
    frame.summary:SetText("")
  end
  if ns.flipScanRunning then
    panel.empty:SetText("Scanning listings...")
  elseif #f.items > 0 then
    panel.empty:SetText("")
  elseif not f.scannedAt then
    panel.empty:SetText("No full scan yet.\nAt the AH, run a full scan in Auctionator; flips appear when it finishes.")
  else
    panel.empty:SetText("No listings below vendor price in the last full scan.")
  end
end

function ns.RefreshUI()
  if not frame or not frame:IsShown() then return end
  local tab = ns.Settings().tab == "flips" and "flips" or "crafts"
  for name, panel in pairs(frame.panels) do panel:SetShown(name == tab) end
  for name, b in pairs(frame.tabButtons) do b:SetEnabled(name ~= tab) end -- active tab looks pressed
  if tab == "flips" then RefreshFlips(frame.panels.flips) else RefreshCrafts(frame.panels.crafts) end
end

function ns.ShowTab(tab)
  ns.Settings().tab = tab
  if not frame then CreateUI() end
  if frame:IsShown() then ns.RefreshUI() else frame:Show() end
end

function ns.ToggleUI()
  if not frame then CreateUI() end
  frame:SetShown(not frame:IsShown())
end
