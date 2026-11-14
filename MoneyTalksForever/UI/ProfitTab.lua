-- Money Talks Forever: Profit tab - "profit so far" per session, day and all time, and a per-item breakdown.
local _, ns = ...
local UI = ns.UI
local C, Colorize, Money, ProfitMoney = ns.COLOR, ns.Colorize, ns.Money, ns.ProfitMoney

local SUMMARY_HEIGHT = 104
local COLUMNS = {
  { key = "item",   label = "Item (all time)", width = 250, justify = "LEFT" },
  { key = "kind",   label = "Type",            width = 70,  justify = "LEFT" },
  { key = "qty",    label = "Sold",            width = 70,  justify = "RIGHT" },
  { key = "via",    label = "Via",             width = 70,  justify = "LEFT" },
  { key = "earned", label = "Earned",          width = 120, justify = "RIGHT" },
  { key = "cost",   label = "Cost",            width = 120, justify = "RIGHT" },
  { key = "profit", label = "Profit",          width = 120, justify = "RIGHT" },
}

local PERIODS = { { key = "session", label = "This session" }, { key = "today", label = "Today" }, { key = "all", label = "All time" } }
local KINDS = { { key = "crafts", label = "Crafts" }, { key = "flips", label = "Flips" }, { key = "total", label = "Total" } }

local RESET_POPUP = "MONEYTALKSFOREVER_RESET_LEDGER"
StaticPopupDialogs[RESET_POPUP] = {
  text = "Reset Money Talks Forever's profit history for this character?",
  button1 = YES, button2 = NO,
  OnAccept = function() ns.ResetLedger() end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

---------------------------------------------------------------------------
-- Per-item rows
---------------------------------------------------------------------------
local function ItemTooltip(row)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(row.data.itemID)
  GameTooltip:Show()
end

local function SoldVia(it)
  local ah, vendor = (it.ahQty or 0) > 0, (it.vendorQty or 0) > 0
  if ah and vendor then return "both" end
  if ah then return Colorize("AH", C.GOLD) end
  return vendor and "vendor" or ""
end

local function InitRow(row, it)
  if not row.cells then UI.BuildCells(row, COLUMNS, ItemTooltip) end
  local cells = row.cells
  row.data = it
  local info = ns.ItemInfo(it.itemID)
  row.icon:SetTexture(info and info.icon or UI.QUESTION_MARK_ICON)
  cells.item:SetText(info and info.link or ("item:" .. it.itemID))
  cells.kind:SetText(it.kind == "crafts" and Colorize("craft", C.BLUE) or Colorize("flip", C.GOLD))
  cells.qty:SetText(it.qty)
  cells.via:SetText(SoldVia(it))
  cells.earned:SetText(Money(it.earned))
  cells.cost:SetText(Money(it.cost))
  cells.profit:SetText(ProfitMoney(it.earned - it.cost))
end

---------------------------------------------------------------------------
-- Summary block: Crafts / Flips / Total x session / today / all time
---------------------------------------------------------------------------
local function PeriodBucket(key)
  if key == "session" then return ns.session end
  local L = ns.Ledger()
  if key == "today" then return L.days[date("%Y-%m-%d")] or ns.NewLedgerBucket() end
  return L.all
end

-- Sums the fields of the bucket's kinds ("total" = crafts + flips).
local function Totals(bucket, kind)
  local t = { earned = 0, cost = 0, qty = 0, estimated = 0, ahQty = 0, ahEarned = 0, deposits = 0 }
  for _, k in ipairs(kind == "total" and { "crafts", "flips" } or { kind }) do
    for field in pairs(t) do t[field] = t[field] + (bucket[k][field] or 0) end
  end
  return t
end

local function CellTooltip(cell)
  local t = Totals(PeriodBucket(cell.period), cell.kind)
  GameTooltip:SetOwner(cell, "ANCHOR_TOP")
  GameTooltip:AddLine(cell.label)
  UI.TipPair("Items sold", t.qty)
  UI.TipPair("  to vendors", ("%d for %s"):format(t.qty - t.ahQty, Money(t.earned - t.ahEarned)))
  UI.TipPair("  on the AH (after cut)", ("%d for %s"):format(t.ahQty, Money(t.ahEarned)))
  UI.TipPair("Earned", Money(t.earned))
  UI.TipPair("Cost", Money(t.cost))
  if t.deposits > 0 then UI.TipPair("  of which AH deposits lost", Money(t.deposits)) end
  UI.TipPair("Profit", ProfitMoney(t.earned - t.cost))
  if t.estimated > 0 then
    UI.TipNote(("%s of the cost is estimated: reagents you didn't buy while tracking, valued at market price.")
      :format(Money(t.estimated)))
  end
  GameTooltip:Show()
end

local function CreateSummary(panel)
  local box = CreateFrame("Frame", nil, panel)
  box:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 16, 8)
  box:SetSize(700, SUMMARY_HEIGHT - 8)
  box.cells = {}
  local LABEL_W, CELL_W, ROW = 90, 150, 18
  for i, period in ipairs(PERIODS) do
    local h = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", LABEL_W + (i - 1) * CELL_W, 0)
    h:SetWidth(CELL_W - 10)
    h:SetJustifyH("RIGHT")
    h:SetText(period.label)
  end
  for r, kind in ipairs(KINDS) do
    local font = kind.key == "total" and "GameFontNormal" or "GameFontHighlightSmall"
    local l = box:CreateFontString(nil, "OVERLAY", font)
    l:SetPoint("TOPLEFT", 0, -r * ROW)
    l:SetText(kind.label)
    for i, period in ipairs(PERIODS) do
      local cell = CreateFrame("Frame", nil, box)
      cell:SetPoint("TOPLEFT", LABEL_W + (i - 1) * CELL_W, -r * ROW)
      cell:SetSize(CELL_W - 10, ROW)
      cell:EnableMouse(true)
      cell.period, cell.kind = period.key, kind.key
      cell.label = kind.label .. " - " .. period.label
      cell.text = cell:CreateFontString(nil, "OVERLAY", font)
      cell.text:SetAllPoints()
      cell.text:SetJustifyH("RIGHT")
      cell:SetScript("OnEnter", CellTooltip)
      cell:SetScript("OnLeave", GameTooltip_Hide)
      table.insert(box.cells, cell)
    end
  end
  box.info = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  box.info:SetPoint("TOPLEFT", 0, -4 * ROW - 6)
  box.info:SetJustifyH("LEFT")
  panel.summaryBox = box
