-- Money Talks Forever: everything that talks to Auctionator's public API (Auctionator.API.v1).
local _, ns = ...

function ns.AuctionatorAPI()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end

local function PositivePrice(fn, itemID)
  local v = ns.SafeNumber(fn, ns.CALLER_ID, itemID)
  return v and v > 0 and v or nil
end

-- Lowest AH buyout from Auctionator's last scan, per unit. nil if never seen.
function ns.AuctionPrice(itemID)
  local api = ns.AuctionatorAPI()
  return api and PositivePrice(api.GetAuctionPriceByItemID, itemID)
end

-- What an NPC vendor sells the item for, if Auctionator has seen it at a merchant. nil otherwise.
function ns.VendorBuyPrice(itemID)
  local api = ns.AuctionatorAPI()
  return api and PositivePrice(api.GetVendorPriceByItemID, itemID)
end

-- Creates (or replaces) an Auctionator shopping list.
-- terms = { { name = "Linen Cloth", maxPrice = copper or nil }, ... }
-- Returns the number of items added, or nil and an error message.
function ns.CreateAuctionatorList(listName, terms)
  local api = ns.AuctionatorAPI()
  if not api or not api.CreateShoppingList or not api.ConvertToSearchString then
    return nil, "Auctionator shopping lists are not available."
  end
  local searchStrings = {}
  for _, t in ipairs(terms) do
    local ok, s = pcall(api.ConvertToSearchString, ns.CALLER_ID,
      { searchString = t.name, isExact = true, maxPrice = t.maxPrice })
    if ok and type(s) == "string" then table.insert(searchStrings, s) end
  end
  if #searchStrings == 0 then return 0 end
  local ok, err = pcall(api.CreateShoppingList, ns.CALLER_ID, listName, searchStrings)
  if not ok then return nil, "could not create shopping list: " .. tostring(err) end
  return #searchStrings
end

-- Auctionator calls back after full and incremental scans; we turn that into the MTF_PRICES_UPDATED message.
ns.On("PLAYER_LOGIN", function()
  local api = ns.AuctionatorAPI()
  if not api then
    ns.Print("Auctionator not found - prices are unavailable. Install/enable Auctionator and scan the AH.")
    return
  end
  if not api.RegisterForDBUpdate then return end
  local ok, err = pcall(api.RegisterForDBUpdate, ns.CALLER_ID, function() ns.Fire("MTF_PRICES_UPDATED") end)
  if not ok then ns.Print("could not register for Auctionator updates:", tostring(err)) end
end)
