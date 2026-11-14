-- Money Talks Forever: "vendor flips" - AH listings priced below what a vendor pays for the item.
-- Source: the game's replicate data, i.e. every AH listing, downloaded by a full scan (ours or Auctionator's).
local _, ns = ...

ns.flips = { items = {}, scannedAt = nil, listings = 0 }
ns.FLIPS_LIST_NAME = "Money Talks Forever Flips"

local BATCH = 2000            -- listings read per frame, keeps the game responsive on big AHs
local MAX_ATTEMPTS = 3        -- re-read the listings while the game loads item data we didn't have yet
local RETRY_DELAY = 5
local FULL_SCAN_TIMEOUT = 90  -- seconds to wait for the AH to send the listings
local SAME_SCAN_WINDOW = 15 * 60

local function RealmKey() return GetRealmName() or "?" end

ns.On("PLAYER_LOGIN", function()
  local saved = MoneyTalksForeverDB.flips[RealmKey()]
  if saved then ns.flips = saved end
end)

-- Progress of the current flips scan, read by the UI. nil when idle, otherwise one of:
--   { phase = "waiting", startedAt, timeout }         full scan requested, AH hasn't sent the listings yet
--   { phase = "reading", done, total, attempt }        going through the listings
--   { phase = "loading", skipped, attempt, retryAt }   waiting for item details before reading again
ns.flipProgress = nil
local function SetProgress(p)
  ns.flipProgress = p
  ns.NotifyUI()
end

---------------------------------------------------------------------------
-- Reading the listings
---------------------------------------------------------------------------

-- Item data per scan, so each item is looked up once instead of once per listing.
-- Equippable items can be worth different amounts to a vendor depending on item level, so their vendor price is
-- read from each listing's own link; for everything else the item ID is enough.
local function NewItemCache()
  local cache = {}
  return function(itemID)
    local c = cache[itemID]
    if c == nil then
      local info = ns.ItemInfo(itemID)
      c = info or false
      cache[itemID] = c
    end
    return c or nil
  end
end

local function AddListing(byItem, info, itemID, link, texture, count, buyout, sellPrice)
  local e = byItem[itemID]
  if not e then
    e = { itemID = itemID, name = info.name, link = link or info.link, icon = texture,
          listings = 0, qty = 0, cost = 0, vendor = 0, profit = 0, maxUnit = 0, vendorUnit = 0 }
    byItem[itemID] = e
  end
  e.listings = e.listings + 1
  e.qty = e.qty + count
  e.cost = e.cost + buyout
  e.vendor = e.vendor + sellPrice * count
  e.profit = e.profit + (sellPrice * count - buyout)
  e.maxUnit = math.max(e.maxUnit, buyout / count)
  e.vendorUnit = math.max(e.vendorUnit, sellPrice)
end

