-- Tests: shuffle pricing, plans, AH-vs-vendor verdict, shopping list
local T = ...
local ns, W, Fire, flush = T.ns, T.W, T.Fire, T.flush
local Setup, ByName, LINEN = T.Setup, T.ByName, T.LINEN

T.Test("basic shuffle / no profit / missing / soulbound excluded", function()
  Setup({
    items = { [100] = { "Bolt", 5, 0 }, [101] = { "Shirt", 120, 0 }, [102] = { "BoP Robe", 900, 1 },
              [103] = { "Belt", 50, 2 }, [200] = { "Cloth", 10, 0 }, [201] = { "Thread", 0, 0 }, [202] = { "Dye", 0, 0 } },
    ah = { [200] = 10, [202] = 500 },
    vendor = { [201] = 1 },
    recipes = {
      [1] = { name = "Shirt", out = 101, reagents = { { 200, 10 }, { 201, 5 } } },  -- 105 < 120
      [2] = { name = "Robe", out = 102, reagents = { { 200, 1 } } },                -- BoP
      [3] = { name = "Belt", out = 103, reagents = { { 200, 4 }, { 202, 1 } } },    -- 540 > 50
      [4] = { name = "Bolt", out = 100, reagents = { { 999, 1 } } },                -- unpriced reagent
      [5] = { name = "Enchant", out = nil, reagents = { { 200, 1 } } },             -- no output item
    },
  })
  local by = ByName()
  local recorded = 0
  for _, r in ipairs(ns.results) do if r.profession ~= ns.CONVERT_PROFESSION then recorded = recorded + 1 end end
  assert(recorded == 3, "excluded: BoP robe and the recipe without an output item")
  assert(by.Shirt.status == ns.STATUS.SHUFFLE and by.Shirt.profit == 15)
  assert(by.Belt.status == ns.STATUS.NOPROFIT)
  assert(by.Bolt.status == ns.STATUS.MISSING)
  assert(ns.flaggedByItem[101])

  MoneyTalksForeverDB.settings.useVendorReagentPrice = false
  assert(ByName().Shirt.status == ns.STATUS.MISSING, "thread has no price without vendor prices")

  MoneyTalksForeverDB.settings.useVendorReagentPrice = true
  MoneyTalksForeverDB.settings.includeSoulbound = true
  assert(ByName().Robe and ns.flaggedByItem[102])
end)

T.Test("craftable reagents use the cheaper of buy vs craft", function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50 }
  Setup(LINEN)
  local by = ByName()
  assert(by.Shirt.cost == 120 and by.Shirt.status == ns.STATUS.SHUFFLE, "crafted bolts: 3 x 40")
  local b = by.Shirt.breakdown[1]
  assert(b.source == "craft" and b.buyUnit == 60 and b.craftUnit == 40)
  assert(by.Bolt.cost == 40, "bolt must not be priced by unbolting its own output")
  assert(by.Unbolt.cost == 60, "cloth can't come from bolts crafted out of cloth: buy the bolt")

  W.ah[2996] = nil
  by = ByName()
  assert(by.Shirt.cost == 120 and by.Shirt.breakdown[1].buyUnit == nil, "priceable via crafting with no AH listing")

  MoneyTalksForeverDB.settings.craftReagents = false
  assert(ByName().Shirt.status == ns.STATUS.MISSING)

  MoneyTalksForeverDB.settings.craftReagents = true
  W.ah[2996] = 30
  by = ByName()
  assert(by.Shirt.cost == 90 and by.Shirt.breakdown[1].source == "AH")
end)

