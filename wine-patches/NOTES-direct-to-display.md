# Design: direct-to-display presentation in winemac.drv

Status: design only. Nothing in this folder implements it.

## Today
Every frame a game renders ends up in a `CAMetalLayer` owned by a `WineContentView`
(`dlls/winemac.drv/cocoa_window.m`, created through `macdrv_create_view_swapchain`). The window server
composites that layer with the rest of the screen, also in fullscreen. Cost: one extra copy per frame and
one compositor frame of latency (about 8 ms at 120 Hz, 16 ms at 60 Hz).

## What macOS offers
Since macOS 10.15 Core Animation can hand a `CAMetalLayer` straight to the display controller when:
- the layer is opaque and covers the whole screen at native resolution,
- nothing is composited above it (no other windows, no menu bar, no cursor layer in the way),
- the window is at a normal level and not transformed, and
- the layer uses a display-compatible pixel format and `displaySyncEnabled` is on.
Nothing is requested explicitly; the system switches when the conditions hold. The Metal Performance HUD
(`MTL_HUD_ENABLED=1`) shows it as `Direct` vs `Composited` next to the presentation mode.

## Changes needed in winemac.drv
1. `cocoa_window.m`, fullscreen path (`setMacDrvState` where `captureDisplays`/`NSWindowStyleMaskBorderless`
   are handled): when a window is fullscreen on one display, make the window itself opaque
   (`setOpaque:YES`, black `backgroundColor`), drop the content view's layer shadow and hide the
   `WineBaseView` chrome so the Metal layer is the top-most layer.
2. `macdrv_create_view_swapchain`: set `layer.opaque = YES`, `layer.presentsWithTransaction = NO`,
   `layer.maximumDrawableCount = 2` in fullscreen (3 windowed), `layer.displaySyncEnabled = allow_vsync`,
   and keep `drawableSize` equal to the display's pixel size (no scaling layer in between). Also expose
   `wantsExtendedDynamicRangeContent` when the swapchain format is HDR.
3. Cursor: the Wine cursor is a separate layer in the content view. In direct mode the hardware cursor
   must be used (`macdrv_set_cursor` already does when `use_system_cursors` is on); force it in fullscreen.
4. Fallback: nothing to do. If a condition breaks (notification banner, Dock showing) the system goes back
   to compositing on its own.

## Measuring
Before/after with the HUD's present mode and frame time, and the app's HUD OCR benchmark (`--hudocr`):
expect the same fps and one frame less input latency; the win is latency, not throughput.

## Why not now
The engine in use is Wine 10.0 and the change sits on the 11.x window code; it needs a 11.x build that
works on macOS 27 first (see NOTES-child-surface-macos27.md).
