-- Offline tests for CraftShuffler's scanning/pricing logic, using a mocked WoW API.
-- Run from the repo root:  lua tests/run.lua
local ADDON_DIR = "CraftShuffler"

---------------------------------------------------------------------------
-- WoW API mocks
---------------------------------------------------------------------------
local timers = {}
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
local function flush() while #timers > 0 do table.remove(timers, 1)() end end

local frameMT = { __index = function() return function() end end }
function CreateFrame() return setmetatable({}, frameMT) end
UnitName = function() return "Tester" end
GetRealmName = function() return "Realm" end
GetMoneyString = function(c) return c .. "c" end
SlashCmdList = {}
Enum = { ItemBind = { None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3 }, CraftingReagentType = { Basic = 1 } }

local items, ah, vendor, recipes -- per-scenario data, set by Setup()

C_Item = {
  GetItemInfo = function(id)
    local i = items[id]
    if not i then return nil end
    -- name, link, quality, ilvl, minLevel, type, subType, stack, equipLoc, icon, sellPrice, class, subclass, bindType
    return i[1], "[" .. i[1] .. "]", 1, 1, 1, "", "", 1, "", 1, i[2], 0, 0, i[3]
  end,
  RequestLoadItemDataByID = function() end,
}
Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, id) return ah[id] end,
  GetVendorPriceByItemID = function(_, id) return vendor[id] end,
} } }
C_TradeSkillUI = {
  IsTradeSkillReady = function() return true end,
  GetBaseProfessionInfo = function() return { professionName = "Tailoring" } end,
  GetAllRecipeIDs = function()
    local t = {}
    for id in pairs(recipes) do t[#t + 1] = id end
    table.sort(t)
    return t
  end,
  GetRecipeInfo = function(id) return { name = recipes[id].name, learned = true } end,
  GetRecipeSchematic = function(id)
    local r, slots = recipes[id], {}
    for _, g in ipairs(r.reagents) do
      table.insert(slots, { required = true, quantityRequired = g[2], reagents = { { itemID = g[1] } } })
    end
    return { outputItemID = r.out, quantityMin = r.qty or 1, quantityMax = r.qty or 1, reagentSlotSchematics = slots }
  end,
}

local ns = {}
for _, f in ipairs({ "Core.lua", "Pricing.lua", "Scanner.lua" }) do
  assert(loadfile(ADDON_DIR .. "/" .. f))("CraftShuffler", ns)
end
print = function() end -- silence addon chat output

local function Setup(scenario)
  items, ah, vendor, recipes = scenario.items, scenario.ah, scenario.vendor or {}, scenario.recipes
  CraftShufflerDB = { chars = {}, settings = {
    useVendorReagentPrice = true, craftReagents = true, includeSoulbound = false, minProfit = 1 } }
  ns.ScanOpenProfession()
  flush()
end

local function ByName()
  ns.Evaluate()
  local by = {}
  for _, r in ipairs(ns.results) do by[r.name] = r end
  return by
end

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------
local tests = {}

tests["basic shuffle / no profit / missing / soulbound excluded"] = function()
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
  assert(#ns.results == 3)
  assert(by.Shirt.status == ns.STATUS.SHUFFLE and by.Shirt.profit == 15)
  assert(by.Belt.status == ns.STATUS.NOPROFIT)
  assert(by.Bolt.status == ns.STATUS.MISSING)
  assert(ns.flaggedByItem[101])

  CraftShufflerDB.settings.useVendorReagentPrice = false
  assert(ByName().Shirt.status == ns.STATUS.MISSING, "thread has no price without vendor prices")

  CraftShufflerDB.settings.useVendorReagentPrice = true
  CraftShufflerDB.settings.includeSoulbound = true
  assert(ByName().Robe and ns.flaggedByItem[102])
end

local LINEN = {
  items = { [2589] = { "Linen Cloth", 1, 0 }, [2996] = { "Bolt of Linen Cloth", 10, 0 }, [2568] = { "Linen Shirt", 200, 2 },
            [300] = { "Pants", 500, 2 }, [400] = { "Thread", 0, 0 } },
  ah = nil, -- set per test
  recipes = {
    [1] = { name = "Bolt", out = 2996, reagents = { { 2589, 2 } } },
    [2] = { name = "Shirt", out = 2568, reagents = { { 2996, 3 } } },
    [3] = { name = "Unbolt", out = 2589, qty = 2, reagents = { { 2996, 1 } } },  -- cycle: bolt -> 2 cloth
    [4] = { name = "Thread", out = 400, qty = 5, reagents = { { 2589, 1 } } },
    [5] = { name = "Pants", out = 300, reagents = { { 400, 2 }, { 2996, 1 }, { 2589, 1 } } },
  },
}

tests["craftable reagents use the cheaper of buy vs craft"] = function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50 }
  Setup(LINEN)
  local by = ByName()
  assert(by.Shirt.cost == 120 and by.Shirt.status == ns.STATUS.SHUFFLE, "crafted bolts: 3 x 40")
  local b = by.Shirt.breakdown[1]
  assert(b.source == "craft" and b.buyUnit == 60 and b.craftUnit == 40)
  assert(by.Bolt.cost == 40, "bolt must not be priced by unbolting its own output")
  assert(by.Unbolt.cost == 40)

  ah[2996] = nil
  by = ByName()
  assert(by.Shirt.cost == 120 and by.Shirt.breakdown[1].buyUnit == nil, "priceable via crafting with no AH listing")

  CraftShufflerDB.settings.craftReagents = false
  assert(ByName().Shirt.status == ns.STATUS.MISSING)

  CraftShufflerDB.settings.craftReagents = true
  ah[2996] = 30
  by = ByName()
  assert(by.Shirt.cost == 90 and by.Shirt.breakdown[1].source == "AH")
end

tests["plan lists buys, crafts in order and leftovers"] = function()
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

  ah[2996], ah[400] = 10, 1
  by = ByName()
  assert(not by.Shirt.usesCrafting and by.Shirt.plan.buys[1].name == "Bolt of Linen Cloth")
end

tests["auction value of the crafted item"] = function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50, [2568] = 400 }
  Setup(LINEN)
  local by = ByName()
  assert(by.Shirt.auctionValue == 400 and by.Shirt.auctionNet == 380)
  assert(by.Shirt.auctionProfit == 380 - by.Shirt.cost)
  assert(by.Thread.auctionValue == 250, "auction value counts the full output quantity (5 x 50)")
  assert(by.Pants.auctionValue == nil and by.Pants.auctionProfit == nil, "never listed -> no auction value")
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
local failed = 0
for _, name in ipairs(names) do
  local ok, err = pcall(tests[name])
  io.write((ok and "PASS  " or "FAIL  ") .. name .. (ok and "" or ("\n      " .. tostring(err))) .. "\n")
  if not ok then failed = failed + 1 end
end
io.write(("%d/%d passed\n"):format(#names - failed, #names))
os.exit(failed == 0 and 0 or 1)
