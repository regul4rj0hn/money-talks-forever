-- Tests: profit ledger: AH sales and deposits from mail
local T = ...
local ns, W, Fire, flush = T.ns, T.W, T.Fire, T.flush
local Setup, ByName, LINEN = T.Setup, T.ByName, T.LINEN

T.Test("ledger: AH sales from mail and lost deposits", function()
  LINEN.ah = { [2589] = 20, [2996] = 60 }
  Setup(LINEN)
  ns.session = ns.NewLedgerBucket()
  W.money, W.bag, W.inbox = 100000, {}, {}
  Fire("PLAYER_LOGIN")
  Fire("PLAYER_LOGIN") -- a second install must not double-record
  local L = ns.Ledger()

  -- 2 shirts bought for 150 each, listed together: the 30 deposit leaves your gold after posting
  ns.RecordPurchase(2568, 2, 300)
  C_AuctionHouse.PostItem({ itemID = 2568 }, 1, 2, nil, 400)
  W.money = W.money - 30
  Fire("PLAYER_MONEY")
  assert(#L.deposits[2568] == 1 and L.deposits[2568][1].amount == 30, "one deposit of 30 recorded")
  -- Listing an untracked item records no deposit
  C_AuctionHouse.PostItem({ itemID = 5000 }, 1, 1, nil, 10)
  W.money = W.money - 5
  Fire("PLAYER_MONEY")
  assert(L.deposits[5000] == nil)

  -- Mailbox: one shirt sold (200, AH cut 10, half the deposit paid back), one came back expired, one untracked sale
  W.inbox = {
    { subject = "Auction successful: Linen Shirt", money = 200 - 10 + 15,
      invoice = { type = "seller", itemName = "Linen Shirt", bid = 200, deposit = 15, consignment = 10, count = 1 } },
    { subject = "Auction expired: Linen Shirt", item = { name = "Linen Shirt", id = 2568, count = 1 } },
    { subject = "Auction successful: Junk", money = 50,
      invoice = { type = "seller", itemName = "Junk", bid = 52, deposit = 0, consignment = 2, count = 1 } },
  }
  Fire("MAIL_SHOW")
  Fire("MAIL_INBOX_UPDATE")             -- nothing collected yet
  assert(L.all.flips.qty == 0)
  table.remove(W.inbox, 1)                    -- take the sale money
  Fire("MAIL_INBOX_UPDATE")
  local fl = L.all.flips
  assert(fl.qty == 1 and fl.earned == 190 and fl.cost == 150 and (fl.ahQty or 0) == 1 and (fl.deposits or 0) == 0,
    "AH sale: net 190, cost 150, refunded deposit is not a cost")
  table.remove(W.inbox, 1)                    -- take the expired shirt
  table.remove(W.inbox, 1)                    -- untracked sale
  Fire("MAIL_INBOX_UPDATE")
  Fire("MAIL_CLOSED")
  assert(fl.qty == 1 and fl.cost == 165 and fl.deposits == 15, "expired auction loses the other half of the deposit")
  assert(L.deposits[2568] == nil and L.items[2568].ahQty == 1 and L.bought[2568].qty == 1)
  assert(ns.BucketProfit(ns.session) == 190 - 165)

  -- Two identical sale mails, only one collected -> one sale. Deposit not paid back -> it is a cost.
  ns.RecordPurchase(2996, 2, 20)
  ns.RecordDeposit(2996, 1, 3)
  local mail = { subject = "Auction successful: Bolt of Linen Cloth", money = 14,
    invoice = { type = "seller", itemName = "Bolt of Linen Cloth", bid = 15, deposit = 3, consignment = 1, count = 1 } }
  W.inbox = { mail, mail }
  Fire("MAIL_SHOW")
  W.inbox = { mail }
  Fire("MAIL_INBOX_UPDATE")
  Fire("MAIL_CLOSED")
  assert(L.items[2996].ahQty == 1 and L.items[2996].earned == 14 and L.items[2996].cost == 10 + 3)
  W.inbox = {}
end)

T.Test("ledger: deposits come from the game and the sale mail, not from other spending", function()
  LINEN.ah = { [2589] = 20, [2996] = 60 }
  Setup(LINEN)
  ns.session = ns.NewLedgerBucket()
  W.money, W.bag, W.inbox = 100000, {}, {}
  Fire("PLAYER_LOGIN")
  local L = ns.Ledger()

  -- Two shirts listed one by one (deposit 12 each) while also buying 500 worth of commodities: one money update.
  W.itemDeposit = 12
  ns.RecordPurchase(2568, 2, 300)
  C_AuctionHouse.PostItem({ itemID = 2568 }, 1, 1, nil, 400)
  C_AuctionHouse.PostItem({ itemID = 2568 }, 1, 1, nil, 400)
  W.money = W.money - 500 - 24
  Fire("PLAYER_MONEY")
  W.itemDeposit = nil
  local d = L.deposits[2568]
  assert(#d == 2 and d[1].amount == 12 and d[2].amount == 12, "each listing gets its own deposit, not the purchase")

  -- A wrong recorded deposit doesn't matter for a sale: the mail says 12 and pays 12 back.
  d[1].amount = 100
  W.inbox = { { subject = "Auction successful: Linen Shirt", money = 200 - 10 + 12,
    invoice = { type = "seller", itemName = "Linen Shirt", bid = 200, deposit = 12, consignment = 10, count = 1 } } }
  Fire("MAIL_SHOW")
  W.inbox = {}
  Fire("MAIL_INBOX_UPDATE")
  Fire("MAIL_CLOSED")
  local fl = L.all.flips
  assert(fl.earned == 190 and fl.cost == 150 and (fl.deposits or 0) == 0, "sale: refunded deposit is no cost")
  assert(ns.BucketProfit(ns.session) == 40)
end)
