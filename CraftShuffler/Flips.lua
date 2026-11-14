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

-- Progress of the current flips scan, for the UI. nil when idle, otherwise one of:
--   { phase = "waiting", startedAt, timeout }         full scan requested, AH hasn't sent the listings yet
--   { phase = "reading", done, total, attempt }        going through the listings
--   { phase = "loading", skipped, attempt, retryAt }   waiting for item details before reading again
ns.flipProgress = nil
local function SetProgress(p)
  ns.flipProgress = p
  if ns.OnFlipProgress then ns.OnFlipProgress() end
end
ns.SetFlipProgress = SetProgress

local MAX_ATTEMPTS = 3   -- re-read the listings while the game loads item data we didn't have yet
local RETRY_DELAY = 5

-- Scans the current replicate data. Returns false if there is none (no full scan done / AH closed).
-- ns.lastScanIncremental records that Auctionator updated prices without a full scan, for the UI hint.
function ns.ScanReplicateForFlips(force, attempt)
  attempt = attempt or 1
  local AH = C_AuctionHouse
  if not AH or not AH.GetNumReplicateItems then return false end
  local n = AH.GetNumReplicateItems() or 0
  if n == 0 then return false end
  ns.lastScanIncremental = false
  if ns.flipScanRunning then return true end
  -- RegisterForDBUpdate also fires for incremental scans; skip re-reading the same full scan.
  if not force and ns.flips.listings == n and ns.flips.scannedAt and time() - ns.flips.scannedAt < 15 * 60 then
    return true
  end

  ns.flipScanRunning = true
  SetProgress({ phase = "reading", done = 0, total = n, attempt = attempt })
  local me = UnitName("player")
  local minProfit = ns.Settings().flipMinProfit
  local byItem, skipped, requested = {}, 0, {}
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

    if skipped > 0 and attempt < MAX_ATTEMPTS then
      -- Item data is being loaded by the game; read the listings again in a moment.
      if attempt == 1 then
        ns.Print(("loading details for %d listing(s), rescanning shortly..."):format(skipped))
      end
      SetProgress({ phase = "loading", skipped = skipped, attempt = attempt + 1, retryAt = GetTime() + RETRY_DELAY })
      C_Timer.After(RETRY_DELAY, function()
        -- The listings can be gone by now (e.g. AH closed); then keep what we have.
        if not ns.ScanReplicateForFlips(true, attempt + 1) then SetProgress(nil) end
      end)
      if ns.RefreshUI then ns.RefreshUI() end
      return
    end
    SetProgress(nil)

    local total = 0
    for _, e in ipairs(items) do total = total + e.profit end
    ns.Print(("vendor flips: %d item(s) on the AH below vendor price, %s total profit (/shuffle flips)%s")
      :format(#items, ns.Money(total), skipped > 0 and (" - %d listing(s) skipped, item data not loaded"):format(skipped) or ""))
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
          if not requested[itemID] then
            requested[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
          end
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
    if ns.flipProgress then
      ns.flipProgress.done = index
      if ns.OnFlipProgress then ns.OnFlipProgress() end
    end
    if index < n then
      C_Timer.After(0, Step)
    else
      Finish()
    end
  end

  Step()
  return true
end

---------------------------------------------------------------------------
-- Our own full scan, so flips don't depend on Auctionator's scan mode setting
---------------------------------------------------------------------------
local FULL_SCAN_TIMEOUT = 90

local scanFrame = CreateFrame("Frame")
local scanID = 0 -- identifies the current request, so an old timeout can't cancel a newer scan

function ns.OnReplicateListUpdate()
  if not ns.fullScanPending then return end
  ns.fullScanPending = false
  scanFrame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  if not ns.ScanReplicateForFlips(true) then
    SetProgress(nil)
    ns.Print("the full scan returned no listings.")
  end
  if ns.RefreshUI then ns.RefreshUI() end
end

scanFrame:SetScript("OnEvent", function(_, event)
  if event == "REPLICATE_ITEM_LIST_UPDATE" then ns.OnReplicateListUpdate() end
end)

function ns.CancelFullScan()
  if not ns.fullScanPending then return end
  ns.fullScanPending = false
  scanFrame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  SetProgress(nil)
end

-- Asks the game for every AH listing (C_AuctionHouse.ReplicateItems). The AH allows one such scan per
-- 15 minutes, shared with Auctionator's full scan.
function ns.StartFullScan()
  if not ns.ahOpen then
    ns.Print("open the auction house first.")
    return
  end
  if ns.fullScanPending or ns.flipScanRunning then return end
  if not C_AuctionHouse or not C_AuctionHouse.ReplicateItems then
    ns.Print("full scans are not available on this client.")
    return
  end
  ns.fullScanPending = true
  scanID = scanID + 1
  local myID = scanID
  scanFrame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  C_AuctionHouse.ReplicateItems()
  SetProgress({ phase = "waiting", startedAt = GetTime(), timeout = FULL_SCAN_TIMEOUT })
  ns.Print("full scan requested, waiting for the auction house to send all listings...")
  if ns.RefreshUI then ns.RefreshUI() end

  C_Timer.After(FULL_SCAN_TIMEOUT, function()
    if not ns.fullScanPending or scanID ~= myID then return end
    ns.fullScanPending = false
    scanFrame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    SetProgress(nil)
    ns.Print("the AH did not answer the full scan. It allows one every 15 minutes (shared with Auctionator), "
      .. "so try again later.")
    if ns.RefreshUI then ns.RefreshUI() end
  end)
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
