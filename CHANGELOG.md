# Changelog

All notable changes to Money Talks Forever (called CraftShuffler up to v0.4.0). Versions follow [Semantic Versioning](https://semver.org/):
MAJOR for breaking changes (e.g. saved data that no longer loads), MINOR for new features, PATCH for fixes.
Each version is a [GitHub release](https://github.com/regul4rj0hn/money-talks-forever/releases) with a ready-to-install zip.

## [Unreleased]

## [0.5.0] - 2026-11-14

### Fixed
- Opening a profession window while the game was still loading its recipe list could erase that profession's
  recorded recipes.
- The globals check before releases now also covers files in subfolders.

### Changed
- **Renamed to Money Talks Forever.** The addon folder is now `MoneyTalksForever`, the command is `/mtf` (`/shuffle`
  still works), and the Auctionator shopping lists are `Money Talks Forever` and `Money Talks Forever Flips`. The
  GitHub repository is now `money-talks-forever`.
- MIT license, also included in the release zip as `LICENSE.txt`.
- Code reorganized into smaller modules (see *Code layout* in the README), with a single event dispatcher, shared
  helpers and one file per window tab. Slash command help is generated from the command list.
- Faster on busy auction houses: deposits are only measured for items without a known deposit, and only once per
  burst of bag updates. The flips scan looks up each item once per pass instead of once per listing, and only reads
  listing links for equippable items.
- The crafting plan says "sell this (see above)" instead of "vendor this" when listing on the AH is the better bet.
- Existing CraftShuffler data is imported on first login when the old addon is still installed, and CraftShuffler is
  then disabled.

## [0.4.0] - 2026-11-14

### Added
- Profit tracking includes **AH sales**. Income comes from *Auction successful* mail when you collect it (sale price
  minus AH cut), and deposits are recorded when listing. A deposit lost on an expired or cancelled auction counts as
  a cost. The Profit tab shows vendor vs AH sales and deposits lost, and a chat summary prints after each mailbox
  visit.
- `scripts/check-globals.sh`, run before every release: fails if the addon uses an unknown global name.

## [0.3.0] - 2026-11-14

### Added
- **Profit** tab ("profit so far"): what you actually made from crafts and flips sold to vendors, for this session,
  today and all time, with gold per hour, unsold stock and a per-item breakdown. Tracks AH purchases at the price
  paid, NPC vendor purchases, crafts and vendor sales. A short profit line is printed after each vendor visit.
  `/shuffle profit`, `/shuffle profit reset`.
- **Full scan** button on the Vendor flips tab and `/shuffle fullscan`, so flips no longer depend on Auctionator's
  scan mode.
- `/shuffle debug` prints diagnostic info for troubleshooting.
- Progress bar for full scans on the Vendor flips tab: time spent waiting for the AH, listings read out of the
  total, and the countdown while item details load.

### Fixed
- Vendor flips never appeared: Auctionator's Scan button runs an incremental scan by default, which has no
  individual listings, and CraftShuffler silently found nothing. The tab now says when the last scan was incremental.
- Listings whose item data the game hadn't loaded yet were skipped. Their data is now requested and the listings are
  read again, up to 3 times.
- Closing the AH cancels a pending full scan.
- A timeout left over from an earlier full scan could cancel a newer one.
- Release workflow: manual runs for older tags no longer mark that release as "Latest". Uses `actions/checkout@v5`.

## [0.2.0] - 2026-11-13

### Added
- **Vendor flips** tab: AH listings priced below what a vendor pays, found in Auctionator's full scan data. Shows
  listings, quantity, the max price to pay each, total cost and profit, sorted by profit.
- `CraftShuffler Flips` Auctionator shopping list, `/shuffle flips` and `/shuffle flipmin <gold>`.

### Changed
- Release workflow can also be run by hand for an existing tag. `release.sh --push` pushes the branch and the tag
  separately.
- The results window now has **Crafts** and **Vendor flips** tabs. Shopping list and Refresh act on the current tab.

## [0.1.0] - 2026-11-13

First version.

### Added
- Records learned recipes and their required reagents when a profession window is opened, per character.
- Flags craftable, non-soulbound items as **Shuffle me!** when Auctionator reagent cost is below vendor value.
- Reagents you can craft yourself are priced at the cheaper of buying or crafting, recursively, with a cycle guard.
- Step-by-step plan in the row tooltip: what to buy, what to craft in which order, and leftovers.
- Auction value column and AH profit after the 5% cut.
- Sell via column: AH or vendor, with the sell chance needed for listing to beat vendoring. Deposits are recorded
  at the AH, or estimated until then.
- Max price per reagent and an Auctionator `CraftShuffler` shopping list for buying in volume.
- Item tooltip line for flagged items, `/shuffle` slash commands, gold coin addon icon.
- Results window title shows the addon version.
- Offline test suite with a mocked WoW API (`lua tests/run.lua`).
- Release tooling: `scripts/release.sh` and a GitHub Action that publishes a zip for every version tag.
