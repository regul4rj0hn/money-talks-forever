-- Money Talks Forever: records learned recipes + their required reagents when a profession window is open.
local _, ns = ...

local scanPending = false
function ns.RequestScan()
  if scanPending then return end
  scanPending = true
  C_Timer.After(0.5, function()
    scanPending = false
    ns.ScanOpenProfession()
  end)
end

local function CanScan()
  local T = C_TradeSkillUI
  if not T or not T.GetAllRecipeIDs then return false end
  if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return false end
  -- Don't record someone else's profession (linked / guild / NPC crafting windows).
  if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end
  if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return false end
  if T.IsNPCCrafting and T.IsNPCCrafting() then return false end
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

function ns.ScanOpenProfession()
  if not CanScan() then return end
  local T = C_TradeSkillUI

  local profInfo = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
  local profName = (profInfo and profInfo.professionName) or "Unknown"
  local recipes = ns.CharStore().recipes

  -- Drop what we had for this profession; it will be re-recorded from the live list.
  for id, r in pairs(recipes) do
    if r.profession == profName then recipes[id] = nil end
  end

  local count = 0
  for _, recipeID in ipairs(T.GetAllRecipeIDs() or {}) do
    local info = T.GetRecipeInfo(recipeID)
    if info and info.learned and not info.isRecraft and not info.isSalvageRecipe
        and not info.isGatheringRecipe and not info.isDummyRecipe then
      local schematic = T.GetRecipeSchematic(recipeID, false)
      if schematic and schematic.outputItemID then
        local reagents = BuildReagents(schematic)
        if #reagents > 0 then
          recipes[recipeID] = {
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

  if ns.lastScanCount ~= (profName .. count) then
    ns.lastScanCount = profName .. count
    ns.Print(("recorded %d %s recipes."):format(count, profName))
  end
  ns.RequestEvaluate(0.5)
end
