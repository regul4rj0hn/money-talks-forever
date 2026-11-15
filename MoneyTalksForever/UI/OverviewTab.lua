-- Money Talks Forever: Overview tab - profit so far, and the best crafts and flips right now. Each box has an icon
-- that opens the full list on its own tab, like the professions window.
local _, ns = ...
local UI = ns.UI
local Money, ProfitMoney = ns.Money, ns.ProfitMoney

local TOP_N = 2          -- items shown per box
local PROFIT_H, GAP = 104, 6
local ITEM_COLUMNS = {
  { key = "item",  width = 300, justify = "LEFT" },
  { key = "value", width = 150, justify = "RIGHT" },
}

local PERIODS = { { key = "session", label = "This session" }, { key = "today", label = "Today" }, { key = "all", label = "All time" } }
local KINDS = { { key = "crafts", label = "Crafts" }, { key = "flips", label = "Flips" }, { key = "total", label = "Total" } }

---------------------------------------------------------------------------
-- Clearing profit: this session only, or all of this character's history (also /mtf profit session|reset)
---------------------------------------------------------------------------
local function Popup(name, text, onAccept)
  StaticPopupDialogs[name] = {
    text = text, button1 = YES, button2 = NO, OnAccept = onAccept,
    timeout = 0, whileDead = true, hideOnEscape = true,
  }
end
Popup("MONEYTALKSFOREVER_RESET_SESSION", "Clear this session's profit? Today and all time are kept.",
  function() ns.ResetSession() end)
Popup("MONEYTALKSFOREVER_RESET_LEDGER",
  "Clear all of this character's profit history?\nThis also forgets what you paid for items you still have.",
  function() ns.ResetLedger() end)

function UI.ClearAllButton(parent)
  return UI.Button(parent, "Clear all", 90, function() StaticPopup_Show("MONEYTALKSFOREVER_RESET_LEDGER") end,
    "Clear all profit history", "Clears this character's session, daily and all-time profits, the items sold, "
    .. "and what you paid for items you still have (they are no longer tracked).")
end

---------------------------------------------------------------------------
-- Profit so far: Crafts / Flips / Total x session / today / all time
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

