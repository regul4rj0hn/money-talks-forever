-- Money Talks Forever: a "Shuffle me!" / "List me!" line on the item tooltip of every profitable crafted item.
local _, ns = ...

local function AddShuffleLines(tooltip, itemID)
  local res = itemID and ns.flaggedByItem[itemID]
  if not res then return end
  tooltip:AddLine(" ")
  tooltip:AddDoubleLine("Money Talks: " .. ns.StatusText(res.status), "+" .. ns.Money(res.bestProfit) .. " / craft")
  tooltip:AddDoubleLine("  reagents (AH)", ns.Money(res.cost), 0.8, 0.8, 0.8, 1, 1, 1)
  if res.status == ns.STATUS.LIST then
    tooltip:AddDoubleLine("  AH value x" .. res.qty .. " after cut", ns.Money(res.auctionNet), 0.8, 0.8, 0.8, 1, 1, 1)
  else
    tooltip:AddDoubleLine("  vendor value x" .. res.qty, ns.Money(res.vendorValue), 0.8, 0.8, 0.8, 1, 1, 1)
  end
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
