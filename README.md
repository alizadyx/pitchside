# Pitchside

<img src="docs/icon.png" width="96" align="right" alt="Pitchside icon">

**A free, open-source scouting tool for Football Manager on Apple Silicon Macs.** It's in the spirit of
Genie Scout on Windows. Search every player and staff member in your save, see their real attributes,
hidden attributes and potential, and plan your squad.

![Players screen](docs/screenshots/players.png)

> Pitchside is a fan project. It isn't affiliated with or endorsed by Sports Interactive or SEGA.
> Football Manager is their trademark. Use it in single-player saves only, at your own risk.

## What it does

- **Player search:** filter by name, club, nationality, division, age, current and potential ability,
  positions (picked on a pitch), value, wage, contract expiry and transfer status. You can also set any
  attribute minimum, including hidden and personality ones ("Pace ≥ 15", "Consistency ≥ 14").
- **FM27 role ratings:** every In Possession and Out of Possession role in FM27 (79 in all), using the
  key and preferable attributes the game itself highlights on the player screen. The scores rank roles
  in the same order as FM's role stars (70 of 73 test comparisons, the rest near-ties). There is also a
  meta score weighted towards the attributes that matter most in FM's match engine.
- **Tactics & squad:** build your own tactic (25 shapes or a blank pitch, any position, any IP and OOP
  role, your mentality, style and team instructions), saved under a name. See your best XI in it,
  everyone at the club who could play each position, when a player would suit another role better,
  and the signings that would improve each position, or the biggest upgrades across the whole team.
  **Suggested** ranks every shape for your squad with the best roles; **Set pieces** picks corner,
  free-kick and penalty takers, aerial targets, who stays back and captains; **Instructions** suggests a
  mentality, style and team instructions with the attributes behind each, against your squad and your
  league. **My squad** and **Timeline** split by first team, U21 and U18, and show what the whole club's
  best XI would be, naming youngsters who'd start. **Depth** lays your formation out as a depth chart:
  every position lists the players in your squad who can play there, best first.
- **Compare teams:** pick a country, then a league, and see it as a sortable table (XI level, depth, CA/PA, each line, technique,
  pace, work rate, aerial threat, set pieces, age, wages) with a radar against the league average and
  the top club; any two clubs head to head; or one club against the average of up to five. Judge clubs
  on their first-team XI, the best XI at the whole club, or their top 18. Cells are coloured by rank in
  the league, can show the difference from the league average, and explain themselves on hover.
  XI level also comes as a 0–100 Rating ((level − 6) × 10) so gaps between clubs are easier to read.
- **Your own columns:** add any stat, attribute, hidden attribute or personality trait as a column to the
  player, squad, signings and growth tables, sort by it, and drag column headers to reorder them.
- **Right-click to copy** a player's name, ready to paste into FM's search.
- **Search suggestions** for clubs, nationalities and divisions as you type.
- **Red and green flags** on every profile ("Injury prone", "Model professional", "Big-match player"),
  and a **development outlook** for young players: the ability they're likely to reach, not just their potential.
- **Player profiles:** all attributes with FM-style colours, hidden attributes, personality, positions
  on a pitch, best roles and star ratings.
- **Squad planning:** where your squad is thin, old or out of contract, signings within your budget, and
  the XI over the next three seasons as contracts end and players age.
- **Staff recommendations:** your weakest coaching, scouting and medical areas, with affordable upgrades
  from people whose job fits the area and who'd plausibly join (board members and unpaid roles left out).
- **Player interest estimate:** how keen each player is likely to be to join your club, graded
  Interested, Persuadable, Doubtful or Unlikely.
- **Growth & regens:** compare scans over time to find the biggest risers and newly generated players.
- **Compare:** up to three players on a radar chart, attribute by attribute.
- **Staff search, shortlist** (with CSV copy), **saved searches**, and a **men's/women's/both** switch.

## Requirements

- A Mac with **Apple Silicon** (M1 or newer), **macOS 14.4 Sonoma** or later
- **Football Manager 27** on **Steam**. FM26 works too, but FM27 is what's tested.
- Apple's free **Command Line Tools**, to build the app. If you don't have them, run `xcode-select --install` once.

## Is it safe? What does it change?

- **The game's own files are never changed.** Pitchside adds a mod loader ([BepInEx](https://github.com/BepInEx/BepInEx))
  next to the game and starts FM through a small launcher script. Clearing one Steam setting turns it all off.
- **It only reads.** The plugin reads FM's database from memory and saves it to a file the app opens.
  It never writes anything to the game or your save.
- **It runs a modified copy of the game's launcher binary.** Apple Silicon needs extra permissions
  (JIT) for the mod loader. Pitchside makes a re-signed copy in `~/pitchside_bep/` rather than touching
  the Steam files.
- **Downloads:** the installer fetches Microsoft's official .NET 6 runtime for arm64. Nothing else is
  downloaded, and nothing is sent anywhere.
- **Everything is open source.** The scripts are plain shell, so please read them before you run them.

## Install

1. **Download** this repository (green **Code** button → **Download ZIP**) and unzip it, for example into Downloads.
2. **Quit Football Manager**, then open Terminal and run:
   ```bash
   cd ~/Downloads/pitchside-main
   bash install.sh
   ```
   If your game isn't in the default Steam folder, give its folder at the end:
   `bash install.sh "/path/to/Football Manager 27"`. To find it, right-click the game in Steam →
   **Manage → Browse local files**.
3. **Set the Steam launch option.** At the end, the installer prints a line like the one below and copies
   it to your clipboard. In Steam, right-click the game → **Properties → General → Launch Options** and
   paste it:
   ```
   "/Users/YOUR-NAME/Library/Application Support/Steam/steamapps/common/Football Manager 27/run_bepinex_arm64.sh" %command%
   ```
   Use the line the installer printed. It already has your real username in it. Typing `/Users/you/…`
   by hand gives Steam's *OS Error 260*.
