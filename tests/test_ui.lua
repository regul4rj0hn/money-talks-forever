-- Tests: UI smoke test. Builds the real window with mocked widgets, opens every tab, draws every row, hovers
-- everything that has a tooltip and clicks every button. Catches nil errors and typos in UI code, and checks the
-- texts users see. It doesn't depend on how the UI is laid out internally.
local T = ...
local ns, W, flush = T.ns, T.W, T.flush
local Setup, LINEN = T.Setup, T.LINEN

local function Slash(msg) SlashCmdList.MONEYTALKSFOREVER(msg) end

local function Visible(w)
  return w.shown ~= false
end

-- Hover every widget with an OnEnter handler that is visible right now; returns all tooltip lines seen.
local function HoverAll()
  local seen = {}
  for _, w in ipairs(T.widgets) do
    if w.scripts.OnEnter and Visible(w) then
      GameTooltip.lines = {}
      w.scripts.OnEnter(w)
      for _, l in ipairs(GameTooltip.lines or {}) do table.insert(seen, l) end
      if w.scripts.OnLeave then w.scripts.OnLeave(w) end
    end
  end
  return table.concat(seen, "\n")
end

local TAB_LABELS = { ["Crafts"] = true, ["Vendor flips"] = true, ["Profit"] = true }

-- Clicks every visible button except tab switches (tabs are opened explicitly, so the current tab stays put).
local function ClickAll()
  -- Copy first: clicking can create widgets (e.g. a tab's rows).
  local buttons = {}
  for _, w in ipairs(T.widgets) do
    if w.scripts.OnClick and Visible(w) then table.insert(buttons, w) end
  end
  for _, b in ipairs(buttons) do
    if not TAB_LABELS[b.text] then b.scripts.OnClick(b, "LeftButton") end
  end
  flush()
end

local function AllText()
  local t = {}
  for _, w in ipairs(T.widgets) do
    if w.text and Visible(w) then table.insert(t, tostring(w.text)) end
  end
  return table.concat(t, "\n")
end

local function Has(hay, needle, what)
  assert(hay:find(needle, 1, true), ("%s: expected to find %q"):format(what, needle))
end

T.Test("ui: every tab renders, rows and tooltips draw, buttons click", function()
  LINEN.ah = { [2589] = 20, [2996] = 60, [400] = 50, [2568] = 400 }
  Setup(LINEN)
  ns.session = ns.NewLedgerBucket()
  W.money, W.bag, W.inbox = 100000, {}, {}
  ns.ahOpen = false

  -- Crafts tab
  Slash("")
  flush()
  local text = AllText()
  Has(text, "Money Talks Forever v", "window title")
  Has(text, "Shuffle me!", "crafts status column")
  Has(text, "buy + craft", "reagents column")
  local tips = HoverAll()
  Has(tips, "1. Buy:", "crafts row tooltip")
  Has(tips, "Craft, in this order", "crafts row tooltip")
  Has(tips, "Recipe: Shirt", "crafts row tooltip")
  ClickAll() -- Full scan needs the AH and just prints here
  assert(W.createdLists["Money Talks Forever"], "Shopping list button on the crafts tab")

  -- Flips tab: empty, then with results and each progress phase
  ns.flips = { items = {}, listings = 0 }
  W.replicate, ns.lastScanIncremental = {}, false
  Slash("flips")
  flush()
  Has(AllText(), "No full scan yet", "flips empty state")
  W.replicate = { { 2568, 1, 150 }, { 2996, 5, 25 } }
  ns.ScanReplicateForFlips(true)
  flush()
  Slash("flips")
  text = AllText()
  Has(text, "2 flips", "flips summary")
  tips = HoverAll()
  Has(tips, "Vendor flip", "flips row tooltip")
  for _, p in ipairs({
    { phase = "waiting", startedAt = GetTime(), timeout = 90 },
    { phase = "reading", done = 2000, total = 5000, attempt = 2 },
    { phase = "loading", skipped = 7, attempt = 2, retryAt = GetTime() + 5 },
  }) do
    ns.flipProgress = p
    for _, w in ipairs(T.widgets) do
      if w.scripts.OnUpdate then w.scripts.OnUpdate(w, 1) end
    end
  end
  Has(AllText(), "Loading details for 7 listing(s)", "progress bar text")
  ns.flipProgress = nil
  ClickAll()
  assert(W.createdLists["Money Talks Forever Flips"], "Shopping list button on the flips tab")

  -- Profit tab: empty, then after a sale
  Slash("profit")
  Has(AllText(), "Nothing sold yet", "profit empty state")
  ns.RecordPurchase(2996, 5, 25)
  ns.RecordVendorSale(2996, 5, 50)
  Slash("profit")
  flush()
  text = AllText()
  Has(text, "This session", "profit summary header")
  Has(text, "flip", "profit per-item row")
  tips = HoverAll()
  Has(tips, "Items sold", "profit cell tooltip")
  ClickAll()
  assert(W.popups[#W.popups] == "MONEYTALKSFOREVER_RESET_LEDGER", "Reset asks for confirmation")
  StaticPopupDialogs.MONEYTALKSFOREVER_RESET_LEDGER.OnAccept()
  assert(ns.BucketProfit(ns.Ledger().all) == 0, "confirmed reset clears the ledger")

  -- Tab buttons switch tabs
  for _, w in ipairs(T.widgets) do
    if TAB_LABELS[w.text] and w.scripts.OnClick then w.scripts.OnClick(w, "LeftButton") end
  end
  flush()

  -- Every slash command runs without errors
  for _, cmd in ipairs({ "help", "list", "vendor", "vendor", "craft", "craft", "soulbound", "soulbound",
                         "minprofit 0.01", "minprofit x", "flipmin 0.01", "flipmin", "duration 24", "duration 7",
                         "shop", "debug", "fullscan", "profit reset", "nonsense" }) do
    Slash(cmd)
  end
  flush()
  Slash("") -- toggle closed
end)
