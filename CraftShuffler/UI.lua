-- CraftShuffler: results window.
local _, ns = ...

local ROW_H = 20
local COLS = {
  { key = "item",   label = "Crafted item", width = 250, justify = "LEFT" },
  { key = "prof",   label = "Profession",   width = 90,  justify = "LEFT" },
  { key = "cost",   label = "Reagent cost", width = 110, justify = "RIGHT" },
  { key = "vendor", label = "Vendor value", width = 110, justify = "RIGHT" },
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
  for _, b in ipairs(d.breakdown or {}) do
    local right = b.total and (ns.Money(b.total) .. (b.source == "vendor" and " |cff999999(vendor)|r" or ""))
      or "|cffff9900no price|r"
    GameTooltip:AddDoubleLine(("  %dx %s"):format(b.qty, b.name or "?"), right, 0.9, 0.9, 0.9, 1, 1, 1)
  end
  GameTooltip:AddLine("Shift-click to link in chat.", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

local function InitRow(row, d)
  if not row.cells then
    row:SetHeight(ROW_H)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 2, ROW_H - 2)
    row.icon:SetPoint("LEFT", 2, 0)

    row.cells = {}
    local x = 0
    for i, col in ipairs(COLS) do
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      local inset = (i == 1) and (ROW_H + 4) or 0
      fs:SetPoint("LEFT", x + inset, 0)
      fs:SetWidth(col.width - inset - 6)
      fs:SetJustifyH(col.justify)
      fs:SetWordWrap(false)
      row.cells[col.key] = fs
      x = x + col.width
    end

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
      if IsModifiedClick("CHATLINK") and self.data and self.data.itemLink then
        ChatEdit_InsertLink(self.data.itemLink)
      end
    end)
  end

  row.data = d
  row.icon:SetTexture(d.icon or 134400) -- question mark fallback
  row.cells.item:SetText(d.itemLink or d.name or ("item:" .. d.itemID))
  row.cells.prof:SetText(d.profession or "")
  row.cells.cost:SetText(d.status == ns.STATUS.MISSING and "|cffff9900?|r" or ns.Money(d.cost))
  row.cells.vendor:SetText(ns.Money(d.vendorValue))
  if d.profit then
    local color = d.profit > 0 and "|cff00ff00" or "|cffff4040"
    row.cells.profit:SetText(color .. ns.Money(d.profit) .. "|r")
  else
    row.cells.profit:SetText(ns.Money(nil))
  end
  row.cells.status:SetText(STATUS_TEXT[d.status] or "")
end

local function CreateUI()
  local width = 30
  for _, c in ipairs(COLS) do width = width + c.width end

  frame = CreateFrame("Frame", "CraftShufflerFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(width + 20, 460)
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
  frame.title:SetText("CraftShuffler")

  -- Column headers
  local x = 16
  for _, col in ipairs(COLS) do
    local h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", x, -34)
    h:SetWidth(col.width - 6)
    h:SetJustifyH(col.justify)
    h:SetText(col.label)
    x = x + col.width
  end

  local scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", 12, -50)
  scrollBox:SetPoint("BOTTOMRIGHT", -30, 40)
  local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_H)
  view:SetElementInitializer("Button", InitRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
  frame.scrollBox = scrollBox

  -- Footer: filter checkbox, refresh button, summary
  local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("BOTTOMLEFT", 12, 10)
  cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb.text:SetText("Only show Shuffle me!")
  cb:SetScript("OnClick", function(self)
    ns.Settings().onlyShuffle = self:GetChecked() and true or false
    ns.RefreshUI()
  end)
  frame.onlyShuffle = cb

  local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refresh:SetSize(90, 22)
  refresh:SetPoint("BOTTOMRIGHT", -12, 10)
  refresh:SetText("Refresh")
  refresh:SetScript("OnClick", function()
    ns.ScanOpenProfession()
    ns.Evaluate()
  end)

  frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.summary:SetPoint("RIGHT", refresh, "LEFT", -10, 0)
  frame.summary:SetJustifyH("RIGHT")

  frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
  frame.empty:SetPoint("CENTER", scrollBox, "CENTER")
  frame.empty:SetWidth(width - 80)

  frame:SetScript("OnShow", function() ns.Evaluate() end)
end

function ns.RefreshUI()
  if not frame or not frame:IsShown() then return end
  local onlyShuffle = ns.Settings().onlyShuffle
  frame.onlyShuffle:SetChecked(onlyShuffle)

  local list, counts = {}, { 0, 0, 0, 0 }
  for _, r in ipairs(ns.results) do
    counts[r.status] = counts[r.status] + 1
    if not onlyShuffle or r.status == ns.STATUS.SHUFFLE then table.insert(list, r) end
  end
  frame.scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)

  frame.summary:SetText(("|cff00ff00%d shuffle|r  |  %d no profit  |  |cffff9900%d no price|r"):format(
    counts[1], counts[2], counts[3]))

  if #list > 0 then
    frame.empty:SetText("")
  elseif #ns.results == 0 then
    frame.empty:SetText("No recipes recorded yet.\nOpen each of your profession windows once.")
  elseif not ns.AuctionatorAPI() then
    frame.empty:SetText("Auctionator is not loaded.")
  else
    frame.empty:SetText("Nothing to shuffle right now.\nRun a full Auctionator scan at the auction house.")
  end
end

function ns.ToggleUI()
  if not frame then CreateUI() end
  frame:SetShown(not frame:IsShown())
end
