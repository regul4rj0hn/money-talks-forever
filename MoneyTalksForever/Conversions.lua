-- Money Talks Forever: item conversions anyone can do by right-clicking the item, no profession needed.
--
-- They are priced exactly like recorded recipes (Pricing.lua), so the same code finds:
--   * arbitrage: buy 1 Greater Magic Essence, split it into 3 Lesser, list those ("List me!" in the Crafts tab)
--   * cheaper reagents: a recipe that needs a Greater essence can use 3 Lesser ones combined
-- and the ledger records a conversion like a craft when you use the item (see Ledger.lua).
local _, ns = ...

ns.CONVERT_PROFESSION = "Convert"

-- Enchanting essences: 3 lesser <-> 1 greater, both ways.
local ESSENCES = {
  { lesser = 10938, greater = 10939 }, -- Magic
  { lesser = 10998, greater = 11082 }, -- Astral
  { lesser = 11134, greater = 11135 }, -- Mystic
  { lesser = 11174, greater = 11175 }, -- Nether
  { lesser = 16202, greater = 16203 }, -- Eternal
}

-- Same shape as a recorded recipe (Scanner.lua), plus the item you use and the verb for its name.
local function Conversion(verb, input, inputQty, output, outputQty)
  return { verb = verb, input = input, profession = ns.CONVERT_PROFESSION, conversion = true,
           outputItemID = output, qtyMin = outputQty, qtyMax = outputQty,
           reagents = { { qty = inputQty, items = { input } } } }
end

-- Keyed like recorded recipes, by negative output item ID (recorded recipe IDs are positive spell IDs).
local conversions = {}
for _, e in ipairs(ESSENCES) do
  conversions[-e.greater] = Conversion("Combine", e.lesser, 3, e.greater, 1)
  conversions[-e.lesser] = Conversion("Split", e.greater, 1, e.lesser, 3)
end

-- All conversions, { [key] = recipe }. Names use the item names, which load from the server on first use.
function ns.Conversions()
  for _, r in pairs(conversions) do r.name = r.verb .. " " .. ns.ItemName(r.input) end
  return conversions
end

-- The conversion an item-use spell performs. Spell IDs come from the items themselves, so none are hardcoded;
-- items whose data isn't loaded yet are looked up again on the next cast.
local bySpell, unresolved = {}, true
function ns.ConversionBySpell(spellID)
  if unresolved and C_Item.GetItemSpell then
    unresolved = false
    for _, r in pairs(conversions) do
      local _, id = C_Item.GetItemSpell(r.input)
      if id then bySpell[id] = r else unresolved = true end
    end
  end
  return bySpell[spellID]
end
