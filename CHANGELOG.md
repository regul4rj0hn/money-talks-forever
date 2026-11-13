# Changelog

All notable changes to CraftShuffler. Versions follow [Semantic Versioning](https://semver.org/):
MAJOR for breaking changes (e.g. saved data that no longer loads), MINOR for new features, PATCH for fixes.
Each version is a [GitHub release](https://github.com/regul4rj0hn/craft-shuffler/releases) with a ready-to-install zip.

## [Unreleased]

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
