# Wine patches from Cosmopolitan

Patches against upstream Wine `main` (11.20, commit 840a939), written from what running Steam and
DirectX 12 games through this launcher on macOS 27 showed. Each one is a `git format-patch` file with its
description inside. The two `NOTES-*.md` files are analysis and design for problems that need a working
Wine 11.x build on macOS 27 before code can be verified.

| File | What it does | Verified how |
|---|---|---|
| `0001-loader-Reserve-the-low-8GB-at-run-time-when-the-prel.patch` | A `wine` loader started without the preloader, or built with neither the preloader nor the `WINE_RESERVE` zero-fill section, now maps the still-free holes below 8 GB `PROT_NONE` and reports them like the preloader does. This is the failure mode of the Sikarugir 11.0_1 loader (children died because ntdll had no reserved low memory). | `clang -fsyntax-only -arch x86_64` with and without `HAVE_WINE_PRELOADER`, and arm64 |
| `0002-winemac.drv-Add-a-KeyboardLayout-option.patch` | New `HKCU\Software\Wine\Mac Driver` / `AppDefaults\<exe>\Mac Driver` string `KeyboardLayout` = input source ID (`com.apple.keylayout.US`). The driver selects it when the process starts (enabling it in the input menu if needed). Games that read scan codes of a US layout stop breaking under Cyrillic, Greek, Hebrew… layouts. Cosmopolitan does the same switch launcher-side today; with this patch it can rely on the registry key instead. Restoring the previous layout on exit is left to the launcher. | syntax-checked; the same TIS calls run in Cosmopolitan's `--uslayout` |
| `0003-winemac.drv-Name-the-application-menu-after-the-Wind.patch` | New string option `ProcessName` (default: the exe name without `.exe`). When Wine runs from the bare loader rather than an `.app` bundle, the application menu says "Hide Steam"/"Quit Steam" instead of "Hide Wine". The Dock label is **not** touched: it comes from the loader file's name, and the private `_LSSetApplicationInformationItem` display-name item was tested on macOS 27 and no longer changes it (returns `noErr`, Dock unchanged). That is why Cosmopolitan runs games through a copy of the loader named after the program. | syntax-checked; Dock behaviour tested with a standalone Cocoa program |
| `NOTES-child-surface-macos27.md` | Why Steam is black under Wine 11.x on macOS 27 (`surface … has been detached already`), with code references and three fix directions. | analysis of 11.20 sources |
| `NOTES-direct-to-display.md` | How to let fullscreen games bypass the compositor (CAMetalLayer direct-to-display) and what to change in winemac.drv. | design |

Not patched because upstream already has it: per-device hidraw selection
(`HKLM\System\CurrentControlSet\Services\WineBus\Devices\<VID>[/<PID>]`, DWORD `Hidraw`), present in
11.20's `dlls/winebus.sys/main.c` (`load_device_options`) and absent from the 10.0 engine (checked the
shipped `winebus.sys` for the strings). Cosmopolitan writes both the global `DisableHidraw` (what 10.0
reads) and the per-device key for Sony pads (what 11.x reads).

Tried and reverted: exporting the driver folders through plain `WINEDLLPATH` (so they would work with any
Wine build, not only the Sikarugir engine's `WINEDLLPATH_<SLOT>` variables). Plain `WINEDLLPATH` makes
DXMT's dxgi/d3d11 the builtin for *every* process, including `steamwebhelper.exe`, which must stay on
Wine's own D3D: Steam then shows "Steamwebhelper is not responding". The slot variables are applied
selectively by the engine; a generic Wine would need per-process `DllOverrides` pointing at the driver
copies instead.

## Trying a patch
```sh
git clone --depth 1 https://gitlab.winehq.org/wine/wine.git && cd wine
git am /path/to/wine-patches/000*.patch
```
A macOS build needs a PE cross-compiler (`brew install mingw-w64 lld llvm`) plus `bison` from Homebrew;
configure with `--enable-archs=i386,x86_64 --disable-tests --without-x`.

## Upstream policy: these patches cannot be submitted as they are
WineHQ's contributor policies (https://gitlab.winehq.org/winehq/winehq/-/wikis/home, "No LLM-generated
code") refuse LLM-generated code, and the user-verification request every new account must file asks you
to confirm you understand that. The three patches here were written by Claude, so they must not be sent
as merge requests. They stay useful as documentation and for building your own engine; a contributor who
reimplements the ideas in their own code (the notes describe what and where) can submit that.

## Submitting upstream (for code you wrote yourself)
1. Make a GitLab account at https://gitlab.winehq.org and fork `wine/wine`.
2. One merge request per patch, branch named after it; the commit message is the review text, keep the
   `module: Imperative summary.` first line.
3. Patches 0002 and 0003 add registry options: mention the key path in the description and update
   `documentation/` if asked. Patch 0001 touches the loader; CC the macOS maintainer in the MR.
4. Attach the `NOTES-child-surface-macos27.md` analysis to a bug at https://bugs.winehq.org together with a
   `WINEDEBUG=+win,+macdrv` log from a 11.x build; it is not a patch yet.
