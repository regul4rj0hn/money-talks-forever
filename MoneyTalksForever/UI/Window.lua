-- Money Talks Forever: the main window. Built on first use from the tabs registered in the UI/*Tab.lua files.
-- Laid out like the game's professions window: a round portrait top left, the tab's title and a header line,
-- the tab's content, buttons along the bottom edge, and one icon tab per tab on the right edge.
local _, ns = ...
local UI = ns.UI

local FRAME_NAME = "MoneyTalksForeverFrame"
local WIDTH_PAD, HEIGHT = 18, 480
local SIDE_TAB_BG = "Interface\\SpellBook\\SpellBook-SkillLineTab"
local window

local function CurrentTab()
  return UI.tabs[ns.Settings().tab] or UI.tabs[1]
end

-- The standard portrait window; a plain window with an inset on clients without that template.
local function CreateBaseFrame()
  local ok, w = pcall(CreateFrame, "Frame", FRAME_NAME, UIParent, "ButtonFrameTemplate")
  if ok and w and w.SetTitle then return w end
  if ok and w then w:Hide() end
  w = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
  local title = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  w.SetTitle = function(_, text) title:SetText(text) end
  return w
end

-- An icon tab on the window's right edge, like the profession tabs.
local function CreateSideTab(w, tab, index)
  local b = CreateFrame("CheckButton", nil, w)
  b:SetSize(32, 32)
  b:SetPoint("TOPLEFT", w, "TOPRIGHT", 0, -48 - (index - 1) * 48)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(SIDE_TAB_BG)
  bg:SetSize(64, 64)
  bg:SetPoint("TOPLEFT", -3, 11)
  b:SetNormalTexture(tab.icon)
  -- Both glows are drawn additively on top of the icon; as plain textures their black background hides it.
  for _, glow in ipairs({ { "SetHighlightTexture", "Interface\\Buttons\\ButtonHilight-Square", "HIGHLIGHT" },
                          { "SetCheckedTexture", "Interface\\Buttons\\CheckButtonHilight", "OVERLAY" } }) do
    local t = b:CreateTexture(nil, glow[3])
    t:SetAllPoints()
    t:SetTexture(glow[2])
    t:SetBlendMode("ADD")
    b[glow[1]](b, t)
  end
  b.tabKey = tab.key
  b:SetScript("OnClick", function() ns.ShowTab(tab.key) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(tab.label)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function CreateWindow()
  local width = 0
  for _, tab in ipairs(UI.tabs) do
    if tab.columns then width = math.max(width, UI.TableWidth(tab.columns)) end
  end

  local w = CreateBaseFrame()
  w:SetSize(width + WIDTH_PAD, HEIGHT)
  w:SetPoint("CENTER")
  w:SetMovable(true)
  w:EnableMouse(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", w.StartMoving)
  w:SetScript("OnDragStop", w.StopMovingOrSizing)
  w:SetFrameStrata("HIGH")
  w:SetClampedToScreen(true)
  w:Hide()
  tinsert(UISpecialFrames, FRAME_NAME) -- close with Escape

  -- Same place as the inset of the portrait template, also on the fallback frame.
  if w.Inset then
    w.Inset:ClearAllPoints()
    w.Inset:SetPoint("TOPLEFT", 4, -60)
    w.Inset:SetPoint("BOTTOMRIGHT", -6, 32)
  end
  local content = CreateFrame("Frame", nil, w)
  content:SetPoint("TOPLEFT", 8, -64)
  content:SetPoint("BOTTOMRIGHT", -10, 36)

  -- Header line under the title, right of the portrait.
  w.summary = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  w.summary:SetPoint("TOPLEFT", 70, -36)
  w.summary:SetPoint("RIGHT", -16, 0)
  w.summary:SetJustifyH("LEFT")
  w.summary:SetWordWrap(false)

  -- Bottom button bar; tabs put their own controls on its left.
  local footer = CreateFrame("Frame", nil, w)
  footer:SetPoint("BOTTOMLEFT", 12, 6)
  footer:SetPoint("BOTTOMRIGHT", -12, 6)
  footer:SetHeight(22)

  local refresh = UI.Button(footer, "Refresh", 90, function() CurrentTab().OnRefreshButton() end)
  refresh:SetPoint("RIGHT")
  w.shopButton = UI.Button(footer, "Shopping list", 110, function()
    local tab = CurrentTab()
    if tab.OnShoppingList then tab.OnShoppingList() end
  end)
  w.shopButton:SetPoint("RIGHT", refresh, "LEFT", -6, 0)
  w.shopButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Auctionator shopping list")
    GameTooltip:AddLine(CurrentTab().shoppingTip or "", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  w.shopButton:SetScript("OnLeave", GameTooltip_Hide)

  -- One side tab and one panel per registered tab, in registration order.
  w.sideTabs, w.panels = {}, {}
  for i, tab in ipairs(UI.tabs) do
    w.sideTabs[tab.key] = CreateSideTab(w, tab, i)
    local panel
    if tab.columns then
      panel = UI.CreateTable(content, tab.columns, tab.initRow)
    else
      panel = CreateFrame("Frame", nil, content)
      panel:SetAllPoints()
    end
    panel.footer = footer
    if tab.Build then tab.Build(panel) end
    w.panels[tab.key] = panel
  end

  w:SetScript("OnShow", function()
    ns.Evaluate()
    ns.RefreshUI()
  end)
  return w
end

function ns.RefreshUI()
  if not window or not window:IsShown() then return end
  local current = CurrentTab()
  for key, panel in pairs(window.panels) do panel:SetShown(key == current.key) end
  for key, b in pairs(window.sideTabs) do b:SetChecked(key == current.key) end
  window:SetTitle(current.title or current.label)
  if window.SetPortraitToAsset then window:SetPortraitToAsset(current.icon) end
  -- Tables sit in the inset; tabs without one (the overview) draw their own boxes.
  if window.Inset then window.Inset:SetShown(current.columns ~= nil) end
  window.shopButton:SetShown(current.OnShoppingList ~= nil)
  window.summary:SetText(current.Refresh(window.panels[current.key]) or "")
end

function ns.ShowTab(key)
  ns.Settings().tab = key
  window = window or CreateWindow()
  if window:IsShown() then ns.RefreshUI() else window:Show() end
end

function ns.ToggleUI()
  window = window or CreateWindow()
  window:SetShown(not window:IsShown())
end
