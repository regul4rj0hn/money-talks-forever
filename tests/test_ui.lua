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

-- Clicks every visible button except tab switches (side tabs, the Overview's icons and rows: they have a tabKey).
-- Tabs are opened explicitly instead, so the current tab stays put.
local function ClickAll()
  -- Copy first: clicking can create widgets (e.g. a tab's rows).
  local buttons = {}
  for _, w in ipairs(T.widgets) do
    if w.scripts.OnClick and Visible(w) then table.insert(buttons, w) end
  end
  for _, b in ipairs(buttons) do
    if not b.tabKey then b.scripts.OnClick(b, "LeftButton") end
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

  -- Overview: the default tab
  ns.flips = { items = {}, listings = 0 }
  Slash("")
  flush()
  local text = AllText()
  Has(text, "Money Talks Forever v", "window title")
  Has(text, "Profit so far", "overview profit box")
  Has(text, "This session", "overview profit grid")
  Has(text, "[Linen Shirt]", "overview best craft")
  Has(text, "3 no profit", "overview crafts status")
  Has(text, "No full scan yet", "overview flips empty state")
  local tips = HoverAll()
  Has(tips, "Recipe: Shirt", "overview craft row uses the crafts tooltip")
  Has(tips, "Items sold", "profit cell tooltip")
  ClickAll()
  assert(W.createdLists["Money Talks Forever"], "Shopping list icon on the overview")
  W.createdLists = {}

  -- Crafts tab
  ns.ShowTab("crafts")
  flush()
  text = AllText()
  Has(text, "All crafts", "overview link to the crafts tab")
  Has(text, "Shuffle me!", "crafts status column")
  Has(text, "buy + craft", "reagents column")
  tips = HoverAll()
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
  Has(tips, "Flip", "flips row tooltip")
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
  ns.ShowTab("overview")
  Has(AllText(), "2 flips", "overview flips status")

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
  W.popups = {}
  ClickAll()
  local asked = {}
  for _, p in ipairs(W.popups) do asked[p] = true end
  assert(asked.MONEYTALKSFOREVER_RESET_SESSION and asked.MONEYTALKSFOREVER_RESET_LEDGER, "clear buttons ask first")
  assert(ns.BucketProfit(ns.session) == 25 and ns.BucketProfit(ns.Ledger().all) == 25, "nothing cleared before confirming")
  StaticPopupDialogs.MONEYTALKSFOREVER_RESET_SESSION.OnAccept()
  assert(ns.BucketProfit(ns.session) == 0 and ns.sessionStart == nil, "clear session")
  assert(ns.BucketProfit(ns.Ledger().all) == 25, "clear session keeps all time")
  StaticPopupDialogs.MONEYTALKSFOREVER_RESET_LEDGER.OnAccept()
  assert(ns.BucketProfit(ns.Ledger().all) == 0, "clear all clears the ledger")

  -- Side tabs, overview icons and overview rows switch tabs
  local switched = {}
  for _, w in ipairs(T.widgets) do
    if w.tabKey and w.scripts.OnClick then
      w.scripts.OnClick(w, "LeftButton")
      flush()
      assert(ns.Settings().tab == w.tabKey, "clicking opens tab " .. w.tabKey)
      switched[w.tabKey] = true
    end
  end
  for _, key in ipairs({ "overview", "crafts", "flips", "profit" }) do assert(switched[key], "no way to open " .. key) end

  -- Every slash command runs without errors
  for _, cmd in ipairs({ "help", "list", "vendor", "vendor", "craft", "craft", "soulbound", "soulbound",
                         "minprofit 0.01", "minprofit x", "flipmin 0.01", "flipmin", "duration 24", "duration 7",
                         "shop", "debug", "fullscan", "profit session", "profit reset", "nonsense" }) do
    Slash(cmd)
  end
  flush()
  Slash("") -- toggle closed
end)