end

local function Duration(seconds)
  local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
  return h > 0 and ("%dh %dm"):format(h, m) or ("%dm"):format(m)
end

local function InfoLine()
  local parts = {}
  if ns.sessionStart then
    local secs = math.max(60, GetTime() - ns.sessionStart)
    table.insert(parts, ("Session %s: %s/hour"):format(Duration(secs), ProfitMoney(ns.BucketProfit(ns.session) * 3600 / secs)))
  end
  local value, n = ns.LedgerStockValue()
  if n > 0 then table.insert(parts, ("Unsold: %d item(s) bought/crafted for %s"):format(n, Money(value))) end
  table.insert(parts, "Tracking since " .. date("%Y-%m-%d", ns.Ledger().since))
  return table.concat(parts, "   |   ")
end

---------------------------------------------------------------------------
-- Tab
---------------------------------------------------------------------------
local function Build(panel)
  CreateSummary(panel)
  local reset = UI.Button(panel, "Reset", 80, function() StaticPopup_Show(RESET_POPUP) end,
    "Reset profit history", "Clears this character's tracked purchases, stock and profits.")
  reset:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 12, -8)
end

local function Refresh(panel)
  local box = panel.summaryBox
  for _, cell in ipairs(box.cells) do
    local t = Totals(PeriodBucket(cell.period), cell.kind)
    cell.text:SetText(ProfitMoney(t.earned - t.cost))
  end
  box.info:SetText(InfoLine())

  local list = {}
  for itemID, it in pairs(ns.Ledger().items) do
    table.insert(list, { itemID = itemID, kind = it.kind, qty = it.qty, earned = it.earned, cost = it.cost,
      ahQty = it.ahQty, vendorQty = it.vendorQty })
  end
  table.sort(list, function(a, b)
    local pa, pb = a.earned - a.cost, b.earned - b.cost
    if pa ~= pb then return pa > pb end
    return a.itemID < b.itemID
  end)
  UI.SetRows(panel, list)
  panel.empty:SetText(#list == 0 and
    "Nothing sold yet.\nBuy reagents or flips on the AH, craft, and sell to a vendor or on the AH:\nprofits show up here."
    or "")
  return ""
end

UI.RegisterTab({
  key = "profit", label = "Profit", buttonWidth = 90,
  columns = COLUMNS, initRow = InitRow, top = -56 - SUMMARY_HEIGHT,
  Build = Build,
  Refresh = Refresh,
  OnRefreshButton = function() ns.RefreshUI() end,
})
