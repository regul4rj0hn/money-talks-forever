-- Mocked WoW API for offline tests. Returns the test kit `T`:
--   T.ns       the addon namespace (all addon files from the TOC are loaded, in TOC order)
--   T.W        mock world state: items, ah, vendor, recipes, money, bag, inbox, replicate, ...
--   T.Fire(event, ...)   deliver an event to every frame registered for it, like the game does
--   T.flush()            run all pending C_Timer callbacks (delays are ignored)
--   T.RunNextTimer()     run only the oldest pending callback
--   T.Setup(scenario)    fresh saved data + record the scenario's recipes
--   T.ByName()           evaluate and index result rows by recipe name
--   T.LINEN              shared tailoring fixture
--   T.Test(name, fn)     register a test
local ADDON = "MoneyTalksForever"

local T = { tests = {} }
local W = {
  items = {}, ah = {}, vendor = {}, recipes = {},
  money = 0, bag = {}, inbox = {}, replicate = {}, replicateRequests = 0,
  auctionsByID = {}, createdLists = {}, popups = {},
}
T.W = W

---------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------
local timers = {}
C_Timer = {
  After = function(_, fn) table.insert(timers, fn) end,
  NewTicker = function(_, fn) table.insert(timers, fn); return { Cancel = function() end } end,
}
function T.flush()
  local guard = 0
  while #timers > 0 do
    table.remove(timers, 1)()
    guard = guard + 1
    assert(guard < 10000, "timers keep rescheduling themselves")
  end
end
function T.RunNextTimer() table.remove(timers, 1)() end

---------------------------------------------------------------------------
-- Frames and widgets: any unknown method is a no-op, the ones the addon relies on behave like the game.
---------------------------------------------------------------------------
local registry = {} -- frames that registered events

local Widget = {}
local WidgetMT = { __index = function(_, k) return Widget[k] or function() end end }

local function NewWidget(kind)
  return setmetatable({ kind = kind, scripts = {}, events = {}, shown = true }, WidgetMT)
end
T.NewWidget = NewWidget

function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:GetScript(name) return self.scripts[name] end
function Widget:HookScript(name, fn)
  local old = self.scripts[name]
  self.scripts[name] = function(...) if old then old(...) end fn(...) end
end
function Widget:HasScript() return true end
function Widget:RegisterEvent(e) self.events[e] = true; registry[self] = true end
function Widget:UnregisterEvent(e) self.events[e] = nil end
function Widget:Show()
  local was = self.shown
  self.shown = true
  if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Widget:Hide() self.shown = false end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:CreateFontString() return NewWidget("FontString") end
function Widget:CreateTexture() return NewWidget("Texture") end
function Widget:SetText(t) self.text = t end
function Widget:GetText() return self.text end
function Widget:SetChecked(v) self.checked = v end
function Widget:GetChecked() return self.checked end
function Widget:SetEnabled(v) self.enabled = v end
function Widget:SetValue(v) self.value = v end
-- Scroll boxes draw every element with the view's initializer, so row code runs in tests.
function Widget:SetDataProvider(provider)
  self.provider = provider
  self.rows = self.rows or {}
  local init = self.view and self.view.initializer
  if not init then return end
  for i, elem in ipairs(provider.list) do
    self.rows[i] = self.rows[i] or NewWidget("Button")
    init(self.rows[i], elem)
  end
end

function CreateFrame(kind) return NewWidget(kind) end

function T.Fire(event, ...)
  for frame in pairs(registry) do
    if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
  end
end

UIParent = NewWidget("Frame")
UISpecialFrames = {}
StaticPopupDialogs = {}
StaticPopup_Show = function(name) table.insert(W.popups, name) end
YES, NO = "Yes", "No"
GameTooltip = NewWidget("GameTooltip")
function GameTooltip:SetOwner() self.lines = {} end
function GameTooltip:AddLine(text) table.insert(self.lines, tostring(text)) end
function GameTooltip:AddDoubleLine(l, r) table.insert(self.lines, tostring(l) .. " | " .. tostring(r)) end
GameTooltip_Hide = function() end
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) T.tooltipPostCall = fn end }
CreateDataProvider = function(list) return { list = list } end
CreateScrollBoxListLinearView = function()
  local view = NewWidget("View")
  function view:SetElementInitializer(_, fn) self.initializer = fn end
  return view
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, _, view) box.view = view end }
ScrollBoxConstants = { RetainScrollPosition = 1 }
BreakUpLargeNumbers = tostring
IsModifiedClick = function() return false end
ChatEdit_InsertLink = function() end
tinsert = table.insert
NUM_BAG_SLOTS = 4

