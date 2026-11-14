-- Money Talks Forever: the main window. Built on first use from the tabs registered in the UI/*Tab.lua files.
local _, ns = ...
local UI = ns.UI

local FRAME_NAME = "MoneyTalksForeverFrame"
local window

local function CurrentTab()
  return UI.tabs[ns.Settings().tab] or UI.tabs[1]
end

local function CreateWindow()
  local width = 0
  for _, tab in ipairs(UI.tabs) do width = math.max(width, UI.TableWidth(tab.columns)) end

  local w = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
  w:SetSize(width + 20, 480)
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

  w.title = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  w.title:SetPoint("TOP", 0, -5)
  w.title:SetText("Money Talks Forever v" .. ns.VERSION)

  -- One button and one panel per registered tab, in registration order.
  w.tabButtons, w.panels = {}, {}
  local prev
  for _, tab in ipairs(UI.tabs) do
    local b = UI.Button(w, tab.label, tab.buttonWidth or 100, function() ns.ShowTab(tab.key) end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 12, -28) end
    prev = b
    w.tabButtons[tab.key] = b

    local panel = UI.CreateTable(w, tab.columns, tab.initRow, tab.top)
    if tab.Build then tab.Build(panel) end
    w.panels[tab.key] = panel
  end

  -- Footer: these act on the current tab.
  local refresh = UI.Button(w, "Refresh", 90, function() CurrentTab().OnRefreshButton() end)
  refresh:SetPoint("BOTTOMRIGHT", -12, 10)

  w.shopButton = UI.Button(w, "Shopping list", 110, function()
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

  w.summary = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  w.summary:SetPoint("RIGHT", w.shopButton, "LEFT", -10, 0)
  w.summary:SetJustifyH("RIGHT")

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
  for key, button in pairs(window.tabButtons) do button:SetEnabled(key ~= current.key) end -- active tab looks pressed
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
