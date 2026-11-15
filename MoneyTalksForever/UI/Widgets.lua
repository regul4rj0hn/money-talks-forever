-- Money Talks Forever: shared UI building blocks and the tab registry.
--
-- A tab is registered once with ns.UI.RegisterTab{...} and the window (Window.lua) builds everything from it.
-- Tabs show in registration order (TOC order) as icons on the window's right edge.
--   key, label, icon, title     identity: side tab tooltip and icon, window title (default: label)
--   columns, initRow            optional: a scrolling table with these column specs and row initializer
--   Build(panel)                optional: extra widgets; panel.footer is the window's bottom button bar
--   Refresh(panel) -> text      redraw the tab; returns the text for the header line under the title
--   OnRefreshButton()           what the footer's Refresh button does on this tab
--   OnShoppingList(), shoppingTip   optional: the footer's Shopping list button (hidden when absent)
--   Summary(), EmptyText(), ShowTooltip(row)   optional: reused by the Overview tab
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

-- Hover tooltip: a title and wrapped white text.
local function AttachTooltip(b, title, text)
  if not title then return end
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(title)
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
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

-- A panel with column headers and a scrolling list, filling its parent.
-- panel.scrollBox takes a data provider; panel.empty is the centered "nothing here" text.
function UI.CreateTable(parent, cols, initializer)
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetAllPoints()

  local x = 8
  for _, col in ipairs(cols) do
    local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", x, 0)
    h:SetWidth(col.width - 6)
    h:SetJustifyH(col.justify)
    h:SetText(col.label)
    if col.tip then -- hover the header for what the column means
      local hover = CreateFrame("Frame", nil, panel)
      hover:SetPoint("TOPLEFT", x, 2)
      hover:SetSize(col.width - 6, 16)
      AttachTooltip(hover, col.label, col.tip)
    end
    x = x + col.width
  end

  local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", 4, -16)
  scrollBox:SetPoint("BOTTOMRIGHT", -22, 2)
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

-- Icon for a row's item. Icons saved at scan time can be the "?" placeholder of an item that wasn't loaded yet.
function UI.ItemIcon(itemID, saved)
  local icon = ns.ItemIcon(itemID)
  if icon and icon ~= UI.QUESTION_MARK_ICON then return icon end
  return saved or UI.QUESTION_MARK_ICON
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
  AttachTooltip(b, tipTitle, tipText)
  return b
end

-- A big icon with a gold name and a grey line under it, like the entries of the professions window.
function UI.IconButton(parent, icon, name, sub, onClick, tipTitle, tipText)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(230, 36)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(36, 36)
  b.icon:SetPoint("LEFT")
  b.icon:SetTexture(icon)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(b.icon)
  hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  hl:SetBlendMode("ADD")
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.label:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -3)
  b.label:SetText(name)
  b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.sub:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -3)
  b.sub:SetTextColor(0.7, 0.7, 0.7)
  b.sub:SetText(sub)
  b:SetScript("OnClick", onClick)
  AttachTooltip(b, tipTitle, tipText)
  return b
end

-- A bordered box with a gold title, like the profession boxes of the professions window.
function UI.Section(parent, title)
  local s = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
  s.title = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  s.title:SetPoint("TOPLEFT", 14, -12)
  s.title:SetText(title)
  return s
end

-- Tooltip line helpers: label on the left in light grey, value on the right in white.
function UI.TipPair(left, right)
  GameTooltip:AddDoubleLine(left, right, 0.9, 0.9, 0.9, 1, 1, 1)
end

function UI.TipNote(text)
  GameTooltip:AddLine(text, 0.6, 0.6, 0.6, true)
end
