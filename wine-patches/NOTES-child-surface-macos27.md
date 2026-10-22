# Wine 11.x on macOS 27: black Steam window (client surface detached)

Status: analysis only. Not reproducible on demand here because the only working engine is Wine 10.0.

Attempt on 2026-10-22 with the Sikarugir 11.0_1 engine (APFS clone of the Steam bottle): the engine ships
two loaders, `bin/wine` (wrapper, 4 GB `__PAGEZERO`, no `WINE_RESERVE`) and `lib/wine/x86_64-unix/wine`
(upstream layout, reserve segment present). Through the second one, with `WINELOADER` pointing at it too,
the first process initialises fully, but every child (`wineboot.exe` from `start.exe /exec`) exits with
code 1 and no message right after mapping its exe, ntdll.dll and apisetschema.dll, with or without
msync/esync. So the engine needs Sikarugir's own launch environment, and a log for this bug needs a plain
x86_64 Wine 11 build (`arch -x86_64` configure with the brew LLVM PE toolchain, roughly an hour of build).

## What was observed
Steam under Wine 11.x on macOS 27 (Apple M2 Max) opens, logs
`surface … has been detached already, ignoring` from win32u, and renders black. Wine 10.0 with the same
drivers (DXMT, D9VK) renders normally.

## Where the message comes from (Wine 11.20, commit 840a939)
- `dlls/win32u/window.c:483` `use_window_client_surface()` warns and does nothing when `surface->hwnd`
  is already NULL.
- `surface->hwnd` is cleared by `client_surface_detach_locked()` (`window.c:298`), called from
  `detach_client_surfaces(hwnd)` in two places: `destroy_window()` (`window.c:5533`) and the cleanup of
  windows owned by an exiting thread (`window.c:5697`).
- The Mac driver's detach (`dlls/winemac.drv/window.c:1075` `macdrv_client_surface_detach`) *disposes the
  Cocoa view* that carries the CAMetalLayer and clears `data->client_view`. Nothing re-creates it: a client
  surface, once detached, can never present again, by design.
- Vulkan presentation (`dlls/win32u/vulkan.c:1562/1595`) marks the surface used/unused around
  `vkQueuePresentKHR`, so every present on a detached surface hits the warning.

## Why Steam is affected
Steam's main window is a CEF browser hosted in a *child* HWND that Steam destroys and re-creates (startup
splash → main window, and on every DPI/display change). D3D11 presentation goes DXMT → MoltenVK-less Metal
path → winemac client surface. When the child HWND is destroyed, win32u detaches the surface; DXMT keeps
presenting the same swapchain (D3D11 has no "surface lost" result), so every frame is dropped and the
window stays black. Wine 10.0 did not have per-HWND client surfaces (the Metal view belonged to the
toplevel's `macdrv_win_data` and survived child recreation), which is why 10.0 works.

## Fix directions (pick one, both need a 11.x build to verify)
1. **winemac.drv**: in `macdrv_client_surface_detach`, hide and unparent the view instead of disposing it,
   and let `macdrv_client_surface_update` re-parent it when the surface is used with a new toplevel. The
   swapchain (and the CAMetalLayer the game renders into) then survives the HWND swap. Risk: views leaking
   until `destroy`; bounded by the surface refcount.
2. **win32u**: do not detach surfaces of a destroyed *child* window while its toplevel lives; re-anchor them
   to the toplevel (`surface->hwnd = toplevel`) and let the driver's `update` move the view. Smaller
   driver-independent change, but it changes semantics for winex11/winewayland too.
3. **DXMT**: recreate the swapchain when `vkQueuePresentKHR`/the Metal present returns an error for N frames.
   Only helps DXMT; D3DMetal and D9VK keep the problem.

## What to collect before filing
`WINEDEBUG=+win,+vulkan,+macdrv,+timestamp wine steam.exe 2> steam.log` on 11.x, then look for the first
`macdrv_client_surface_detach` and whether a `destroy_window` of a child precedes it while the toplevel is
alive. File at https://bugs.winehq.org, component `-unknown`/winemac.drv, attach the log and this analysis.
