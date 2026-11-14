-- Offline tests for Money Talks Forever, using a mocked WoW API (tests/mocks.lua).
-- Run from the repo root:  lua tests/run.lua
local T = dofile("tests/mocks.lua")

local FILES = { "pricing", "flips", "ledger", "mail", "migration", "ui" }
for _, name in ipairs(FILES) do
  local path = "tests/test_" .. name .. ".lua"
  local chunk = loadfile(path)
  if chunk then chunk(T) elseif name ~= "ui" then error("missing " .. path) end
end

local names = {}
for name in pairs(T.tests) do names[#names + 1] = name end
table.sort(names)

local failed = 0
for _, name in ipairs(names) do
  local ok, err = pcall(T.tests[name])
  io.write((ok and "PASS  " or "FAIL  ") .. name .. (ok and "" or ("\n      " .. tostring(err))) .. "\n")
  if not ok then failed = failed + 1 end
end
io.write(("%d/%d passed\n"):format(#names - failed, #names))
os.exit(failed == 0 and 0 or 1)