---------------------------------------------------------------------------
-- Game data
---------------------------------------------------------------------------
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end
GetMoneyString = function(c) return c .. "c" end
GetMoney = function() return W.money end
SlashCmdList = {}
time = os.time
GetTime = os.clock
date = os.date
Enum = {
  ItemBind = { None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3 },
  CraftingReagentType = { Basic = 1 },
  TooltipDataType = { Item = 0 },
}

-- Hooks: wrap the table function so the hook runs after it, like WoW's hooksecurefunc.
function hooksecurefunc(t, name, hook)
  local orig = t[name]
  t[name] = function(...) local r = orig(...); hook(...); return r end
end

-- W.items[id] = { name, sellPrice, bindType [, equipLoc] }
C_Item = {
  GetItemInfo = function(id)
    local i = W.items[id]
    if not i then return nil end
    -- name, link, quality, ilvl, minLevel, type, subType, stack, equipLoc, icon, sellPrice, class, subclass, bindType
    return i[1], "[" .. i[1] .. "]", 1, 1, 1, "", "", 1, i[4] or "", 1, i[2], 0, 0, i[3]
  end,
  GetItemInfoInstant = function(id)
    local i = W.items[id]
    return id, "", "", i and i[4] or "", 1, 0, 0
  end,
  RequestLoadItemDataByID = function() end,
  GetItemNameByID = function(id) return W.items[id] and W.items[id][1] end,
  GetItemID = function(location) return location.itemID end,
}
C_CurrencyInfo = { GetCurrencyInfo = function() return nil end }

-- Mailbox: { subject, money, invoice = {type, itemName, bid, deposit, consignment, count}, item = {name, id, count} }
GetInboxNumItems = function() return #W.inbox end
GetInboxHeaderInfo = function(i)
  local m = W.inbox[i]
  return nil, nil, "Auction House", m.subject, m.money or 0, 0, 30, m.item and 1 or nil
end
GetInboxInvoiceInfo = function(i)
  local v = W.inbox[i].invoice
  if not v then return nil end
  return v.type, v.itemName, nil, v.bid, v.bid, v.deposit, v.consignment, 0, 0, 0, v.count, true
end
GetInboxItem = function(i)
  local it = W.inbox[i].item
  if not it then return nil end
  return it.name, it.id, nil, it.count
end
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"

-- Bags: one bag holding W.bag = { [itemID] = count }
local function SortedBagIDs()
  local ids = {}
  for id in pairs(W.bag) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end
C_Container = {
  GetContainerNumSlots = function(b) return b == 0 and #SortedBagIDs() or 0 end,
  GetContainerItemInfo = function(_, slot)
    local id = SortedBagIDs()[slot]
    return id and { itemID = id, stackCount = W.bag[id] } or nil
  end,
  GetContainerItemID = function(_, slot) return SortedBagIDs()[slot] end,
}

-- Replicate (full scan) listings: W.replicate = { { itemID, count, buyout, owner }, ... }
C_AuctionHouse = {
  ReplicateItems = function() W.replicateRequests = W.replicateRequests + 1 end,
  StartCommoditiesPurchase = function() end,
  ConfirmCommoditiesPurchase = function() end,
  PlaceBid = function() end,
  PostItem = function() return true end,
  PostCommodity = function() return true end,
  GetAuctionInfoByID = function(id) return W.auctionsByID[id] end,
  GetNumReplicateItems = function() return #W.replicate end,
  GetReplicateItemInfo = function(i) -- 0-based, like the real API
    local l = W.replicate[i + 1]
    return "name", 1, l[2], 1, true, 1, 0, 0, 0, l[3], 0, false, nil, l[4], nil, 0, l[1], true
  end,
  GetReplicateItemLink = function(i)
    W.replicateLinkCalls = (W.replicateLinkCalls or 0) + 1
    return W.replicate[i + 1][1] -- the item ID works as a "link" for the GetItemInfo mock
  end,
}

Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, id) return W.ah[id] end,
  GetVendorPriceByItemID = function(_, id) return W.vendor[id] end,
  -- Same shape as Auctionator's real search strings; maxPrice is stored in gold.
  ConvertToSearchString = function(_, t)
    return ('"%s";;;;;;;;%s;;;;'):format(t.searchString, t.maxPrice and tostring(t.maxPrice / 10000) or "")
  end,
  CreateShoppingList = function(_, name, strings) W.createdLists[name] = strings end,
} } }