4. **Build the app:**
   ```bash
   cd app && bash make-app.sh && open Pitchside.app
   ```
   Drag `Pitchside.app` into Applications if you like.

**First start:** launch FM from Steam as usual. The first start takes a few minutes, and the game may
close once on its own while BepInEx prepares itself. Just start it again. To check it worked, open
`BepInEx/LogOutput.log` in the game folder. It should contain `Pitchside 0.4.1 loaded`.

## Use

Load your save → open Pitchside → press **Scan** (⌘R). A scan takes a few seconds. Scan again whenever
you want fresh data, for example after a transfer window or youth intake. Each scan is kept, which is
what powers the Growth & regens screen.

To plan your squad and tactics, open **Tactics & squad** and type your club's name. The interest estimate in the
player profile and the Players list also uses this club.

## Updating

Download the new version, run `bash install.sh` again (with the game closed), and rebuild the app with
`cd app && bash make-app.sh`. Your shortlist, saved searches, tactics and scan history are kept.

## After a Football Manager patch

Patches can move data around in memory. If a scan finds very few players, or values look wrong:

1. Check for a newer Pitchside release first, since it may already include the fix.
2. Otherwise use **Calibration** in the app. Enter two outfield players and one staff member from your
   own club (where you can see exact attributes), press **Run calibration**, and if the report says
   *player attributes found*, press **Apply suggested offsets** and scan again.
3. If it still doesn't work, open an issue and attach the calibration report and `diagnostics.txt`.
   **Open data folder** in the app shows you where they are.

## Uninstall

1. In Steam, clear the game's **Launch Options**. FM is back to normal from this point on.
2. To remove everything, delete these from the game folder: `BepInEx/`, `dotnet_arm64`,
   `libdoorstop.dylib`, `run_bepinex_arm64.sh`. Then delete `~/pitchside_bep/`,
   `~/Library/Application Support/Pitchside/` and `Pitchside.app`.

## Troubleshooting

| Problem | What to do |
|---|---|
| Steam says *OS Error 260* | The launch option path is wrong. Re-run `install.sh` and paste the exact line it prints. |
| App says the plugin hasn't picked up the request | FM wasn't started through the launch option, or BepInEx didn't load. Check `BepInEx/LogOutput.log` in the game folder and `/tmp/pitchside_launch.log`. |
| Game quits before the main menu | Normal once on the very first start. If it keeps happening, clear the launch option to play normally and open an issue with the two logs above. |
| Scan finds very few players, or values are wrong | See *After a Football Manager patch*. |
| Ages are a year off | Check the in-game date in the status bar; if it's wrong, set the season in Settings (⌘,). |
| *"Pitchside.app can't be opened"* | Right-click it → **Open** → **Open**. Apps you build yourself aren't notarised by Apple. |

## Known limitations

- **Player interest is an estimate.** FM works out a player's interest when you search and doesn't store
  it, so Pitchside approximates it from club and league size, the player's reputation, ambition, loyalty,
  age, contract and transfer status. Treat it as a guide.
- The in-game date is worked out from the most recent contract signing in the database, so it can be
  a day or two behind. It's shown in the status bar; the season can be set by hand in Settings.
- Players are placed by the squad lists FM keeps on each team (plugin 0.7.0 or newer): first team,
  U21, U18, and loanees at the club they're playing for, marked "on loan from". Players missing from
  every list keep the team their contract names; with scans older than 0.4.1 the first team is
  estimated as the best 30 and youth teams go by age.
- A club's league is the league of its highest-reputation team.
- **Tactics advice comes from attributes only.** It doesn't know your opponents, your players' morale or
  how they've been playing, so treat it as a starting point and adjust in-game.
- Out of Possession roles are scored on their key attributes only (FM's role cards list up to eight and
  don't show preferable ones).
- Only the Steam version on Apple Silicon is supported. Intel Macs, Game Pass and Epic aren't.

## How it works

FM's database lives in its native C++ engine. Each player and staff member is a C++ object whose class
can be recognised from its run-time type information. A small BepInEx plugin walks the game's memory
from inside the process using `mach_vm_read_overwrite`, which can't crash the game on freed memory. It
finds those objects and reads each field at the positions listed in `offsets.json`, then writes
`export.json`. The SwiftUI app reads that file. Calibration finds the field positions again after a
patch, using values you can see in the game.

| Folder | What's in it |
|---|---|
| `app/` | The Mac app (SwiftUI). `PitchsideCore` holds the logic and its tests. |
| `plugin/` | The BepInEx plugin (C#) and the FM27 memory map. `dist/Pitchside.dll` is prebuilt. |
| `macos-compat/` | The Apple Silicon BepInEx setup: launcher, injector and core files. |
| `licenses/` | Licence texts for the third-party parts. |

To build the plugin yourself: `dotnet build plugin/Pitchside.csproj -c Release` (.NET 6 SDK or newer).

## Credits

- **Apple Silicon BepInEx layer:** [DadMych / TFP FM contributors](https://github.com/DadMych/fm26-player-export-macos)
  (MIT). Without their work none of this would run on Apple Silicon.
- **BepInEx**, **Il2CppInterop**, **UnityDoorstop**, **Dobby** and the other libraries listed in
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- The FM26 Windows field map published by [FMSuperScout](https://github.com/mavarobli/FMSuperScout)
  (and the Cheat Engine tables it credits) was the starting point for the memory layout. No code was copied.
- Built with a lot of help from Claude (Anthropic's AI assistant).

## Licence

Pitchside's own code is under the [MIT licence](LICENSE). Bundled third-party components keep their own
licences. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