T.Test("plan lists buys, crafts in order and leftovers", function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50 }
  Setup(LINEN)
  local by = ByName()
  local pl = by.Shirt.plan
  assert(by.Shirt.usesCrafting)
  assert(#pl.buys == 1 and pl.buys[1].name == "Linen Cloth" and pl.buys[1].qty == 6)
  assert(#pl.crafts == 1 and pl.crafts[1].count == 3 and pl.buyTotal == 120)

  local pp = by.Pants.plan -- 2 thread (1 craft, 3 leftover) + 1 bolt (2 cloth) + 1 cloth
  assert(#pp.buys == 1 and pp.buys[1].qty == 4)
  assert(#pp.crafts == 2 and #pp.leftovers == 1 and pp.leftovers[1].qty == 3)
  assert(math.abs(by.Pants.cost - 68) < 1e-9)

  W.ah[2996], W.ah[400] = 10, 1
  by = ByName()
  assert(not by.Shirt.usesCrafting and by.Shirt.plan.buys[1].name == "Bolt of Linen Cloth")
end)

T.Test("auction value of the crafted item", function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50, [2568] = 400 }
  Setup(LINEN)
  local by = ByName()
  assert(by.Shirt.auctionValue == 400 and by.Shirt.auctionNet == 380)
  assert(by.Shirt.auctionProfit == 380 - by.Shirt.cost)
  assert(by.Thread.auctionValue == 250, "auction value counts the full output quantity (5 x 50)")
  assert(by.Pants.auctionValue == nil and by.Pants.auctionProfit == nil, "never listed -> no auction value")
end)

T.Test("AH vs vendor verdict with estimated and recorded deposits", function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50, [2568] = 400, [300] = 100 }
  Setup(LINEN)
  local by = ByName()
  -- Shirt: vendor 200, AH 400 -> net 380; estimated deposit 15% of 200 = 30 -> p = 30 / (180 + 30)
  local shirt = by.Shirt
  assert(shirt.saleVerdict == "ah" and shirt.depositEstimated and shirt.deposit == 30)
  assert(math.abs(shirt.breakEvenSell - 30 / 210) < 1e-9)
  assert(by.Pants.saleVerdict == "vendor", "AH net 95 < vendor 500")
  assert(by.Bolt.saleVerdict == "ah", "verdict is known even though bolt is unprofitable to craft")

  MoneyTalksForeverDB.deposits[2568] = { [1] = 10 }
  shirt = ByName().Shirt
  assert(not shirt.depositEstimated and math.abs(shirt.breakEvenSell - 10 / 190) < 1e-9)

  MoneyTalksForeverDB.settings.ahDuration = 3 -- 48h: no recorded value, estimate x4
  assert(ByName().Shirt.deposit == 120)
end)

T.Test("max reagent prices and Auctionator shopping list", function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50 }
  Setup(LINEN)
  local by = ByName()
  -- Shirt: buys 6 cloth for 120, vendor 200, min profit 1 -> slack 79 -> cap floor(20 + 79 / 6) = 33
  assert(by.Shirt.plan.buys[1].maxPrice == 33)
  -- Pants: buys 4 cloth for 80, vendor 500 -> slack 419 -> cap floor(20 + 419 / 4) = 124
  assert(by.Pants.plan.buys[1].maxPrice == 124)
  -- "List me!" recipes count too, capped by AH value after the cut: Thread makes 5, AH 50 each -> net 237.5,
  -- buys 1 cloth -> cap floor(20 + 237.5 - 20 - 1) = 236. Bolt: net 57 -> cap floor(20 + (57 - 40 - 1) / 2) = 28.
  assert(by.Thread.status == ns.STATUS.LIST and by.Thread.plan.buys[1].maxPrice == 236)
  assert(by.Bolt.status == ns.STATUS.LIST and by.Bolt.plan.buys[1].maxPrice == 28)
  local caps = ns.CollectShoppingCaps()
  assert(#caps == 1 and caps[1].name == "Linen Cloth" and caps[1].maxPrice == 236 and caps[1].recipes == 4)

  ns.CreateReagentShoppingList()
  local list = W.createdLists[ns.SHOPPING_LIST_NAME]
  assert(list and #list == 1 and list[1] == '"Linen Cloth";;;;;;;;0.0236;;;;', tostring(list and list[1]))
end)
