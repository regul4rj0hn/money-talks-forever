-- CraftShuffler: "vendor flips" - AH listings priced below what a vendor pays for the item.
-- Source: the game's replicate data (every listing on the AH) that Auctionator's full scan downloads.
local _, ns = ...

ns.flips = { items = {}, scannedAt = nil, listings = 0 }
ns.FLIPS_LIST_NAME = "CraftShuffler Flips"

local BATCH = 2000 -- listings per frame, keeps the game responsive on big AHs

local function RealmKey() return GetRealmName() or "?" end

function ns.LoadSavedFlips()
  local saved = CraftShufflerDB.flips[RealmKey()]
  if saved then ns.flips = saved end
end

-- Scans the current replicate data. Returns false if there is none (no full scan done / AH closed).
function ns.ScanReplicateForFlips(force)
  local AH = C_AuctionHouse
  if not AH or not AH.GetNumReplicateItems then return false end
  local n = AH.GetNumReplicateItems() or 0
  if n == 0 then return false end
  if ns.flipScanRunning then return true end
  -- RegisterForDBUpdate also fires for incremental scans; skip re-reading the same full scan.
  if not force and ns.flips.listings == n and ns.flips.scannedAt and time() - ns.flips.scannedAt < 15 * 60 then
    return true
  end

  ns.flipScanRunning = true
  local me = UnitName("player")
  local minProfit = ns.Settings().flipMinProfit
  local byItem, skipped = {}, 0
  local index = 0 -- replicate indices are 0-based

  local function Finish()
    local items = {}
    for _, e in pairs(byItem) do table.insert(items, e) end
    table.sort(items, function(a, b)
      if a.profit ~= b.profit then return a.profit > b.profit end
      return a.itemID < b.itemID
    end)
    ns.flips = { items = items, scannedAt = time(), listings = n, skipped = skipped }
    CraftShufflerDB.flips[RealmKey()] = ns.flips
    ns.flipScanRunning = false

    local total = 0
    for _, e in ipairs(items) do total = total + e.profit end
    ns.Print(("vendor flips: %d item(s) on the AH below vendor price, %s total profit (/shuffle flips)")
      :format(#items, ns.Money(total)))
    if ns.RefreshUI then ns.RefreshUI() end
  end

  local function Step()
    local last = math.min(index + BATCH, n) - 1
    for i = index, last do
      local _, texture, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID = AH.GetReplicateItemInfo(i)
      if itemID and buyout and buyout > 0 and count and count > 0 and owner ~= me then
        local link = AH.GetReplicateItemLink and AH.GetReplicateItemLink(i)
        local name, _, _, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(link or itemID)
        if not name then
          skipped = skipped + 1
        elseif sellPrice and sellPrice > 0 then
          local profit = sellPrice * count - buyout
          if profit >= minProfit then
            local e = byItem[itemID]
            if not e then
              e = { itemID = itemID, name = name, link = link, icon = texture,
                    listings = 0, qty = 0, cost = 0, vendor = 0, profit = 0, maxUnit = 0, vendorUnit = 0 }
              byItem[itemID] = e
            end
            e.listings = e.listings + 1
            e.qty = e.qty + count
            e.cost = e.cost + buyout
            e.vendor = e.vendor + sellPrice * count
            e.profit = e.profit + profit
            e.maxUnit = math.max(e.maxUnit, buyout / count)
            e.vendorUnit = math.max(e.vendorUnit, sellPrice)
          end
        end
      end
    end
    index = last + 1
    if index < n then
      C_Timer.After(0, Step)
    else
      Finish()
    end
  end

  Step()
  return true
end

-- Auctionator shopping list: each flip item capped at the highest unit price that still profits.
function ns.CreateFlipsShoppingList()
  local api = ns.AuctionatorAPI()
  if not api or not api.CreateShoppingList or not api.ConvertToSearchString then
    ns.Print("Auctionator shopping lists are not available.")
    return
  end
  local searchStrings = {}
  for _, e in ipairs(ns.flips.items) do
    local cap = math.min(math.floor(e.maxUnit), e.vendorUnit - 1)
    if cap > 0 then
      local ok, s = pcall(api.ConvertToSearchString, ns.CALLER_ID,
        { searchString = e.name, isExact = true, maxPrice = cap })
      if ok and type(s) == "string" then table.insert(searchStrings, s) end
    end
  end
  if #searchStrings == 0 then
    ns.Print("no vendor flips found yet - run a full scan in Auctionator first.")
    return
  end
  local ok, err = pcall(api.CreateShoppingList, ns.CALLER_ID, ns.FLIPS_LIST_NAME, searchStrings)
  if not ok then
    ns.Print("could not create shopping list: " .. tostring(err))
    return
  end
  ns.Print(("created Auctionator shopping list '%s' with %d item(s). Buy them, then sell them to any vendor.")
    :format(ns.FLIPS_LIST_NAME, #searchStrings))
end
