-- Tests: profit ledger: purchases, crafts, vendor sales
local T = ...
local ns, W, Fire, flush = T.ns, T.W, T.Fire, T.flush
local Setup, ByName, LINEN = T.Setup, T.ByName, T.LINEN

T.Test("ledger: AH purchases, crafts and vendor sales", function()
  -- vendor prices: Linen Cloth 1, Bolt 10, Shirt 200; recipes: Bolt = 2 cloth, Shirt = 3 bolts
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50 }
  Setup(LINEN)
  ns.session = ns.NewLedgerBucket()
  W.money, W.bag = 100000, {}
  Fire("PLAYER_LOGIN") -- installs the purchase hooks
  local L = ns.Ledger()

  -- Commodity purchase: 10 cloth for 150 total (price from COMMODITY_PRICE_UPDATED)
  C_AuctionHouse.StartCommoditiesPurchase(2589, 10)
  Fire("COMMODITY_PRICE_UPDATED", 15, 150)
  C_AuctionHouse.ConfirmCommoditiesPurchase(2589, 10)
  Fire("COMMODITY_PURCHASE_SUCCEEDED")
  assert(L.bought[2589].qty == 10 and L.bought[2589].cost == 150)

  -- A failed purchase records nothing
  C_AuctionHouse.StartCommoditiesPurchase(2589, 5)
  Fire("COMMODITY_PRICE_UPDATED", 15, 75)
  C_AuctionHouse.ConfirmCommoditiesPurchase(2589, 5)
  Fire("COMMODITY_PURCHASE_FAILED")
  Fire("COMMODITY_PURCHASE_SUCCEEDED") -- stray event must not reuse the failed purchase
  assert(L.bought[2589].qty == 10)

  -- Craft 2 bolts (spell ID = recipe ID): uses 4 cloth at 15 each
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1)
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1)
  Fire("UNIT_SPELLCAST_SUCCEEDED", "target", "guid", 1) -- someone else's cast
  assert(L.bought[2589].qty == 6 and L.crafted[2996].qty == 2 and L.crafted[2996].cost == 60)

  -- Craft a shirt with only 2 bolts in stock: 3rd bolt valued at market (AH 60) and marked estimated
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 2)
  assert(L.crafted[2996] == nil and L.crafted[2568].cost == 120 and L.crafted[2568].estimated == 60)

  -- Sell the shirt (and some loot junk) to a vendor: bags and money change while the merchant is open
  W.bag = { [2568] = 1, [5000] = 3 }
  W.items[5000] = { "Junk", 7, 0 }
  Fire("MERCHANT_SHOW")
  W.bag = {}
  W.money = W.money + 200 + 21
  Fire("PLAYER_MONEY")
  ns.MerchantDiff()
  Fire("MERCHANT_CLOSED")
  local c = L.all.crafts
  assert(c.qty == 1 and c.earned == 200 and c.cost == 120 and c.estimated == 60, "crafts bucket")
  assert(L.items[5000] == nil, "untracked junk is ignored")
  assert(ns.BucketProfit(ns.session) == 80)

  -- Single item bought at buyout, confirmed once the money is spent
  W.auctionsByID = { [77] = { itemKey = { itemID = 2996 }, buyoutAmount = 25, quantity = 5 },
                   [78] = { itemKey = { itemID = 2996 }, buyoutAmount = 99, quantity = 1 } }
  C_AuctionHouse.PlaceBid(78, 50) -- a bid below buyout is not a purchase
  C_AuctionHouse.PlaceBid(77, 25)
  W.money = W.money - 25
  Fire("PLAYER_MONEY")
  Fire("PLAYER_MONEY")
  assert(L.bought[2996].qty == 5 and L.bought[2996].cost == 25)

  -- Flip: sell the 5 bolts to a vendor for 10 each
  W.bag = { [2996] = 5 }
  Fire("MERCHANT_SHOW")
  W.bag = {}
  W.money = W.money + 50
  Fire("PLAYER_MONEY")
  ns.MerchantDiff()
  Fire("MERCHANT_CLOSED")
  local fl = L.all.flips
  assert(fl.qty == 5 and fl.earned == 50 and fl.cost == 25)
  assert(L.items[2996].kind == "flips" and L.items[2568].kind == "crafts")

  -- Buying thread from a vendor puts it in stock at what was paid
  W.bag = {}
  Fire("MERCHANT_SHOW")
  W.bag = { [400] = 5 }
  W.money = W.money - 30
  Fire("PLAYER_MONEY")
  ns.MerchantDiff()
  Fire("MERCHANT_CLOSED")
  assert(L.bought[400].qty == 5 and L.bought[400].cost == 30)

  -- Only money changing (repairs) or only items changing records nothing yet
  Fire("MERCHANT_SHOW")
  W.money = W.money - 500
  Fire("PLAYER_MONEY")
  ns.MerchantDiff()
  Fire("MERCHANT_CLOSED")
  assert(L.all.flips.qty == 5 and L.all.crafts.qty == 1)

  -- Crafting at a vendor (items change, money doesn't) must not later count the used reagents as sold
  local clock = 1000
  local realGetTime = GetTime
  GetTime = function() return clock end
  W.bag = { [2589] = 6, [2996] = 0 }
  Fire("MERCHANT_SHOW")
  W.bag = { [2589] = 4, [2996] = 1 }   -- 2 cloth turned into a bolt, no money involved
  ns.MerchantDiff()                    -- starts waiting for money
  clock = clock + 2
  ns.MerchantDiff()                    -- no money came: accepted as not a sale
  W.bag = { [2589] = 4 }                 -- now sell the bolt
  W.money = W.money + 10
  Fire("PLAYER_MONEY")
  ns.MerchantDiff()
  Fire("MERCHANT_CLOSED")
  GetTime = realGetTime
  assert(L.items[2589] == nil, "cloth used in crafting was counted as sold")
  flush()

  local value, n = ns.LedgerStockValue()
  assert(n == 11 and math.abs(value - (6 * 15 + 30)) < 1e-9, "6 cloth + 5 thread still in stock")
  local today = L.days[os.date("%Y-%m-%d")]
  assert(today and today.flips.earned == 50 and today.crafts.earned == 200)

  ns.ResetLedger()
  assert(ns.Ledger().all.crafts.qty == 0 and ns.BucketProfit(ns.session) == 0)
end)