-- Reads the current replicate data in batches. Returns false if there is none (no full scan, or AH closed).
function ns.ScanReplicateForFlips(force, attempt)
  attempt = attempt or 1
  local AH = C_AuctionHouse
  if not AH or not AH.GetNumReplicateItems then return false end
  local n = AH.GetNumReplicateItems() or 0
  if n == 0 then return false end
  ns.lastScanIncremental = false
  if ns.flipScanRunning then return true end
  -- Auctionator's update callback also fires for incremental scans; don't re-read the same full scan.
  local f = ns.flips
  if not force and f.listings == n and f.scannedAt and time() - f.scannedAt < SAME_SCAN_WINDOW then
    return true
  end

  ns.flipScanRunning = true
  SetProgress({ phase = "reading", done = 0, total = n, attempt = attempt })
  local me = UnitName("player")
  local minProfit = ns.Settings().flipMinProfit
  local lookup = NewItemCache()
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
    MoneyTalksForeverDB.flips[RealmKey()] = ns.flips
    ns.flipScanRunning = false

    if skipped > 0 and attempt < MAX_ATTEMPTS then
      -- The game is loading item data we requested; read the listings again in a moment.
      if attempt == 1 then
        ns.Print(("loading details for %d listing(s), rescanning shortly..."):format(skipped))
      end
      SetProgress({ phase = "loading", skipped = skipped, attempt = attempt + 1, retryAt = GetTime() + RETRY_DELAY })
      C_Timer.After(RETRY_DELAY, function()
        -- The listings can be gone by now (e.g. AH closed); then keep what we have.
        if not ns.ScanReplicateForFlips(true, attempt + 1) then SetProgress(nil) end
      end)
      return
    end
    SetProgress(nil)

    local total = 0
    for _, e in ipairs(items) do total = total + e.profit end
    ns.Print(("vendor flips: %d item(s) on the AH below vendor price, %s total profit (/mtf flips)%s"):format(
      #items, ns.Money(total), skipped > 0 and (" - %d listing(s) skipped, item data not loaded"):format(skipped) or ""))
  end

  local function Step()
    local last = math.min(index + BATCH, n) - 1
    for i = index, last do
      local _, texture, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID = AH.GetReplicateItemInfo(i)
      if itemID and buyout and buyout > 0 and count and count > 0 and owner ~= me then
        local info = lookup(itemID)
        if not info then
          skipped = skipped + 1
          if not requested[itemID] then
            requested[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
          end
        else
          local link, sellPrice = nil, info.sellPrice
          if info.equippable and AH.GetReplicateItemLink then
            link = AH.GetReplicateItemLink(i)
            sellPrice = (link and ns.ItemSellPrice(link)) or sellPrice
          end
          if sellPrice > 0 and sellPrice * count - buyout >= minProfit then
            AddListing(byItem, info, itemID, link, texture, count, buyout, sellPrice)
          end
        end
      end
    end
    index = last + 1
    if ns.flipProgress then ns.flipProgress.done = index end
    if index < n then
      C_Timer.After(0, Step)
    else
      Finish()
    end
  end

  Step()
  return true
end

-- After an Auctionator scan the game may hold every listing (full scans only); look for flips.
ns.On("MTF_PRICES_UPDATED", function()
  if not ns.ahOpen then return end
  C_Timer.After(1, function()
    if not ns.ScanReplicateForFlips() then
      ns.lastScanIncremental = true -- incremental scans have no individual listings
      ns.NotifyUI()
    end
  end)
end)

---------------------------------------------------------------------------
-- Our own full scan, so flips don't depend on Auctionator's scan mode setting
---------------------------------------------------------------------------
local scanID = 0 -- identifies the current request, so an old timeout can't cancel a newer scan

function ns.CancelFullScan()
  if not ns.fullScanPending then return end
  ns.fullScanPending = false
  SetProgress(nil)
end

function ns.OnReplicateListUpdate()
  if not ns.fullScanPending then return end -- someone else's scan (e.g. Auctionator's); it reports via its callback
  ns.fullScanPending = false
  if not ns.ScanReplicateForFlips(true) then
    SetProgress(nil)
    ns.Print("the full scan returned no listings.")
  end
end

ns.On("REPLICATE_ITEM_LIST_UPDATE", ns.OnReplicateListUpdate)
ns.On("AUCTION_HOUSE_CLOSED", ns.CancelFullScan)

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
  C_AuctionHouse.ReplicateItems()
  SetProgress({ phase = "waiting", startedAt = GetTime(), timeout = FULL_SCAN_TIMEOUT })
  ns.Print("full scan requested, waiting for the auction house to send all listings...")

  C_Timer.After(FULL_SCAN_TIMEOUT, function()
    if not ns.fullScanPending or scanID ~= myID then return end
    ns.CancelFullScan()
    ns.Print("the AH did not answer the full scan. It allows one every 15 minutes (shared with Auctionator), "
      .. "so try again later.")
  end)
end

-- Auctionator shopping list: each flip item capped at the highest unit price that still profits.
function ns.CreateFlipsShoppingList()
  local terms = {}
  for _, e in ipairs(ns.flips.items) do
    local cap = math.min(math.floor(e.maxUnit), e.vendorUnit - 1)
    if cap > 0 then table.insert(terms, { name = e.name, maxPrice = cap }) end
  end
  if #terms == 0 then
    ns.Print("no vendor flips found yet - at the AH, click Full scan on the Vendor flips tab.")
    return
  end
  local added, err = ns.CreateAuctionatorList(ns.FLIPS_LIST_NAME, terms)
  if not added then
    ns.Print(err)
    return
  end
  ns.Print(("created Auctionator shopping list '%s' with %d item(s). Buy them, then sell them to any vendor.")
    :format(ns.FLIPS_LIST_NAME, added))
end
