-- Money Talks Forever: Profit tab - every item sold, all time. The totals per session, day and all time are on the
-- Overview tab.
local _, ns = ...
local UI = ns.UI
local C, Colorize, Money, ProfitMoney = ns.COLOR, ns.Colorize, ns.Money, ns.ProfitMoney

local COLUMNS = {
  { key = "item",   label = "Item (all time)", width = 250, justify = "LEFT" },
  { key = "kind",   label = "Type",            width = 70,  justify = "LEFT" },
  { key = "qty",    label = "Sold",            width = 70,  justify = "RIGHT" },
  { key = "via",    label = "Via",             width = 70,  justify = "LEFT" },
  { key = "earned", label = "Earned",          width = 120, justify = "RIGHT" },
  { key = "cost",   label = "Cost",            width = 120, justify = "RIGHT" },
  { key = "profit", label = "Profit",          width = 120, justify = "RIGHT" },
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
  row.icon:SetTexture(UI.ItemIcon(it.itemID, info and info.icon))
  cells.item:SetText(info and info.link or ns.ItemName(it.itemID)) -- ItemName asks the server; we redraw on arrival
  cells.kind:SetText(it.kind == "crafts" and Colorize("craft", C.BLUE) or Colorize("flip", C.GOLD))
  cells.qty:SetText(it.qty)
  cells.via:SetText(SoldVia(it))
  cells.earned:SetText(Money(it.earned))
  cells.cost:SetText(Money(it.cost))
  cells.profit:SetText(ProfitMoney(it.earned - it.cost))
end

---------------------------------------------------------------------------
-- Tab
---------------------------------------------------------------------------
local function Build(panel)
  UI.ClearAllButton(panel):SetPoint("LEFT", panel.footer, "LEFT", 0, 0)
end

local function Refresh(panel)
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
  return UI.ProfitInfoLine()
end

UI.RegisterTab({
  key = "profit", label = "Profit", title = "Profit by item", icon = "Interface\\Icons\\INV_Misc_Note_01",
  columns = COLUMNS, initRow = InitRow,
  Build = Build,
  Refresh = Refresh,
  OnRefreshButton = function() ns.RefreshUI() end,
})
