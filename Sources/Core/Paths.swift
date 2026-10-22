import SwiftUI

// Engine: open-source Wine 10.0 (Sikarugir build) kept in our own folder. No CodeWeavers code.
// ponytail: Wine 11.x Staging renders Steam's UI black on macOS 27 (client surface detached); stay on 10.0 until that's fixed upstream.
let support = NSHomeDirectory() + "/Library/Application Support/Cosmopolitan"
// The engine is a setting (Settings › Engine); 10.0_8 is the tested default. Pinned there because 11.x renders Steam black on macOS 27.
let defaultEngine = "WS12WineSikarugir10.0_8"
var engineName: String { UserDefaults.standard.string(forKey: "engine") ?? defaultEngine }
var engineDir: String { support + "/engines/\(engineName)/wswine.bundle" }
var wineBin: String { engineDir + "/bin/wine" }
let bottlesDir = support + "/bottles"
var engineOK: Bool { FileManager.default.fileExists(atPath: wineBin) }   // re-evaluated: first-run setup installs it while the app runs
// Drivers live in engines/renderer/<name>/wine; the engine loads a folder's DLLs as builtins when WINEDLLPATH_<slot> points at it.
// Per-bottle choice is DRIVERS=dxmt,cnc_ddraw in cosmopolitan.env (absent = dxmt). Drop a new renderer folder in and add its slot here.
let driversDir = support + "/engines/renderer"
let driverSlot = ["dxmt": "DXMT", "dxvk": "DXVK", "dxvk3": "DXVK", "d9vk": "D9VK", "d3dmetal": "D3DMETAL", "cnc_ddraw": "CNCD"]
// Auto = the set whose DLLs don't overlap: dxmt (d3d10core/d3d11/dxgi), d9vk (d3d8/d3d9), cnc_ddraw (ddraw). D3D12 needs d3dmetal, which
// replaces dxmt's d3d11/dxgi too, so it stays a manual choice. ponytail: no per-exe import sniffing; games LoadLibrary D3D at runtime anyway.
let autoDriverSet = ["dxmt", "d9vk", "cnc_ddraw"]
// A bottle holding a Direct3D 12 program gets d3dmetal in place of dxmt (both provide d3d11/dxgi; D3DMetal does 11 and 12), so that
// games started from inside Steam get DirectX 12 too. verifyAll() keeps the marker file current and restarts Steam when it flips.
let autoDriverSetDX12 = ["d3dmetal", "d9vk", "cnc_ddraw"]
func dx12Marker(_ bottle: String) -> String { "\(bottlesDir)/\(bottle)/.needs-dx12" }
