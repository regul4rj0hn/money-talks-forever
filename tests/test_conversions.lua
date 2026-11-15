-- Tests: conversions anyone can do (3 lesser <-> 1 greater essence), priced like recipes and tracked by the ledger
local T = ...
local ns, W, Fire = T.ns, T.W, T.Fire
local Setup, ByName = T.Setup, T.ByName

local LESSER, GREATER, WAND = 10938, 10939, 500
local ESSENCES = {
  items = { [LESSER] = { "Lesser Magic Essence", 10, 0 }, [GREATER] = { "Greater Magic Essence", 30, 0 },
            [WAND] = { "Magic Wand", 1000, 0 } },
  recipes = { [7] = { name = "Wand", out = WAND, reagents = { { GREATER, 1 } } } },
}

T.Test("conversions: split and combine essences for the AH, or for cheaper reagents", function()
  -- The in-game prices: 1 greater 373, 3 lesser 3 x 130 = 390, 370.5 after the AH cut: a loss both ways
  ESSENCES.ah = { [GREATER] = 373, [LESSER] = 130 }
  Setup(ESSENCES)
  local by = ByName()
  local split, combine = by["Split Greater Magic Essence"], by["Combine Lesser Magic Essence"]
  assert(split and combine and split.profession == ns.CONVERT_PROFESSION)
  assert(split.qty == 3 and split.cost == 373 and split.status == ns.STATUS.NOPROFIT)
  assert(math.abs(split.bestProfit - (390 * 0.95 - 373)) < 1e-9, "unprofitable rows show the better way to sell")
  assert(combine.cost == 390 and combine.status == ns.STATUS.NOPROFIT, "not: buy greater, split, combine back")
  assert(by.Wand.cost == 373 and by.Wand.plan.buys[1].itemID == GREATER, "buying the greater is cheaper")

  -- Lesser at 150: 450 x 0.95 = 427.5 for 373 -> "List me!", buy greater up to floor(373 + 427.5 - 373 - 1) = 426
  W.ah[LESSER] = 150
  split = ByName()["Split Greater Magic Essence"]
  assert(split.status == ns.STATUS.LIST and math.abs(split.bestProfit - 54.5) < 1e-9)
  assert(split.plan.buys[1].itemID == GREATER and split.plan.buys[1].maxPrice == 426)
  assert(ns.flaggedByItem[LESSER] == split)
  local caps = ns.CollectShoppingCaps()
  assert(#caps == 1 and caps[1].itemID == GREATER and caps[1].recipes == 2, "List me! rows go on the shopping list")

  -- Lesser at 100: the wand's greater essence is cheaper as 3 lesser combined (300 < 373)
  W.ah[LESSER] = 100
  by = ByName()
  local wand = by.Wand
  assert(wand.cost == 300 and wand.usesCrafting, "combine counts as crafting a reagent")
  assert(wand.plan.buys[1].itemID == LESSER and wand.plan.buys[1].qty == 3)
  assert(wand.plan.crafts[1].itemID == GREATER and wand.plan.crafts[1].count == 1)
  assert(by["Combine Lesser Magic Essence"].status == ns.STATUS.LIST, "300 for 373 x 0.95 = 354.35")

  -- The row tooltips spell out what to do, also for a conversion inside another recipe's plan
  local function Tooltip(row)
    ns.UI.tabs.crafts.ShowTooltip({ data = row })
    return table.concat(GameTooltip.lines, "\n")
  end
  local tip = Tooltip(by["Combine Lesser Magic Essence"])
  assert(tip:find("Convert 3x Lesser Magic Essence into 1x Greater Magic Essence (right-click)", 1, true), tip)
  assert(tip:find("3. List 1x Greater Magic Essence on the AH", 1, true), tip)
  tip = Tooltip(wand)
  assert(tip:find("Convert 3x Lesser Magic Essence into 1x Greater Magic Essence (right-click)", 1, true), tip)
  assert(tip:find("3. Sell 1x Magic Wand to a vendor", 1, true), tip)
end)

T.Test("conversions: using the item is recorded like a craft", function()
  ESSENCES.ah = { [GREATER] = 373, [LESSER] = 150 }
  Setup(ESSENCES)
  ns.session = ns.NewLedgerBucket()
  W.itemSpells = { [GREATER] = 9001, [LESSER] = 9002 } -- the items' "Use:" spells: split, combine
  local L = ns.Ledger()

  ns.RecordPurchase(GREATER, 1, 373)
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 12345) -- some other spell: nothing happens
  assert(L.bought[GREATER].qty == 1)
  Fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 9001)  -- right-click the greater essence
  assert(L.bought[GREATER] == nil, "the greater essence was used")
  assert(L.crafted[LESSER].qty == 3 and L.crafted[LESSER].cost == 373, "3 lesser in stock at its cost")

  ns.RecordVendorSale(LESSER, 3, 30)
  assert(L.items[LESSER].kind == "crafts" and L.items[LESSER].cost == 373)
  W.itemSpells = nil
end)