C_TradeSkillUI = {
  IsTradeSkillReady = function() return true end,
  GetBaseProfessionInfo = function() return { professionName = "Tailoring" } end,
  GetAllRecipeIDs = function()
    local t = {}
    for id in pairs(W.recipes) do t[#t + 1] = id end
    table.sort(t)
    return t
  end,
  GetRecipeInfo = function(id) return { name = W.recipes[id].name, learned = true } end,
  GetRecipeSchematic = function(id)
    local r, slots = W.recipes[id], {}
    for _, g in ipairs(r.reagents) do
      table.insert(slots, { required = true, quantityRequired = g[2], reagents = { { itemID = g[1] } } })
    end
    return { outputItemID = r.out, quantityMin = r.qty or 1, quantityMax = r.qty or 1, reagentSlotSchematics = slots }
  end,
}

---------------------------------------------------------------------------
-- Load the addon exactly as the TOC lists it
---------------------------------------------------------------------------
local ns = {}
T.ns = ns
for raw in io.lines(ADDON .. "/" .. ADDON .. ".toc") do
  local line = raw:gsub("\r", ""):match("^%s*(.-)%s*$")
  if line ~= "" and not line:match("^#") then
    local path = ADDON .. "/" .. line:gsub("\\", "/")
    assert(loadfile(path))(ADDON, ns)
  end
end
print = function() end -- silence addon chat output

---------------------------------------------------------------------------
-- Helpers for tests
---------------------------------------------------------------------------
function T.Test(name, fn)
  assert(not T.tests[name], "duplicate test name: " .. name)
  T.tests[name] = fn
end

function T.Setup(scenario)
  W.items, W.ah, W.vendor, W.recipes = scenario.items, scenario.ah or {}, scenario.vendor or {}, scenario.recipes
  MoneyTalksForeverDB = { chars = {}, deposits = {}, flips = {}, ledger = {}, settings = {
    useVendorReagentPrice = true, craftReagents = true, includeSoulbound = false, minProfit = 1, ahDuration = 1,
    flipMinProfit = 1, chatAlert = true } }
  ns.ScanOpenProfession()
  T.flush()
end

function T.ByName()
  ns.Evaluate()
  local by = {}
  for _, r in ipairs(ns.results) do by[r.name] = r end
  return by
end

-- Tailoring: vendor prices Linen Cloth 1, Bolt 10, Shirt 200, Pants 500; recipes Bolt = 2 cloth, Shirt = 3 bolts
T.LINEN = {
  items = { [2589] = { "Linen Cloth", 1, 0 }, [2996] = { "Bolt of Linen Cloth", 10, 0 }, [2568] = { "Linen Shirt", 200, 2 },
            [300] = { "Pants", 500, 2 }, [400] = { "Thread", 0, 0 } },
  ah = nil, -- set per test
  recipes = {
    [1] = { name = "Bolt", out = 2996, reagents = { { 2589, 2 } } },
    [2] = { name = "Shirt", out = 2568, reagents = { { 2996, 3 } } },
    [3] = { name = "Unbolt", out = 2589, qty = 2, reagents = { { 2996, 1 } } },  -- cycle: bolt -> 2 cloth
    [4] = { name = "Thread", out = 400, qty = 5, reagents = { { 2589, 1 } } },
    [5] = { name = "Pants", out = 300, reagents = { { 400, 2 }, { 2996, 1 }, { 2589, 1 } } },
  },
}

return T
