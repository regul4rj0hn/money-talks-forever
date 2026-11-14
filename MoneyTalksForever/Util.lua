-- Money Talks Forever: small shared helpers (loaded first).
local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.CALLER_ID = "MoneyTalksForever" -- identifies us to Auctionator's API
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (GetMeta and GetMeta(ADDON_NAME, "Version")) or "?"

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
ns.COLOR = {
  BRAND = "ff33ff99",
  GREEN = "ff00ff00",
  RED = "ffff4040",
  GOLD = "ffffd100",
  BLUE = "ff66ccff",
  ORANGE = "ffff9900",
  GREY = "ff808080",
  DIM = "ff999999",
  LIGHT = "ffcccccc",
}

function ns.Colorize(text, color)
  return "|c" .. color .. tostring(text) .. "|r"
end

function ns.Print(...)
  print(ns.Colorize("Money Talks", ns.COLOR.BRAND) .. ":", ...)
end

-- Copper as gold/silver/copper with coin icons; "--" for nil.
function ns.Money(copper)
  if copper == nil then return ns.Colorize("--", ns.COLOR.GREY) end
  local s = GetMoneyString(math.abs(math.floor(copper + 0.5)), true)
  return copper < 0 and ("-" .. s) or s
end

-- Money in green when >= 0, red when negative.
function ns.ProfitMoney(copper)
  copper = copper or 0
  return ns.Colorize(ns.Money(copper), copper >= 0 and ns.COLOR.GREEN or ns.COLOR.RED)
end

function ns.OnOff(v)
  return v and ns.Colorize("on", ns.COLOR.GREEN) or ns.Colorize("off", ns.COLOR.RED)
end

-- "0.5" (gold) -> 5000 copper, at least 1. nil if not a non-negative number.
function ns.ParseGold(text)
  local gold = tonumber(text)
  if not gold or gold < 0 then return nil end
  return math.max(1, math.floor(gold * 10000 + 0.5))
end

---------------------------------------------------------------------------
-- Tables and calls
---------------------------------------------------------------------------
function ns.CountKeys(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- Calls an API function that may be missing or may error; returns its result only if it is a number.
function ns.SafeNumber(fn, ...)
  if not fn then return nil end
  local ok, v = pcall(fn, ...)
  if ok and type(v) == "number" then return v end
  return nil
end

-- Runs fn once, `delay` seconds after the first of a burst of calls with the same key.
local pending = {}
function ns.Debounce(key, delay, fn)
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(delay, function()
    pending[key] = nil
    fn()
  end)
end

-- Ask the open window (if any) to redraw soon; cheap to call often.
function ns.NotifyUI()
  ns.Debounce("ui", 0.1, function()
    if ns.RefreshUI then ns.RefreshUI() end
  end)
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

-- Name of an item, or "item:ID" while the game loads its data (and the item is then requested).
function ns.ItemName(itemID)
  local name = C_Item.GetItemInfo(itemID)
  if not name then
    C_Item.RequestLoadItemDataByID(itemID)
    ns.waitingForItems = true
  end
  return name or ("item:" .. itemID)
end

-- The fields of GetItemInfo we use, by name. nil if the item data isn't cached yet.
function ns.ItemInfo(item)
  local name, link, _, _, _, _, _, _, equipLoc, icon, sellPrice, _, _, bindType = C_Item.GetItemInfo(item)
  if not name then return nil end
  return { name = name, link = link, icon = icon, sellPrice = sellPrice or 0, bindType = bindType,
           equippable = equipLoc ~= nil and equipLoc ~= "" }
end

function ns.ItemSellPrice(item)
  return (select(11, C_Item.GetItemInfo(item)))
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

-- Calls fn(bag, slot, itemID, count) for every occupied bag slot.
function ns.ForEachBagItem(fn)
  if not C_Container then return end
  for bag = 0, LAST_BAG do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then fn(bag, slot, info.itemID, info.stackCount or 1) end
    end
  end
end

-- { [itemID] = total count in bags }
function ns.BagCounts()
  local counts = {}
  ns.ForEachBagItem(function(_, _, itemID, count) counts[itemID] = (counts[itemID] or 0) + count end)
  return counts
end
