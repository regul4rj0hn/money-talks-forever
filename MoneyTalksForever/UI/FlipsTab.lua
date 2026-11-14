-- Money Talks Forever: Vendor flips tab - AH listings below vendor price, the Full scan button and its progress bar.
local _, ns = ...
local UI = ns.UI
local C, Colorize, Money = ns.COLOR, ns.Colorize, ns.Money

local COLUMNS = {
  { key = "item",     label = "Item",               width = 250, justify = "LEFT" },
  { key = "listings", label = "Listings",           width = 70,  justify = "RIGHT" },
  { key = "qty",      label = "Quantity",           width = 70,  justify = "RIGHT" },
  { key = "maxbuy",   label = "Buy up to (each)",   width = 120, justify = "RIGHT" },
  { key = "vendor",   label = "Vendor pays (each)", width = 120, justify = "RIGHT" },
  { key = "cost",     label = "Total cost",         width = 110, justify = "RIGHT" },
  { key = "profit",   label = "Profit",             width = 110, justify = "RIGHT" },
}

local function MinutesAgo(t) return math.floor((time() - t) / 60) end

local function ShowRowTooltip(row)
  local e = row.data
  if not e then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(e.itemID)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(Colorize("Vendor flip", C.GREEN) .. ": buy on the AH, sell to any vendor.")
  UI.TipPair(("Buy %d in %d listing(s)"):format(e.qty, e.listings), Money(e.cost))
  UI.TipPair("Vendor pays", Money(e.vendor))
  UI.TipPair("Profit", ns.ProfitMoney(e.profit))
  GameTooltip:AddLine(("Only buy listings up to %s each."):format(Money(math.floor(e.maxUnit))), 1, 0.82, 0)
  if ns.flips.scannedAt then
    UI.TipNote(("From the full scan %d min ago; some listings may be gone."):format(MinutesAgo(ns.flips.scannedAt)))
  end
  GameTooltip:AddLine("Shift-click to link in chat.", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

local function InitRow(row, e)
  if not row.cells then UI.BuildCells(row, COLUMNS, ShowRowTooltip) end
  local cells = row.cells
  row.data = e
  row.icon:SetTexture(e.icon or UI.QUESTION_MARK_ICON)
  cells.item:SetText(e.link or e.name)
  cells.listings:SetText(e.listings)
  cells.qty:SetText(e.qty)
  cells.maxbuy:SetText(Money(math.floor(e.maxUnit)))
  cells.vendor:SetText(Money(e.vendorUnit))
  cells.cost:SetText(Money(e.cost))
  cells.profit:SetText(ns.ProfitMoney(e.profit))
end

---------------------------------------------------------------------------
-- Full scan progress bar
---------------------------------------------------------------------------
local Num = BreakUpLargeNumbers or tostring

-- Text and fill (0..1, or nil for an empty bar) for the scan's current phase.
local function ProgressText(p)
  local now = GetTime()
  if p.phase == "waiting" then
    -- The game reports no progress while the AH sends the listings; show how long we've waited.
    return ("Waiting for the AH to send all listings... %ds (gives up after %ds)"):format(
      math.floor(now - p.startedAt), p.timeout), nil
  elseif p.phase == "reading" then
    local pct = p.total > 0 and p.done / p.total or 0
    local try = (p.attempt or 1) > 1 and (" - try %d/3"):format(p.attempt) or ""
    return ("Reading listings %s / %s (%d%%)%s"):format(Num(p.done), Num(p.total), math.floor(pct * 100), try), pct
  elseif p.phase == "loading" then
    return ("Loading details for %s listing(s), reading again in %ds (try %d/3)"):format(
      Num(p.skipped), math.max(0, math.ceil(p.retryAt - now)), p.attempt), 1
  end
  return "", nil
end

local function UpdateProgress(bar)
  local p = ns.flipProgress
  bar:SetShown(p ~= nil)
  if not p then return end
  local text, fill = ProgressText(p)
  bar.label:SetText(text)
  bar:SetValue(fill or 0)
  if p.phase == "loading" then bar:SetStatusBarColor(0.9, 0.7, 0.1) else bar:SetStatusBarColor(0.2, 0.55, 1) end
end

local function CreateProgressBar(parent, anchor)
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetSize(420, 18)
  bar:SetPoint("LEFT", anchor, "RIGHT", 10, 0)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0, 1)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.5)
  bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.label:SetPoint("CENTER")
  -- Poll the scan state while visible: elapsed times tick even without game events.
  local acc = 0
  bar:SetScript("OnUpdate", function(self, elapsed)
    acc = acc + elapsed
    if acc >= 0.25 then
      acc = 0
      UpdateProgress(self)
    end
  end)
  bar:Hide()
  return bar
end

---------------------------------------------------------------------------
-- Tab
---------------------------------------------------------------------------
local function Build(panel)
  local fullScan = UI.Button(panel, "Full scan", 100, function() ns.StartFullScan() end, "Full AH scan",
    "Downloads every AH listing and looks for items below vendor price. Must be at the AH. "
    .. "The AH allows one full scan every 15 minutes, shared with Auctionator.")
  fullScan:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 12, -8)
  panel.progress = CreateProgressBar(panel, fullScan)
  -- The bar only polls while visible; check right away when the panel opens, in case a scan is running.
  panel:SetScript("OnShow", function() UpdateProgress(panel.progress) end)
end

local function EmptyText(f)
  if ns.fullScanPending then return "Full scan requested, waiting for the auction house..." end
  if ns.flipScanRunning then return "Reading listings..." end
  if #f.items > 0 then return "" end
  if f.scannedAt then return "No listings below vendor price in the last full scan." end
  if ns.lastScanIncremental then
    return "Auctionator's last scan was incremental, which doesn't include individual listings.\n"
      .. "Click Full scan below, or tick 'Use alternate slower scan mode by default'\nin Auctionator's Advanced settings."
  end
  local msg = "No full scan yet.\nAt the auction house, click Full scan below."
  if not ns.ahOpen then msg = msg .. "\n(The auction house is closed.)" end
  return msg
end

local function Refresh(panel)
  local f = ns.flips
  UI.SetRows(panel, f.items)
  panel.empty:SetText(EmptyText(f))
  UpdateProgress(panel.progress)

  if not f.scannedAt then return "" end
  local total = 0
  for _, e in ipairs(f.items) do total = total + e.profit end
  return ("%d flips  |  %s total  |  scanned %d min ago"):format(#f.items, ns.ProfitMoney(total), MinutesAgo(f.scannedAt))
end

UI.RegisterTab({
  key = "flips", label = "Vendor flips", buttonWidth = 110,
  columns = COLUMNS, initRow = InitRow,
  Build = Build,
  Refresh = Refresh,
  OnRefreshButton = function()
    if not ns.ScanReplicateForFlips(true) then
      ns.Print("no full scan data to read. At the AH, click Full scan.")
    end
  end,
  OnShoppingList = function() ns.CreateFlipsShoppingList() end,
  shoppingTip = "Creates the 'Money Talks Forever Flips' list: every flip item, capped at the highest price that still "
    .. "profits. Buy every listing up to the cap, then sell to any vendor.",
})