local function CreateProfitGrid(parent)
  local grid = CreateFrame("Frame", nil, parent)
  local LABEL_W, CELL_W, ROW = 90, 150, 18
  grid:SetSize(LABEL_W + #PERIODS * CELL_W, ROW * (#KINDS + 1))
  grid.cells = {}
  for i, period in ipairs(PERIODS) do
    local h = grid:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", LABEL_W + (i - 1) * CELL_W, 0)
    h:SetWidth(CELL_W - 10)
    h:SetJustifyH("RIGHT")
    h:SetText(period.label)
  end
  for r, kind in ipairs(KINDS) do
    local font = kind.key == "total" and "GameFontNormal" or "GameFontHighlightSmall"
    local l = grid:CreateFontString(nil, "OVERLAY", font)
    l:SetPoint("TOPLEFT", 0, -r * ROW)
    l:SetText(kind.label)
    for i, period in ipairs(PERIODS) do
      local cell = CreateFrame("Frame", nil, grid)
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
      table.insert(grid.cells, cell)
    end
  end
  return grid
end

local function Duration(seconds)
  local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
  return h > 0 and ("%dh %dm"):format(h, m) or ("%dm"):format(m)
end

-- A per-hour rate from the first few minutes is mostly noise (one sale looks like a fortune), so it waits.
local MIN_RATE_SECONDS = 600

-- "Session 42m: 25s (36s/hour) | Unsold: ... | Tracking since ...", also the Profit tab's header line.
function UI.ProfitInfoLine()
  local parts = {}
  if ns.sessionStart then
    local secs, profit = GetTime() - ns.sessionStart, ns.BucketProfit(ns.session)
    local text = ("Session %s: %s"):format(Duration(math.max(60, secs)), ProfitMoney(profit))
    if secs >= MIN_RATE_SECONDS then text = text .. (" (%s/hour)"):format(ProfitMoney(profit * 3600 / secs)) end
    table.insert(parts, text)
  end
  local value, n = ns.LedgerStockValue()
  if n > 0 then table.insert(parts, ("Unsold: %d item(s) bought/crafted for %s"):format(n, Money(value))) end
  table.insert(parts, "Tracking since " .. date("%Y-%m-%d", ns.Ledger().since))
  return table.concat(parts, "   |   ")
end

---------------------------------------------------------------------------
-- Boxes
---------------------------------------------------------------------------
-- The icon that opens a tab.
local function OpenTabButton(parent, key, name, sub)
  local tab = UI.tabs[key]
  local b = UI.IconButton(parent, tab.icon, name, sub, function() ns.ShowTab(key) end)
  b.tabKey = key
  b:SetPoint("TOPLEFT", 14, -42)
  return b
end

local function BuildProfitBox(panel)
  local box = UI.Section(panel, "Profit so far")
  box:SetPoint("TOPLEFT")
  box:SetPoint("TOPRIGHT")
  box:SetHeight(PROFIT_H)
  OpenTabButton(box, "profit", "Profit by item", "Every item you sold")
  box.grid = CreateProfitGrid(box)
  box.grid:SetPoint("TOPLEFT", 300, -14)
  panel.profit = box
end

-- One line per top item: icon, link, profit. Hover for the tab's tooltip; click to open the tab.
local function CreateItemLine(box, tab, index)
  local row = CreateFrame("Button", nil, box)
  UI.BuildCells(row, ITEM_COLUMNS, function(self) tab.ShowTooltip(self) end)
  row:SetPoint("TOPLEFT", 14, -112 - (index - 1) * (UI.ROW_H + 4))
  row:SetWidth(UI.TableWidth(ITEM_COLUMNS))
  row.tabKey = tab.key
  row:SetScript("OnClick", function(self)
    local link = self.data and (self.data.itemLink or self.data.link)
    if IsModifiedClick("CHATLINK") and link then ChatEdit_InsertLink(link) else ns.ShowTab(tab.key) end
  end)
  return row
end

-- A box for one feature tab: its status, its best TOP_N items and action buttons along the bottom.
local function BuildFeatureBox(panel, key, name, sub, actions)
  local tab = UI.tabs[key]
  local box = UI.Section(panel, tab.label)
  box.tab = tab
  OpenTabButton(box, key, name, sub)

  box.status = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  box.status:SetPoint("TOPRIGHT", -14, -16)
  box.status:SetJustifyH("RIGHT")

  local best = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  best:SetPoint("TOPLEFT", 14, -94)
  best:SetText("Best right now")

  box.rows = {}
  for i = 1, TOP_N do box.rows[i] = CreateItemLine(box, tab, i) end
  box.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  box.empty:SetPoint("TOPLEFT", 14, -114)
  box.empty:SetPoint("RIGHT", -14, 0)
  box.empty:SetJustifyH("LEFT")

  local prev
  for _, a in ipairs(actions) do
    local b = UI.IconButton(box, a.icon, a.name, a.sub, a.run, a.name, a.tip)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("BOTTOMLEFT", 14, 14) end
    prev = b
  end
  return box
end

local SHOPPING_ICON, SCAN_ICON = "Interface\\Icons\\INV_Scroll_03", "Interface\\Icons\\INV_Misc_Spyglass_02"

local function Build(panel)
  BuildProfitBox(panel)
  local clearSession = UI.Button(panel, "Clear session", 110,
    function() StaticPopup_Show("MONEYTALKSFOREVER_RESET_SESSION") end,
    "Clear session", "Starts this session's profit and gold per hour over. Today and all time are kept.")
  clearSession:SetPoint("LEFT", panel.footer, "LEFT", 0, 0)
  UI.ClearAllButton(panel):SetPoint("LEFT", clearSession, "RIGHT", 6, 0)

  panel.crafts = BuildFeatureBox(panel, "crafts", "All crafts", "Every recorded recipe", {
    { icon = SHOPPING_ICON, name = "Shopping list", sub = "Reagents, with max prices",
      run = function() ns.CreateReagentShoppingList() end, tip = UI.tabs.crafts.shoppingTip },
  })
  panel.crafts:SetPoint("TOPLEFT", 0, -(PROFIT_H + GAP))
  panel.crafts:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -GAP / 2, 0)

  panel.flips = BuildFeatureBox(panel, "flips", "All flips", "AH listings below vendor price", {
    { icon = SCAN_ICON, name = "Full scan", sub = "At the AH, every 15 min",
      run = function() ns.ShowTab("flips"); ns.StartFullScan() end,
      tip = "Downloads every AH listing and looks for items below vendor price. Opens the Flips tab to show progress." },
    { icon = SHOPPING_ICON, name = "Shopping list", sub = "Every flip, with max prices",
      run = function() ns.CreateFlipsShoppingList() end, tip = UI.tabs.flips.shoppingTip },
  })
  panel.flips:SetPoint("TOPLEFT", panel, "TOP", GAP / 2, -(PROFIT_H + GAP))
  panel.flips:SetPoint("BOTTOMRIGHT")
end

local function FillBox(box, list, valueText)
  for i, row in ipairs(box.rows) do
    local d = list[i]
    row.data = d
    row:SetShown(d ~= nil)
    if d then
      row.icon:SetTexture(UI.ItemIcon(d.itemID, d.icon))
      row.cells.item:SetText(d.itemLink or d.link or d.name or ("item:" .. d.itemID))
      row.cells.value:SetText(valueText(d))
    end
  end
  box.empty:SetText(#list == 0 and box.tab.EmptyText() or "")
  box.status:SetText(box.tab.Summary())
end

local function Refresh(panel)
  for _, cell in ipairs(panel.profit.grid.cells) do
    local t = Totals(PeriodBucket(cell.period), cell.kind)
    cell.text:SetText(ProfitMoney(t.earned - t.cost))
  end

  local best = {}
  for _, r in ipairs(ns.results) do -- sorted: profitable first, best profit first
    if not ns.IsProfitable(r) or #best == TOP_N then break end
    table.insert(best, r)
  end
  FillBox(panel.crafts, best, function(r)
    return ProfitMoney(r.bestProfit) .. (r.status == ns.STATUS.LIST and " / craft (AH)" or " / craft")
  end)

  local flips = {}
  for i = 1, math.min(TOP_N, #ns.flips.items) do flips[i] = ns.flips.items[i] end
  FillBox(panel.flips, flips, function(e) return ProfitMoney(e.profit) end)

  return UI.ProfitInfoLine()
end

UI.RegisterTab({
  key = "overview", label = "Overview", title = "Money Talks Forever v" .. ns.VERSION, icon = "Interface\\Icons\\INV_Misc_Coin_02",
  Build = Build,
  Refresh = Refresh,
  OnRefreshButton = function()
    ns.Evaluate()
    ns.RefreshUI()
  end,
})
