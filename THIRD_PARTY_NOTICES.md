# Third-party notices

Pitchside bundles the components below, unchanged unless stated. Each keeps its own licence;
licence texts are in [`licenses/`](licenses/).

## Apple Silicon BepInEx compatibility layer

`macos-compat/` is copied from [DadMych/fm26-player-export-macos](https://github.com/DadMych/fm26-player-export-macos)
at commit `463074f` (MIT, © TFP FM contributors; [`licenses/MIT-macos-compat.txt`](licenses/MIT-macos-compat.txt)).
Its original notice is kept at [`macos-compat/NOTICE.md`](macos-compat/NOTICE.md). That notice also describes
plugins from the upstream project (FM26 Player Export, FM26 Display Fix) that Pitchside does **not** ship.

Pitchside's changes to it:
- `run_bepinex_arm64.sh`: one shadow folder per game under `~/pitchside_bep/`; arm64-only copy of
  `UnityPlayer.dylib` in the shadow bundle; two-phase interop generation for FM27's universal
  `GameAssembly.dylib`; log at `/tmp/pitchside_launch.log`.
- `libdoorstop.dylib`: rebuilt (see UnityDoorstop below).

## BepInEx 6 (IL2CPP) and bundled libraries

`macos-compat/dist/bepinex-core/` contains the [BepInEx](https://github.com/BepInEx/BepInEx) 6 IL2CPP core
(LGPL-2.1) and the libraries it ships with, each under its own licence. The copyleft ones are
Il2CppInterop (LGPL-3.0) and funchook (GPL-2.0 or later, with a linking exception). The rest, including
HarmonyX, MonoMod, Mono.Cecil, Cpp2IL, Iced, AsmResolver, Disarm, Capstone and Dobby, use permissive
licences (MIT, BSD or Apache-2.0); see each project for details.

As distributed by the upstream compatibility layer, these files are modified:
- `BepInEx.Core.dll`, `BepInEx.Unity.IL2CPP.dll`: a main-thread tick for plugins on macOS arm64
  (described in [`macos-compat/BEPINEX-PATCH.md`](macos-compat/BEPINEX-PATCH.md)).
- `Il2CppInterop.*.dll`: built from Il2CppInterop 1.5.1 (commit `6d9007c` + PR #272) with arm64
  support. The source patch is
  [`docs/il2cppinterop-arm64.patch`](https://github.com/DadMych/fm26-player-export-macos/tree/main/docs)
  in the upstream repository.

Source for every LGPL component is available from the projects linked above. You may replace any of
these libraries with your own build.

## UnityDoorstop

`macos-compat/libdoorstop.dylib` is [UnityDoorstop](https://github.com/NeighTools/UnityDoorstop) 4.6.0
(LGPL-3.0), built by Pitchside from **unmodified** upstream source, commit `1c3ece1`, for arm64 with:

```
zig cc -target aarch64-macos -shared -Os -DVERBOSE -DPLTHOOK_DEBUG_CMD -DPLTHOOK_DEBUG_FIXUPS
```

## Dobby

`macos-compat/libdobby.arm64.dylib` is from [Dobby](https://github.com/jmpews/Dobby) (Apache-2.0).

## Microsoft .NET

`macos-compat/dist/dotnet-extras/` holds unmodified Microsoft .NET helper libraries (MIT). The installer
downloads the official .NET 6 runtime for arm64 directly from Microsoft.

## Football Manager

Football Manager is a trademark of Sports Interactive Limited and SEGA. Pitchside is not affiliated with
or endorsed by them. No game files or game data are included. The interop assemblies BepInEx generates
from your own installation stay on your Mac and must not be redistributed.
