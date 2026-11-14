-- Money Talks Forever: records learned recipes + their required reagents when a profession window is open.
local _, ns = ...

-- Profession windows fire several events while loading; scan once they settle.
local function RequestScan()
  ns.Debounce("scan", 0.5, ns.ScanOpenProfession)
end
ns.On("TRADE_SKILL_SHOW", RequestScan)
ns.On("TRADE_SKILL_LIST_UPDATE", RequestScan)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", RequestScan)

local function CanScan()
  local TS = C_TradeSkillUI
  if not TS or not TS.GetAllRecipeIDs then return false end
  if TS.IsTradeSkillReady and not TS.IsTradeSkillReady() then return false end
  -- Don't record someone else's profession (linked / guild / NPC crafting windows).
  if TS.IsTradeSkillLinked and TS.IsTradeSkillLinked() then return false end
  if TS.IsTradeSkillGuild and TS.IsTradeSkillGuild() then return false end
  if TS.IsNPCCrafting and TS.IsNPCCrafting() then return false end
  return true
end

-- A reagent slot counts as "required" if the API says so; otherwise fall back to the Basic reagent type.
local function IsRequiredSlot(slot)
  if slot.required ~= nil then return slot.required end
  local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
  return basic ~= nil and slot.reagentType == basic
end

local function BuildReagents(schematic)
  local reagents = {}
  for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
    if IsRequiredSlot(slot) and (slot.quantityRequired or 0) > 0 then
      local entry = { qty = slot.quantityRequired, items = {} }
      for _, reagent in ipairs(slot.reagents or {}) do
        if reagent.itemID then
          table.insert(entry.items, reagent.itemID)   -- several IDs = interchangeable options (e.g. quality ranks)
        elseif reagent.currencyID then
          entry.currencyID = reagent.currencyID       -- cannot be bought on the AH
        end
      end
      if #entry.items > 0 or entry.currencyID then
        table.insert(reagents, entry)
      end
    end
  end
  return reagents
end

local lastCount = {} -- [profession] = recipes recorded last time, to announce only changes

function ns.ScanOpenProfession()
  if not CanScan() then return end
  local TS = C_TradeSkillUI

  local profInfo = TS.GetBaseProfessionInfo and TS.GetBaseProfessionInfo()
  local profName = (profInfo and profInfo.professionName) or "Unknown"
  local found, count = {}, 0
  for _, recipeID in ipairs(TS.GetAllRecipeIDs() or {}) do
    local info = TS.GetRecipeInfo(recipeID)
    if info and info.learned and not info.isRecraft and not info.isSalvageRecipe
        and not info.isGatheringRecipe and not info.isDummyRecipe then
      local schematic = TS.GetRecipeSchematic(recipeID, false)
      if schematic and schematic.outputItemID then
        local reagents = BuildReagents(schematic)
        if #reagents > 0 then
          found[recipeID] = {
            name = info.name,
            profession = profName,
            outputItemID = schematic.outputItemID,
            qtyMin = schematic.quantityMin or 1,
            qtyMax = schematic.quantityMax or schematic.quantityMin or 1,
            reagents = reagents,
          }
          count = count + 1
        end
      end
    end
  end

  -- An empty list usually means the window is still loading: keep what we had.
  if count == 0 then return end
  local recipes = ns.CharStore().recipes
  for id, r in pairs(recipes) do
    if r.profession == profName then recipes[id] = nil end
  end
  for id, r in pairs(found) do recipes[id] = r end

  if lastCount[profName] ~= count then
    lastCount[profName] = count
    ns.Print(("recorded %d %s recipes."):format(count, profName))
  end
  ns.RequestEvaluate(0.5)
end
