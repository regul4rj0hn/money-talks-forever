-- Money Talks Forever: ledger input from the auction house - purchases (at the exact price paid) and the
-- deposits paid when listing tracked items. Sales come in by mail (LedgerMail.lua).
local _, ns = ...

-- AH: commodities (stackables). Start -> price update -> confirm -> succeeded/failed.
local commodityStart, commodityConfirm
-- AH: single items bought at buyout, confirmed when the money leaves your bags.
local pendingBuys = {}
local lastMoney

local function OnStartCommoditiesPurchase(itemID, qty)
  commodityStart = { itemID = itemID, qty = qty }
end

local function OnConfirmCommoditiesPurchase(itemID, qty)
  local total
  if commodityStart and commodityStart.itemID == itemID and commodityStart.total then
    total = commodityStart.total * qty / math.max(1, commodityStart.qty)
  end
  commodityConfirm = { itemID = itemID, qty = qty, total = total }
end

local function OnPlaceBid(auctionID, amount)
  local info = C_AuctionHouse.GetAuctionInfoByID and C_AuctionHouse.GetAuctionInfoByID(auctionID)
  if not info or not info.itemKey or not info.buyoutAmount or amount < info.buyoutAmount then return end
  table.insert(pendingBuys, { itemID = info.itemKey.itemID, qty = info.quantity or 1, cost = amount, t = GetTime() })
end

-- Listings of tracked items waiting for their deposit to be paid. `deposit` is what the game says the listing
-- costs (nil if it can't tell us), so other spending at the same time isn't mistaken for the deposit.
local pendingPosts = {}

local function AddPendingPost(location, qty, depositFn, ...)
  if not location or not C_Item.GetItemID then return end
  local ok, itemID = pcall(C_Item.GetItemID, location)
  if ok and itemID and ns.IsTracked(itemID) then
    table.insert(pendingPosts, { itemID = itemID, qty = qty or 1, deposit = ns.SafeNumber(depositFn, ...), t = GetTime() })
  end
end

local function OnPostItem(location, duration, qty)
  AddPendingPost(location, qty, C_AuctionHouse.CalculateItemDeposit, location, duration, qty or 1)
end

local function OnPostCommodity(location, duration, qty)
  local ok, itemID = pcall(C_Item.GetItemID, location)
  AddPendingPost(location, qty, C_AuctionHouse.CalculateCommodityDeposit, ok and itemID, duration, qty or 1)
end

-- Hooks only observe calls (no taint): they run after the original function.
function ns.InstallLedgerHooks()
  local AH = C_AuctionHouse
  lastMoney = GetMoney()
  if ns.ledgerHooksInstalled or not AH or not hooksecurefunc then return end
  ns.ledgerHooksInstalled = true -- installing twice would record every purchase twice
  if AH.StartCommoditiesPurchase then hooksecurefunc(AH, "StartCommoditiesPurchase", OnStartCommoditiesPurchase) end
  if AH.ConfirmCommoditiesPurchase then hooksecurefunc(AH, "ConfirmCommoditiesPurchase", OnConfirmCommoditiesPurchase) end
  if AH.PlaceBid then hooksecurefunc(AH, "PlaceBid", OnPlaceBid) end
  if AH.PostItem then hooksecurefunc(AH, "PostItem", OnPostItem) end
  if AH.PostCommodity then hooksecurefunc(AH, "PostCommodity", OnPostCommodity) end
end

-- Gold left your bags: confirm pending buyouts (exact amounts), then the deposits of pending listings. A listing
-- with a known deposit is confirmed once that much was spent; for one without, everything left is its deposit.
local function MatchSpending()
  local now = GetMoney()
  local spent = (lastMoney or now) - now
  lastMoney = now
  for i = #pendingBuys, 1, -1 do
    local p = pendingBuys[i]
    if GetTime() - p.t > 15 then
      table.remove(pendingBuys, i) -- never paid: outbid or no longer available
    elseif spent >= p.cost then
      spent = spent - p.cost
      ns.RecordPurchase(p.itemID, p.qty, p.cost)
      table.remove(pendingBuys, i)
    end
  end
  while #pendingPosts > 0 do
    local p = pendingPosts[1]
    if GetTime() - p.t > 15 then
      table.remove(pendingPosts, 1) -- never posted (e.g. needed confirmation and was cancelled)
    elseif p.deposit and spent >= p.deposit then
      ns.RecordDeposit(p.itemID, p.qty, p.deposit)
      spent = spent - p.deposit
      table.remove(pendingPosts, 1)
    elseif not p.deposit and spent > 0 then
      ns.RecordDeposit(p.itemID, p.qty, spent)
      spent = 0
      table.remove(pendingPosts, 1)
    else
      break
    end
  end
end

ns.On("PLAYER_LOGIN", ns.InstallLedgerHooks)

ns.On("COMMODITY_PRICE_UPDATED", function(_, totalPrice)
  if commodityStart then commodityStart.total = totalPrice end
end)

ns.On("COMMODITY_PURCHASE_SUCCEEDED", function()
  local c = commodityConfirm
  commodityConfirm = nil
  if c then
    local cost = c.total or ((ns.GetReagentUnitPrice(c.itemID) or 0) * c.qty)
    ns.RecordPurchase(c.itemID, c.qty, cost)
  end
end)

ns.On("COMMODITY_PURCHASE_FAILED", function() commodityConfirm = nil end)

ns.On("PLAYER_MONEY", function()
  if #pendingBuys > 0 or #pendingPosts > 0 then MatchSpending() else lastMoney = GetMoney() end
end)
