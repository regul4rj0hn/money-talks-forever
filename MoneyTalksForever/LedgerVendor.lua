-- Money Talks Forever: ledger input from NPC vendors. Selling tracked items realizes profit; buying (e.g. thread)
-- puts items in stock. Detected by comparing bag contents and gold while the merchant window is open.
local _, ns = ...

-- Waits until both have changed, since bag and money updates can arrive in different frames.
local merchant -- { counts, money, earned, profit, untracked } while a vendor window is open

local function MerchantDiff()
  if not merchant then return end
  local counts, money = ns.BagCounts(), GetMoney()
  local dMoney = money - merchant.money
  local decreased, increased = {}, {}
  for id, n in pairs(merchant.counts) do
    local now = counts[id] or 0
    if now < n then decreased[id] = n - now end
  end
  for id, n in pairs(counts) do
    local before = merchant.counts[id] or 0
    if n > before then increased[id] = n - before end
  end
  local itemsChanged = next(decreased) ~= nil or next(increased) ~= nil
  if not itemsChanged then
    merchant.money = money -- e.g. repairs: no items involved
    merchant.waitStart = nil
    return
  end
  if dMoney == 0 then
    -- Items changed but no money (yet). Usually the money update is a frame behind; if it doesn't come,
    -- this wasn't a sale (crafting or looting with the vendor open), so accept the new bag contents.
    if not merchant.waitStart then
      merchant.waitStart = GetTime()
      C_Timer.After(1.2, MerchantDiff)
    elseif GetTime() - merchant.waitStart > 1 then
      merchant.counts, merchant.waitStart = counts, nil
    end
    return
  end
  merchant.waitStart = nil

  if dMoney > 0 then
    for id, q in pairs(decreased) do
      local sellPrice = ns.ItemSellPrice(id)
      if sellPrice and sellPrice > 0 then
        local earned = sellPrice * q
        local profit = ns.RecordVendorSale(id, q, earned)
        if profit then
          merchant.earned = merchant.earned + earned
          merchant.profit = merchant.profit + profit
        end
      end
    end
  else
    -- Bought from the vendor: split what was paid across the new items by quantity.
    local totalQty = 0
    for _, q in pairs(increased) do totalQty = totalQty + q end
    for id, q in pairs(increased) do ns.RecordPurchase(id, q, -dMoney * q / totalQty) end
  end
  merchant.counts, merchant.money = counts, money
end
ns.MerchantDiff = MerchantDiff

local function RequestMerchantDiff()
  if merchant then ns.Debounce("merchant", 0.3, MerchantDiff) end
end

function ns.OnMerchantShow()
  merchant = { counts = ns.BagCounts(), money = GetMoney(), earned = 0, profit = 0 }
end

function ns.OnMerchantClosed()
  if not merchant then return end
  MerchantDiff()
  if merchant.earned > 0 and ns.Settings().chatAlert then
    ns.Print(("vendor visit: sold %s of tracked items, %s (session %s)"):format(
      ns.Money(merchant.earned), ns.ProfitOrLoss(merchant.profit), ns.ProfitMoney(ns.BucketProfit(ns.session))))
  end
  merchant = nil
end

ns.On("MERCHANT_SHOW", ns.OnMerchantShow)
ns.On("MERCHANT_CLOSED", ns.OnMerchantClosed)
ns.On("PLAYER_MONEY", RequestMerchantDiff)
ns.On("BAG_UPDATE_DELAYED", RequestMerchantDiff)
