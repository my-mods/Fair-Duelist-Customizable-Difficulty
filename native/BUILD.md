# Building the attack-ticket helper

Use Windows x64, Visual Studio 2022 MSVC v143, Windows SDK 10.0.26100.0 and CMake 3.25 or newer. Build Release with the shared C runtime.

The SDK uses RE-UE4SS `97b7e501c19d8b2b7c662feee73aaa0dc1f0a4d1` and its UEPseudo submodule `eb40a05f49509bdeb1ac39287032b60af585cca8`. The engine headers require an Epic-linked GitHub account; they are not redistributed here.

```bat
git clone https://github.com/UE4SS-RE/RE-UE4SS.git RE-UE4SS
git -C RE-UE4SS checkout 97b7e501c19d8b2b7c662feee73aaa0dc1f0a4d1
git -C RE-UE4SS submodule update --init deps/first/Unreal
cmake -S native -B build-native -A x64 -DUE4SS_SDK=C:/path/to/RE-UE4SS
cmake --build build-native --config Release
```

Run the CMake commands from this repository. Pinned MinHook, static Zydis/Zycore and SDK header dependencies are obtained by CMake. The resulting `main.dll` belongs in `Dawnwalker/Binaries/Win64/ue4ss/Mods/FairDuelist/dlls/` inside the archive. `UE4SS.def` creates an import library for the running UE4SS host; it is not a replacement host DLL. Preserve `LICENSES/MinHook.txt`, `LICENSES/Zydis.txt` and `LICENSES/Zycore.txt`.

## Ticket control

Lua validates the current player, world, AI stub and AI board before binding a board. The native helper checks the reflected fragment offset and the operation-specific allocation, availability and release contracts. It changes only the bound player board: one Standard slot plus the remaining Helper slots. Both native requests and the reflected request thunk refresh capacities; the thunk contains an inlined allocation path. Requests and releases retain their original arguments, results and notifications. Lower limits drain existing holders instead of revoking tickets. Game default restores captured capacities. Deleted boards are invalidated using the object-array deletion listener and object identity.

Readiness retries are finite and event-driven; no idle timer or settings polling is used. Unsupported native contracts disable this feature with a diagnostic while ordinary balance controls remain available. Code locations are hints, not compatibility gates; no game hash, storefront or version is required. Scripted attacks outside the Standard/Helper coordination system are outside this limit. Runtime behavior still needs in-game validation before a public release.
