#!/bin/zsh
# Builds the driver stress tests into <bottle>/drive_c/StressTest (default bottle: Steam). The .NET one is compiled inside the bottle by its own csc.
set -e
cd "${0:A:h}"
B="$HOME/Library/Application Support/Cosmopolitan/bottles/${1:-Steam}"; O="$B/drive_c/StressTest"; mkdir -p "$O"; rm -f "$O/results.txt"
for a in x86_64 i686; do
  s=$([[ $a == x86_64 ]] && echo 64 || echo 32); cc=$a-w64-mingw32-gcc; f=(-O2 -s -mwindows)
  $cc $f d3d9.c  -o "$O/stress-d3d9-$s.exe"  -ld3d9
  $cc $f d3d11.c -o "$O/stress-d3d11-$s.exe" -ld3d11 -ldxgi -luuid
  $cc $f -DD3D10 d3d11.c -o "$O/stress-d3d10-$s.exe" -ld3d10 -ldxgi -luuid
  $cc $f ddraw.c -o "$O/stress-ddraw-$s.exe" -lddraw -ldxguid -luuid
done
x86_64-w64-mingw32-gcc -O2 -s -mwindows d3d12.c -o "$O/stress-d3d12-64.exe" -ld3d12 -ldxgi -luuid   # D3D12 is 64-bit only on macOS
# .NET: compiled inside the bottle by Wine Mono's mcs (no .NET SDK on the Mac). WINEMSYNC=1 matches the msync wineserver Steam may be running.
E="$HOME/Library/Application Support/Cosmopolitan/engines/$(defaults read local.cosmopolitan engine 2>/dev/null || echo WS12WineSikarugir10.0_8)/wswine.bundle"
cp dotnet.cs "$E"/share/wine/mono/wine-mono-*/lib/mono/4.5/mcs.exe "$O/"
(cd "$O" && WINEPREFIX="$B" WINEDEBUG=-all WINEMSYNC=1 "$E/bin/wine" mcs.exe -nologo -target:winexe -out:stress-dotnet.exe -r:System.Windows.Forms.dll -r:System.Drawing.dll dotnet.cs)
rm -f "$O/mcs.exe" "$O/dotnet.cs"
ls "$O"
