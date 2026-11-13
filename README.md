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

The row tooltip marks each reagent as `(craft)`, `(vendor)` or AH-priced, and for craftable reagents shows the buy
vs. craft price side by side.

Flagged items also get a "Shuffle me!" line in their item tooltip.

## Notes

- The TOC targets `## Interface: 16001`. If the client reports the addon as out of date after a patch, bump this.
- AH prices are Auctionator's last-scan minimum buyout. Buying many units will push the real cost above that.
