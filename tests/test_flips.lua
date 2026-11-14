-- Tests: vendor flips and full scans
local T = ...
local ns, W, Fire, flush = T.ns, T.W, T.Fire, T.flush
local Setup, ByName, LINEN = T.Setup, T.ByName, T.LINEN

T.Test("vendor flips from full scan listings", function()
  -- vendor prices: Linen Cloth 1, Bolt 10, Shirt 200
  Setup(LINEN)
  W.replicate = {
    { 2996, 5, 25 },              -- 5 bolts for 25 (5 each) -> vendor 50 -> +25
    { 2996, 2, 30 },              -- 15 each > 10 -> not a flip
    { 2996, 1, 9 },               -- 9 < 10 -> +1
    { 2568, 1, 150 },             -- shirt 150 < 200 -> +50
    { 2568, 1, 0 },               -- bid only -> skipped
    { 2568, 1, 10, "Tester" },    -- own auction -> skipped
    { 2589, 20, 20 },             -- cloth 1 each = vendor -> no profit
    { 9999, 1, 1 },               -- uncached item -> skipped
  }
  assert(ns.ScanReplicateForFlips(true))
  flush()
  local f = ns.flips
  assert(#f.items == 2, "#items " .. #f.items)
  assert(f.items[1].itemID == 2568 and f.items[1].profit == 50, "sorted by profit")
  local bolt = f.items[2]
  assert(bolt.listings == 2 and bolt.qty == 6 and bolt.cost == 34 and bolt.vendor == 60 and bolt.profit == 26)
  assert(bolt.maxUnit == 9 and bolt.vendorUnit == 10)
  assert(f.skipped == 1 and MoneyTalksForeverDB.flips.Realm == f)

  MoneyTalksForeverDB.settings.flipMinProfit = 30
  ns.ScanReplicateForFlips(true); flush()
  assert(#ns.flips.items == 1 and ns.flips.items[1].itemID == 2568)

  ns.CreateFlipsShoppingList()
  local list = W.createdLists[ns.FLIPS_LIST_NAME]
  assert(list and #list == 1 and list[1] == '"Linen Shirt";;;;;;;;0.015;;;;', tostring(list and list[1]))

  W.replicate = {}
  assert(ns.ScanReplicateForFlips(true) == false, "no replicate data -> false, keeps last result")
  assert(#ns.flips.items == 1)
end)

T.Test("full scan button, item data retry and timeout", function()
  Setup(LINEN)
  ns.flips = { items = {}, listings = 0 }
  W.replicate = {}

  -- Not at the AH: no request
  ns.ahOpen = false
  ns.StartFullScan()
  assert(W.replicateRequests == 0 and not ns.fullScanPending)

  -- At the AH: requests a full scan, then reads listings when the game answers
  ns.ahOpen = true
  ns.StartFullScan()
  assert(W.replicateRequests == 1 and ns.fullScanPending)
  assert(ns.flipProgress and ns.flipProgress.phase == "waiting" and ns.flipProgress.timeout == 90)
  ns.StartFullScan()
  assert(W.replicateRequests == 1, "no second request while one is pending")

  -- Shirt is not cached yet on the first read, then the game loads it
  local shirt = W.items[2568]
  W.items[2568] = nil
  local requestedLoads = {}
  C_Item.RequestLoadItemDataByID = function(id)
    requestedLoads[#requestedLoads + 1] = id
    W.items[2568] = shirt
  end
  W.replicate = { { 2568, 1, 150 }, { 2568, 1, 160 } }
  ns.OnReplicateListUpdate()
  assert(not ns.fullScanPending)
  local p = ns.flipProgress
  -- Items are looked up once per pass, so both listings of the not-yet-loaded shirt wait for the retry.
  assert(p and p.phase == "loading" and p.skipped == 2 and p.attempt == 2, "waiting for item details before retry")
  flush() -- runs the retry
  assert(ns.flipProgress == nil, "idle again after the scan")
  C_Item.RequestLoadItemDataByID = function() end
  assert(#requestedLoads == 1, "item data requested once per item, got " .. #requestedLoads)
  assert(#ns.flips.items == 1 and ns.flips.items[1].listings == 2 and ns.flips.skipped == 0)

  -- AH never answers: timeout clears the pending state
  ns.StartFullScan()
  assert(ns.fullScanPending)
  flush() -- runs the timeout callback (mock timers ignore delays)
  assert(not ns.fullScanPending)

  -- Closing the AH cancels a pending scan
  ns.StartFullScan()
  ns.CancelFullScan()
  assert(not ns.fullScanPending and ns.flipProgress == nil)

  -- A timeout left over from an earlier scan must not cancel a newer one
  W.replicate = { { 2568, 1, 150 } }
  ns.StartFullScan()          -- scan A (its timeout is queued)
  ns.OnReplicateListUpdate()  -- A finishes
  ns.StartFullScan()          -- scan B
  T.RunNextTimer()   -- A's timeout fires
  assert(ns.fullScanPending, "stale timeout cancelled the newer scan")
  flush()                     -- B's timeout
  assert(not ns.fullScanPending)

  -- Reading progress reaches the total
  local seen = {}
  local notify = ns.NotifyUI
  ns.NotifyUI = function() if ns.flipProgress then seen[#seen + 1] = ns.flipProgress.phase end end
  ns.ScanReplicateForFlips(true)
  flush()
  ns.NotifyUI = notify
  assert(seen[1] == "reading" and ns.flipProgress == nil)
  ns.ahOpen = false
end)
