# Changelog

All notable changes to CraftShuffler. Versions follow [Semantic Versioning](https://semver.org/):
MAJOR for breaking changes (e.g. saved data that no longer loads), MINOR for new features, PATCH for fixes.
Each version is a [GitHub release](https://github.com/regul4rj0hn/craft-shuffler/releases) with a ready-to-install zip.

## [Unreleased]

### Fixed
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
