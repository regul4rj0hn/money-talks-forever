# CraftShuffler

A World of Warcraft: Forever addon that flags craftable items as **"Shuffle me!"** when the reagents cost less on the
Auction House than the crafted item sells for at an NPC vendor.

## How it works

1. Open each of your profession windows once. CraftShuffler records every learned recipe that produces an item,
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

Copy the `CraftShuffler` folder to `World of Warcraft\_forever_\Interface\AddOns\`. Requires
[Auctionator](https://www.curseforge.com/wow/addons/auctionator).

## Usage

| Command | Effect |
|---|---|
| `/shuffle` | Toggle the results window (hover a row for the reagent breakdown, shift-click to link) |
| `/shuffle list` | Print every "Shuffle me!" item to chat |
| `/shuffle vendor` | Toggle using NPC vendor prices for reagents (default on) |
| `/shuffle craft` | Toggle pricing craftable reagents at their own craft cost when cheaper (default on) |
| `/shuffle soulbound` | Toggle including soulbound crafts (default off) |
| `/shuffle minprofit <gold>` | Minimum profit per craft to be flagged, e.g. `0.5` = 50s |
| `/shuffle reset` | Forget this character's recorded recipes |

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

## Development

`lua tests/run.lua` runs offline tests of the scanning and pricing logic against a mocked WoW API.

## Notes

- The TOC targets `## Interface: 16001`. If the client reports the addon as out of date after a patch, bump this.
- AH prices are Auctionator's last-scan minimum buyout. Buying many units will push the real cost above that.
