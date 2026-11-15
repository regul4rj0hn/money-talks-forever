-- Money Talks Forever: AH sales income and lost deposits, from the mailbox.
--
-- While the mailbox is open we keep a snapshot of AH mails and compare it after every inbox update:
--   * an "Auction successful" mail (seller invoice) whose gold was collected -> AH sale
--     income = sale price - AH cut (from the invoice); a deposit paid back with the payout is not a cost
--   * an "Auction expired" / "Auction cancelled" mail whose item was taken -> that listing's deposit is lost
-- Comparing snapshots works however the mail is opened (Blizzard's Open All, mail addons, one by one).
local _, ns = ...

-- Turns a GlobalStrings format like "Auction expired: %s" into a Lua pattern capturing the item name.
local function SubjectPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
  p = p:gsub("%%s", "(.+)")
  return "^" .. p .. "$"
end

local RETURNED_PATTERNS -- built on first use, after the client's strings are loaded
local function ReturnedPatterns()
  if not RETURNED_PATTERNS then
    RETURNED_PATTERNS = {}
    for _, fmt in ipairs({
      AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s",
      AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s",
    }) do
      local p = SubjectPattern(fmt)
      if p then table.insert(RETURNED_PATTERNS, p) end
    end
  end
  return RETURNED_PATTERNS
end

local function IsReturnedSubject(subject)
  if not subject then return false end
  for _, p in ipairs(ReturnedPatterns()) do
    if subject:match(p) then return true end
  end
  return false
end

-- Invoices only carry the item name: { [name] = itemID } of everything tracked (stock and listed deposits).
local function TrackedNames()
  local L, names = ns.Ledger(), {}
  for _, stock in ipairs({ L.deposits or {}, L.bought, L.crafted }) do
    for id in pairs(stock) do
      local name = C_Item.GetItemInfo(id)
      if name then names[name] = id end
    end
  end
  return names
end

-- key -> { n = how many identical mails, entry = details }
local function Snapshot()
  local snap = {}
  local function add(key, entry)
    local s = snap[key]
    if s then s.n = s.n + 1 else snap[key] = { n = 1, entry = entry } end
  end
  for i = 1, (GetInboxNumItems and GetInboxNumItems() or 0) do
    local _, _, _, subject, money, _, _, hasItem = GetInboxHeaderInfo(i)
    local invoiceType, itemName, _, bid, _, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
    if invoiceType == "seller" and money and money > 0 and itemName then
      count = count or 1
      add(("S|%s|%d|%d|%d|%d"):format(itemName, bid or 0, consignment or 0, count, money), {
        kind = "sale", itemName = itemName, bid = bid or 0, consignment = consignment or 0,
        deposit = deposit or 0, count = count, money = money,
      })
    elseif hasItem and IsReturnedSubject(subject) then
      local name, itemID, _, itemCount = GetInboxItem(i, 1)
      if name then
        add(("R|%s|%d"):format(tostring(itemID or name), itemCount or 1),
          { kind = "returned", itemID = itemID, itemName = name, count = itemCount or 1 })
      end
    end
  end
  return snap
end

local snapshot   -- while the mailbox is open
local visit      -- totals for this mailbox visit, printed on close

local function Process(e, names)
  local itemID = e.itemID or names()[e.itemName]
  if not itemID then return end
  if e.kind == "sale" then
    local net = e.bid - e.consignment
    local refund = math.max(0, e.money - net)
    local profit = ns.RecordAHSale(itemID, e.count, net, refund, e.deposit)
    if profit then
      visit.sales = visit.sales + 1
      visit.earned = visit.earned + net
      visit.profit = visit.profit + profit
    end
  else
    local lost = ns.RecordAuctionReturned(itemID, e.count)
    if lost > 0 then
      visit.returned = visit.returned + 1
      visit.lost = visit.lost + lost
    end
  end
end

function ns.OnInboxUpdate()
  if not snapshot then return end
  local new = Snapshot()
  local cached
  local function names() cached = cached or TrackedNames(); return cached end -- built only if something was taken
  for key, old in pairs(snapshot) do
    local remaining = new[key] and new[key].n or 0
    for _ = 1, old.n - remaining do Process(old.entry, names) end
  end
  snapshot = new
end

function ns.OnMailShow()
  snapshot = Snapshot()
  visit = { sales = 0, earned = 0, profit = 0, returned = 0, lost = 0 }
end

function ns.OnMailClosed()
  if not snapshot then return end
  ns.OnInboxUpdate()
  snapshot = nil
  if ns.Settings().chatAlert and (visit.sales > 0 or visit.returned > 0) then
    local parts = {}
    if visit.sales > 0 then
      table.insert(parts, ("%d AH sale(s) collected, %s, |cff00ff00%s profit|r"):format(
        visit.sales, ns.Money(visit.earned), ns.Money(visit.profit)))
    end
    if visit.returned > 0 then
      table.insert(parts, ("%d auction(s) came back, %s deposit lost"):format(visit.returned, ns.Money(visit.lost)))
    end
    ns.Print("mailbox: " .. table.concat(parts, "; ") .. (" (session %s)"):format(ns.Money(ns.BucketProfit(ns.session))))
  end
end

ns.On("MAIL_SHOW", ns.OnMailShow)
ns.On("MAIL_INBOX_UPDATE", ns.OnInboxUpdate)
ns.On("MAIL_CLOSED", ns.OnMailClosed)
