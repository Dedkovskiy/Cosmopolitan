# Cosmopolitan

Runs Windows games and programs on Apple Silicon Macs through Wine, with the graphics
layers (DXMT, DXVK, D3DMetal), controllers, runtimes and community fixes handled
automatically. Free, open, unnotarized.

## First launch

The app is not notarized (no paid Apple Developer account), so macOS blocks the first
open. Right-click `Cosmopolitan.app` → **Open** → **Open** in the dialog. Once is enough.

## D3DMetal (Direct3D 12) is optional and comes from Apple

Direct3D 10/11 games run through DXMT out of the box. Direct3D 12 needs Apple's
D3DMetal, which is proprietary and **not included**. Download the Game Porting Toolkit
from https://developer.apple.com/games/game-porting-toolkit/, then in Cosmopolitan:
Drivers › **D3DMetal…** › *Install from Apple's download…*, read Apple's license, and
accept it. You can remove it again from the same place. See `THIRD_PARTY_NOTICES.md`.

## Anti-cheat

Nothing here bypasses or disables anti-cheat, ever. Games are badged honestly:
"Online won't work (Easy Anti-Cheat)" or "Kernel anti-cheat — will not run". For the
latter, the app points to cloud gaming.

## Not built (and why)

GOG and Epic imports (GOG Galaxy installs fine inside a bottle; Epic needs the Legendary backend and an account), SteamGridDB art (needs an API key; Steam's own CDN art is used instead), DualSense haptics (SDL gives XInput, no haptics path under Wine), cloud-save sync (Steam Cloud already works inside Steam), backend benchmarking and fps history (no frame-rate source outside the Metal HUD), Discord Rich Presence bridge, replay clips, mod manager, shared multi-user libraries. (The US-keyboard-layout fix is done outside Wine: the app selects the macOS US layout while a game runs and restores yours afterwards.)

## Layout

- `Sources/Core/` — paths, environment, licensing gate, drivers, PE parsing, shell helpers
- `Sources/Model/` — the `Model` class (state, bottles, processes, launching)
- `Sources/Features/` — one file per feature, each an `extension Model` (launch check, anti-cheat, community data, D3DMetal, troubleshoot, triage, updates, snapshots, AVX, imports, …)
- `Sources/UI/` — `ContentView` and one file per sheet under `UI/Sheets/`
- `Sources/App/` — entry point, Sparkle updater, command-line modes
- `scripts/build.sh` (app + dSYM), `scripts/release.sh` (zip, symbols, signed appcast, GitHub release), `scripts/dist.sh` (offline bundle without D3DMetal)

## Credits

Wine and the Sikarugir Wine builds, DXMT (3Shain), DXVK/D9VK (doitsujin, Gcenx),
MoltenVK (Khronos), GStreamer, cnc-ddraw, SDL, winetricks, DOSBox Staging, the Highball
database (CC0), ProtonDB and umu-protonfixes. Full list with licenses in
`THIRD_PARTY_NOTICES.md`.
