-- Money Talks Forever: shared UI building blocks and the tab registry.
--
-- A tab is registered once with ns.UI.RegisterTab{...} and the window (Window.lua) builds everything from it:
--   key, label, buttonWidth     identity and tab button
--   columns, initRow, top       the scrolling table: column specs, row initializer, optional top offset
--   Build(panel)                optional: extra widgets for the tab (footer controls, summary block)
--   Refresh(panel) -> text      redraw the tab; returns the footer summary text
--   OnRefreshButton()           what the footer's Refresh button does on this tab
--   OnShoppingList(), shoppingTip   optional: the footer's Shopping list button (hidden when absent)
local _, ns = ...

local UI = { tabs = {}, ROW_H = 20, QUESTION_MARK_ICON = 134400 }
ns.UI = UI

function UI.RegisterTab(def)
  table.insert(UI.tabs, def)
  UI.tabs[def.key] = def
end

function UI.TableWidth(cols)
  local w = 30
  for _, c in ipairs(cols) do w = w + c.width end
  return w
end

-- Creates the row's icon + one font string per column, once per recycled row frame.
-- Shift-clicking a row links its item in chat.
function UI.BuildCells(row, cols, onEnter)
  local ROW_H = UI.ROW_H
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

-- A panel with column headers and a scrolling list, filling the window between the tabs and the footer.
-- panel.scrollBox takes a data provider; panel.empty is the centered "nothing here" text.
function UI.CreateTable(parent, cols, initializer, top)
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetPoint("TOPLEFT", 0, top or -56)
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
  view:SetElementExtent(UI.ROW_H)
  view:SetElementInitializer("Button", initializer)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
  panel.scrollBox = scrollBox

  panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
  panel.empty:SetPoint("CENTER", scrollBox, "CENTER")
  panel.empty:SetWidth(UI.TableWidth(cols) - 80)
  return panel
end

function UI.SetRows(panel, list)
  panel.scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)
end

-- A standard button with an optional hover tooltip.
function UI.Button(parent, text, width, onClick, tipTitle, tipText)
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

-- Tooltip line helpers: label on the left in light grey, value on the right in white.
function UI.TipPair(left, right)
  GameTooltip:AddDoubleLine(left, right, 0.9, 0.9, 0.9, 1, 1, 1)
end

function UI.TipNote(text)
  GameTooltip:AddLine(text, 0.6, 0.6, 0.6, true)
end
