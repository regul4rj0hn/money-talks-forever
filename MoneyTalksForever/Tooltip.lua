-- Money Talks Forever: a "Shuffle me!" line on the item tooltip of every flagged crafted item.
local _, ns = ...

local function AddShuffleLines(tooltip, itemID)
  local res = itemID and ns.flaggedByItem[itemID]
  if not res then return end
  tooltip:AddLine(" ")
  tooltip:AddDoubleLine(ns.Colorize("Money Talks: Shuffle me!", ns.COLOR.GREEN), "+" .. ns.Money(res.profit) .. " / craft")
  tooltip:AddDoubleLine("  reagents (AH)", ns.Money(res.cost), 0.8, 0.8, 0.8, 1, 1, 1)
  tooltip:AddDoubleLine("  vendor value x" .. res.qty, ns.Money(res.vendorValue), 0.8, 0.8, 0.8, 1, 1, 1)
end

ns.On("PLAYER_LOGIN", function()
  if TooltipDataProcessor and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if data and data.id then AddShuffleLines(tooltip, data.id) end
    end)
  elseif GameTooltip:HasScript("OnTooltipSetItem") then
    -- Older clients without TooltipDataProcessor
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
      local _, link = tooltip:GetItem()
      AddShuffleLines(tooltip, link and C_Item.GetItemInfoInstant(link))
    end)
  end
end)
