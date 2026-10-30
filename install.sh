#!/bin/bash
# Pitchside installer: Football Manager 27 (or 26), Steam version, Apple Silicon Mac.
#
#   bash install.sh                                   # default Steam folder for FM27
#   bash install.sh "/path/to/Football Manager 27"    # if your game is somewhere else
#
# What it does. None of the game's own files are changed or replaced:
#   1. Adds the BepInEx mod loader and an Apple Silicon launcher next to the game.
#      Downloads Microsoft's official .NET 6 runtime for arm64 (about 30 MB) the first time.
#   2. Adds the Pitchside plugin, which reads the game's database (read-only).
#   3. Prints the exact Steam launch option to paste.
# Safe to run again to update. To uninstall, see README.md.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="${1:-$HOME/Library/Application Support/Steam/steamapps/common/Football Manager 27}"
GAME="${GAME%/}"
SUPPORT="$HOME/Library/Application Support"
DATA="$SUPPORT/Pitchside"

if [ "$(uname -m)" != "arm64" ]; then
  echo "Pitchside needs an Apple Silicon Mac (M1 or newer). This Mac reports: $(uname -m)" >&2
  exit 1
fi
if [ ! -d "$GAME/fm.app" ]; then
  echo "Can't find the game (fm.app) in:" >&2
  echo "  $GAME" >&2
  echo "" >&2
  echo "Find your game folder in Steam: right-click the game → Manage → Browse local files." >&2
  echo "Then run:  bash install.sh \"/path/to/that/folder\"" >&2
  exit 1
fi
if pgrep -f "Football Manager 2[0-9].*fm.app" >/dev/null 2>&1 || pgrep -x fm >/dev/null 2>&1; then
  echo "Please quit Football Manager first, then run this again." >&2
  exit 1
fi

GAME_NAME="$(basename "$GAME")"

# Earlier versions of this project were called FMScoutMac: move their data across.
[ -d "$HOME/fmscout_bep" ] && [ ! -e "$HOME/pitchside_bep" ] && mv "$HOME/fmscout_bep" "$HOME/pitchside_bep"
[ -d "$SUPPORT/FMScoutMac" ] && [ ! -e "$DATA" ] && mv "$SUPPORT/FMScoutMac" "$DATA"

export FM26_GAME="$GAME"
export FM26_BEP="$HOME/pitchside_bep/$GAME_NAME"
COMPAT="$HERE/macos-compat"

echo "== Pitchside installer =="
echo "Game:          $GAME"
echo "Launcher copy: $FM26_BEP"
echo ""

echo "== 1/5 .NET runtime, injector and launcher =="
bash "$COMPAT/setup_arm64.sh"

echo ""
echo "== 2/5 BepInEx core =="
CORE="$GAME/BepInEx/core"
mkdir -p "$CORE" "$GAME/BepInEx/plugins" "$GAME/BepInEx/config"
if [ ! -d "$CORE/backup-stock" ] && ls "$CORE"/*.dll >/dev/null 2>&1; then
  mkdir -p "$CORE/backup-stock"
  find "$CORE" -maxdepth 1 -type f \( -name "*.dll" -o -name "*.dylib" \) -exec cp {} "$CORE/backup-stock/" \;
  echo "   backed up the BepInEx core you already had to BepInEx/core/backup-stock"
fi
cp "$COMPAT/dist/bepinex-core/"* "$CORE/"
find "$GAME/BepInEx" -name "._*" -delete 2>/dev/null || true
echo "   installed $(ls "$COMPAT/dist/bepinex-core" | wc -l | tr -d ' ') core files"

echo ""
echo "== 3/5 Pitchside plugin =="
rm -rf "$GAME/BepInEx/plugins/FMScoutMac"          # the plugin's earlier name
mkdir -p "$GAME/BepInEx/plugins/Pitchside"
cp "$HERE/plugin/dist/Pitchside.dll" "$GAME/BepInEx/plugins/Pitchside/"
echo "   installed BepInEx/plugins/Pitchside/Pitchside.dll"

echo ""
echo "== 4/5 Memory map for this game version =="
mkdir -p "$DATA"
case "$GAME_NAME" in
  *27*)
    SHIPPED="$HERE/plugin/offsets.fm27-mac.json"
    if [ ! -f "$DATA/offsets.json" ]; then
      cp "$SHIPPED" "$DATA/offsets.json"
      echo "   installed the FM27 memory map"
    elif ! cmp -s "$SHIPPED" "$DATA/offsets.json"; then
      backup="$DATA/offsets.backup-$(date +%Y%m%d-%H%M%S).json"
      cp "$DATA/offsets.json" "$backup"
      cp "$SHIPPED" "$DATA/offsets.json"
      echo "   updated the FM27 memory map (your previous one is saved as $(basename "$backup"))"
    else
      echo "   FM27 memory map already up to date"
    fi
    ;;
  *)
    echo "   using the plugin's built-in FM26 map"
    ;;
esac

echo ""
echo "== 5/5 Clear the download quarantine on the added files =="
for p in "$GAME/BepInEx" "$GAME/libdoorstop.dylib" "$GAME/run_bepinex_arm64.sh" "$GAME/dotnet_arm64" "$FM26_BEP"; do
  [ -e "$p" ] && xattr -dr com.apple.quarantine "$p" 2>/dev/null || true
done
echo "   done"

LINE="\"$GAME/run_bepinex_arm64.sh\" %command%"
printf '%s' "$LINE" | pbcopy 2>/dev/null && COPIED=" (already copied to your clipboard)" || COPIED=""

echo ""
echo "================================================================"
echo " Last step, in Steam:"
echo "   right-click $GAME_NAME → Properties → General → Launch Options"
echo "   and paste this whole line$COPIED:"
echo ""
echo "   $LINE"
echo ""
echo " Then start the game from Steam as usual."
echo " The first start takes a few minutes and the game may close once on its"
echo " own while BepInEx prepares itself. Just start it again."
echo ""
echo " Check it worked: $GAME/BepInEx/LogOutput.log"
echo " should contain 'Pitchside 0.6.0 loaded'."
echo "================================================================"
