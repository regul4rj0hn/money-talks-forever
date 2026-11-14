# Money Talks Forever

A World of Warcraft: Forever addon for making gold, using Auctionator's prices:

- **Crafting shuffles:** flags craftable items as **"Shuffle me!"** when their reagents cost less on the Auction House
  than the crafted item sells for to a vendor. It shows a step-by-step buy and craft plan, and creates a shopping list
  with the most you can pay per reagent.
- **Vendor flips:** finds AH listings priced below what a vendor pays for them.
- **AH or vendor:** tells you when listing on the AH beats vendoring, deposit risk included.
- **Profit so far:** tracks what you actually paid and earned from crafts, flips and AH sales, per session, day and
  all time.

Formerly called **CraftShuffler**; see [Upgrading from CraftShuffler](#upgrading-from-craftshuffler).

## How crafting shuffles work

1. Open each of your profession windows once. Money Talks Forever records every learned recipe that produces an item,
   along with its required reagents. This is saved per character, so you don't need to reopen the window afterwards.
2. Run a full Auctionator scan at the Auction House.
3. For each recipe:
   - Crafted items that are soulbound (Bind on Pickup, quest, account-bound) are skipped. Bind on Equip, Bind on Use
     and unbound items are kept.
   - **Reagent cost** = sum over required reagents of `quantity x cheapest unit price`, where the unit price is the
     Auctionator AH price or, if Auctionator has seen it at a merchant and it is cheaper, the NPC vendor price.
     If you know a recipe that makes the reagent itself (e.g. Bolt of Linen Cloth from Linen Cloth), its craft cost
     (reagent cost / quantity made, resolved recursively) is used instead when that is cheaper than buying.
     Optional or finishing reagents are ignored. If a slot accepts several items (e.g. quality ranks), the cheapest
     one is used.
   - **Vendor value** = item vendor sell price x guaranteed minimum output quantity.
   - **Auction value** = Auctionator price of the crafted item x the same quantity, for comparison. It is shown in
     gold when selling on the AH, after the 5% AH cut, beats vendoring. The row tooltip shows the profit for both
     ways of selling. The "Shuffle me!" flag is still based on vendor value only.
   - If `reagent cost < vendor value`, the item is flagged **Shuffle me!**

Prices are re-evaluated automatically whenever Auctionator finishes a scan.

## Install

Download `MoneyTalksForever-vX.Y.Z.zip` from [Releases](https://github.com/regul4rj0hn/money-talks-forever/releases)
and extract it into `World of Warcraft\_forever_\Interface\AddOns\`. The zip contains the `MoneyTalksForever`
folder. To try an older or newer version, replace that folder with the one from another release; your saved data is
kept. Or copy the `MoneyTalksForever` folder from this repo. Requires
[Auctionator](https://www.curseforge.com/wow/addons/auctionator).

### Upgrading from CraftShuffler

Install `MoneyTalksForever` **next to** your old `CraftShuffler` folder and log in once. Your recipes, deposits,
flips and profit history are imported, and CraftShuffler is disabled. Then `/reload` and delete the `CraftShuffler`
folder. The import only happens if Money Talks Forever has no data of its own yet. `/shuffle` still works as a
shortcut for `/mtf`. Releases up to v0.4.0 are called CraftShuffler.

## Usage

| Command | Effect |
|---|---|
| `/mtf` (or `/shuffle`) | Toggle the results window (hover a row for the reagent breakdown, shift-click to link) |
| `/mtf list` | Print every "Shuffle me!" item to chat |
| `/mtf vendor` | Toggle using NPC vendor prices for reagents (default on) |
| `/mtf craft` | Toggle pricing craftable reagents at their own craft cost when cheaper (default on) |
| `/mtf soulbound` | Toggle including soulbound crafts (default off) |
| `/mtf minprofit <gold>` | Minimum profit per craft to be flagged, e.g. `0.5` = 50s |
| `/mtf shop` | Create the Auctionator shopping list `Money Talks Forever` with max prices (same as the **Shopping list** button) |
| `/mtf flips` | Open the Vendor flips tab (AH listings cheaper than their vendor price) |
| `/mtf profit` | Open the Profit tab; `/mtf profit reset` clears this character's profit history |
| `/mtf fullscan` | Full AH scan for vendor flips (at the AH, once per 15 minutes) |
| `/mtf debug` | Print diagnostic info (scan state, Auctionator settings, counts) |
| `/mtf flipmin <gold>` | Minimum profit per flip listing, e.g. `0.01` = 1s |
| `/mtf duration 12\|24\|48` | Auction duration used for deposits (default 12h) |
| `/mtf reset` | Forget this character's recorded recipes |

The **Reagents** column shows `buy all` when every reagent should be bought, or `buy + craft` when it is cheaper to
craft some reagents yourself first. Hover a row for the step-by-step plan:

```
1. Buy:
    6x Linen Cloth                 120c (AH)
2. Craft, in this order:
    3x Bolt of Linen Cloth
    1x Linen Shirt  <- vendor this
Craftable reagents             buy / craft each
    Bolt of Linen Cloth          60c / [40c]
```

Buy quantities are summed across all crafting levels, and leftovers are listed (e.g. a craft that makes 5 thread
when you only need 2). The listed cost spreads a craft's price over everything it makes, so with leftovers it can be
a bit lower than what you spend on one craft. The tooltip shows both numbers when they differ.

Flagged items also get a "Shuffle me!" line in their item tooltip.

## Buying in volume: max prices and the shopping list

For every bought reagent, the row tooltip shows a **max** price: the most you can pay per unit, with the other
reagents at current prices, and still make your minimum profit. **Shopping list** (or `/mtf shop`) creates an
Auctionator shopping list called `Money Talks Forever`. It holds every AH reagent of your "Shuffle me!" recipes, each capped
at its highest max price across those recipes. At the AH, search the list and buy **every listing up to the max
price**, not just one craft's worth. Reagents bought from NPC vendors are printed in chat instead.

Auctionator applies the cap to an item's cheapest listing. When you open an item, more expensive listings are still
shown, so stop buying at the max price.

## Vendor flips

Sometimes items are listed on the AH for less than a vendor pays for them. Buy them and sell them to any NPC for a
risk-free profit, no crafting needed. The **Vendor flips** tab (`/mtf flips`) lists every such item from the last
**full** Auctionator scan. For each item it shows the number of listings, the quantity, the most to pay per unit, the
total cost and the profit.

- At the AH, click **Full scan** on the Vendor flips tab (or `/mtf fullscan`). This downloads every listing, and
  Money Talks Forever compares each listing's unit price with the vendor price. Bid-only and your own auctions are skipped.
  The AH allows one full scan every 15 minutes, shared with Auctionator.
  A progress bar next to the button shows each step. **Waiting** for the AH to send the listings has no progress
  from the game, so it shows elapsed time and gives up after 90s. **Reading** shows listings read out of the total.
  **Loading details** counts down while the game loads items it didn't know yet, then reads again, up to 3 times.
- Auctionator's own **Scan** button only does a full scan if *Use alternate slower scan mode by default* is ticked
  in Auctionator's Advanced settings. It is off by default, and then Auctionator runs incremental scans. Those don't
  include individual listings and can't find flips. With the option on, flips update after every Auctionator scan.
- **Shopping list** on this tab creates the Auctionator list `Money Talks Forever Flips`, capping each item at the highest
  profitable unit price.
- Results are a snapshot of the scan, so other players may buy some listings first. The tab shows how old the scan is.
- `/mtf flipmin <gold>` sets the minimum profit per listing (default 1 copper).

## Profit so far

The **Profit** tab (`/mtf profit`) shows what you actually made. It uses the prices you paid and the money vendors
gave you, not estimates. It shows this session, today and all time, separately for **Crafts** and **Flips**, plus your
gold per hour this session. Hover a number for items sold, vendor money, cost and how much of the cost is estimated.

How it's tracked, per character:

- **Buying** on the AH (through Auctionator or Blizzard's UI) or from an NPC vendor puts the item in stock at the
  price you paid.
- **Crafting** a recorded recipe uses its reagents from stock and puts the crafted item in stock at their cost.
  Crafted reagents like bolts carry their cost into the next craft.
- **Listing on the AH** records the deposit you paid, for items the addon tracks.
- **Selling on the AH**: when you collect the gold from an *Auction successful* mail, profit = sale price - AH cut -
  stock cost. A deposit paid back with the payout costs nothing. When you take an item back from an
  *Auction expired* or *Auction cancelled* mail, that listing's deposit counts as a cost. This works however you open
  mail (one by one, Open All, or a mail addon).
- **Selling to a vendor** realizes profit = what the vendor paid - stock cost. Sold items that were crafted count as
  Crafts; items sold as bought count as Flips. Items the addon never saw being bought or crafted, like loot and junk,
  are ignored.
- Reagents you used without buying them while tracking (farmed, or bought before installing) are valued at the
  current market price and reported as **estimated** cost.

After each vendor or mailbox visit, chat shows the profit from tracked items. The per-item list shows whether each
item sold to vendors, on the AH or both, and hovering a total shows the split and any deposits lost.
**Reset** clears the history for the current character.

## AH or vendor?

The **Sell via** column says `vendor`, or `AH 14%+`. The second means listing on the AH beats vendoring if the item
sells at least 14% of the time. Unsold auctions come back by mail and can still be vendored, so listing only risks the
deposit:

```
list on the AH if  chance it sells  >  deposit / (AH price after cut - vendor value + deposit)
```

Deposits are read from the game whenever the AH is open, for crafted items in your bags or AH commodities. Until then
the deposit is estimated at 15% of the vendor price per 12h and marked `est.` in the tooltip. This verdict does not
depend on reagent cost.

## Development

`lua tests/run.lua` runs offline tests of the scanning and pricing logic against a mocked WoW API.
`scripts/check-globals.sh` fails if the addon uses a global name that isn't a known WoW API. That catches calls to a
`local function` defined further down a file, which only break in game. Both run before every release.

### Releases

Versions follow semver, starting at 0.x until the addon is proven in game. Add every change to `## [Unreleased]` in
[CHANGELOG.md](CHANGELOG.md), then:

```
scripts/release.sh patch|minor|major      # bump TOC version, date the changelog, commit, tag vX.Y.Z
git push origin main && git push origin vX.Y.Z   # or pass --push to the script
```

Pushing a `v*` tag runs [the release workflow](.github/workflows/release.yml). It runs the tests, checks the tag
matches the TOC version, and publishes a GitHub release with the zip and that version's changelog notes.
If a tag ever ends up without a release, run the workflow by hand: `gh workflow run release.yml -f tag=vX.Y.Z`.

## Notes

- The TOC targets `## Interface: 16001`. If the client reports the addon as out of date after a patch, bump this.
- AH prices are Auctionator's last-scan minimum buyout. Buying many units will push the real cost above that.
