#!/usr/bin/env bash
# Fails if the addon reads or writes a global that isn't on the allowlist below.
# Catches a classic Lua bug: calling a `local function` defined further down the file,
# which silently becomes a (nil) global lookup and errors in game.
#
# Usage: scripts/check-globals.sh [luac]   (default: luac on PATH; CI passes luac5.1)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
LUAC=${1:-luac}
ADDON_DIR=${ADDON_DIR:-MoneyTalksForever}

# WoW API, FrameXML and Lua standard library names the addon is expected to use.
ALLOWED="
Auctionator AUCTION_EXPIRED_MAIL_SUBJECT CraftShufflerDB DisableAddOn AUCTION_REMOVED_MAIL_SUBJECT BreakUpLargeNumbers
C_AddOns C_AuctionHouse C_Container C_CurrencyInfo C_Item C_Timer C_TradeSkillUI ChatEdit_InsertLink
MoneyTalksForeverDB CreateDataProvider CreateFrame CreateScrollBoxListLinearView Enum GameTooltip GameTooltip_Hide
GetAddOnMetadata GetInboxHeaderInfo GetInboxInvoiceInfo GetInboxItem GetInboxNumItems GetMoney GetMoneyString
GetRealmName GetTime IsModifiedClick ItemLocation NO NUM_BAG_SLOTS NUM_TOTAL_EQUIPPED_BAG_SLOTS
ScrollBoxConstants ScrollUtil SlashCmdList StaticPopupDialogs StaticPopup_Show TooltipDataProcessor UIParent
UISpecialFrames UnitName YES SLASH_MONEYTALKSFOREVER1 SLASH_MONEYTALKSFOREVER2
assert date hooksecurefunc ipairs math next pairs pcall print select string table time tinsert tonumber tostring type unpack
"

used=$(
  find "$ADDON_DIR" -name '*.lua' | sort | while read -r f; do
    "$LUAC" -o /dev/null -l "$f"
  done |
    # Lua 5.1: GETGLOBAL/SETGLOBAL ... ; name    Lua 5.2+: GETTABUP/SETTABUP ... _ENV "name"
    sed -nE 's/.*(GETGLOBAL|SETGLOBAL).*; ([A-Za-z_][A-Za-z0-9_]*)$/\2/p; s/.*(GETTABUP|SETTABUP).*_ENV "([A-Za-z_][A-Za-z0-9_]*)".*/\2/p' |
    sort -u
)

if [[ -z "$used" ]]; then
  echo "check-globals: could not read any globals from '$LUAC -l' output (unknown format?)" >&2
  exit 1
fi

bad=0
for name in $used; do
  if ! grep -qw -- "$name" <<<"$ALLOWED"; then
    echo "unexpected global: $name" >&2
    bad=1
  fi
done
[[ $bad -eq 0 ]] && echo "globals ok ($(wc -w <<<"$used") names)"
exit $bad
