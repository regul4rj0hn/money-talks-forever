-- Money Talks Forever: one event frame for the whole addon.
--   ns.On(event, fn)      fn(...) runs for the game event, in registration (= file load) order
--   ns.Fire(message, ...) addon-internal messages, named "MTF_*", use the same handlers
local _, ns = ...

local handlers = {}
local frame = CreateFrame("Frame")

local function IsInternal(event) return event:sub(1, 4) == "MTF_" end

function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    if not IsInternal(event) then frame:RegisterEvent(event) end
  end
  table.insert(handlers[event], fn)
end

local function Dispatch(event, ...)
  for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end

function ns.Fire(message, ...)
  assert(IsInternal(message), "ns.Fire is for internal MTF_* messages")
  Dispatch(message, ...)
end

frame:SetScript("OnEvent", function(_, event, ...) Dispatch(event, ...) end)
