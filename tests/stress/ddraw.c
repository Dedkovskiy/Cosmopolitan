// DirectDraw 7: windowed primary + offscreen surface, colour-fill Blt every frame and blit to the window (old 2D games' path, cnc-ddraw).
#define COBJMACROS
#include "common.h"
#include <ddraw.h>

int main(void) {
    HWND w = make_window("Stress DDraw");
    IDirectDraw7 *dd; HRESULT hr;
    if (FAILED(hr = DirectDrawCreateEx(0, (void **)&dd, &IID_IDirectDraw7, 0))) { result("ddraw", 0, 0, 0, "DirectDrawCreateEx failed"); return 1; }
    IDirectDraw7_SetCooperativeLevel(dd, w, DDSCL_NORMAL);
    DDSURFACEDESC2 sd = { sizeof sd }; sd.dwFlags = DDSD_CAPS; sd.ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE;
    IDirectDrawSurface7 *prim, *back; IDirectDrawClipper *clip;
    if (FAILED(hr = IDirectDraw7_CreateSurface(dd, &sd, &prim, 0))) { char e[64]; sprintf(e, "primary hr=0x%08lx", hr); result("ddraw", 0, 0, 0, e); return 1; }
    IDirectDraw7_CreateClipper(dd, 0, &clip, 0); IDirectDrawClipper_SetHWnd(clip, 0, w); IDirectDrawSurface7_SetClipper(prim, clip);
    DDSURFACEDESC2 od = { sizeof od }; od.dwFlags = DDSD_CAPS | DDSD_WIDTH | DDSD_HEIGHT; od.ddsCaps.dwCaps = DDSCAPS_OFFSCREENPLAIN; od.dwWidth = 640; od.dwHeight = 480;
    if (FAILED(hr = IDirectDraw7_CreateSurface(dd, &od, &back, 0))) { char e[64]; sprintf(e, "offscreen hr=0x%08lx", hr); result("ddraw", 0, 0, 0, e); return 1; }
    int frames = 0, bad = 0; RECT badr = {0}; double t0 = now(), t;
    while ((t = now() - t0) < SECONDS && pump()) {
        DDBLTFX fx = { sizeof fx };
        for (int i = 0; i < 64; i++) {   // 64 coloured rectangles per frame
            RECT r = { (i * 37 + frames * 3) % 600, (i * 53 + frames) % 440, 0, 0 }; r.right = r.left + 40; r.bottom = r.top + 40;
            fx.dwFillColor = (i * 2654435761u + frames) & 0xffffff;
            IDirectDrawSurface7_Blt(back, &r, 0, 0, DDBLT_COLORFILL | DDBLT_WAIT, &fx);
        }
        RECT dst; GetClientRect(w, &dst); MapWindowPoints(w, 0, (POINT *)&dst, 2);
        if (FAILED(hr = IDirectDrawSurface7_Blt(prim, &dst, back, 0, DDBLT_WAIT, 0))) { if (!bad++) badr = dst; continue; }   // like a game: drop the frame
        frames++;
    }
    DDSURFACEDESC2 pd = { sizeof pd }; IDirectDrawSurface7_GetSurfaceDesc(prim, &pd);
    DEVMODEA dm = { .dmSize = sizeof dm }; EnumDisplaySettingsA(0, ENUM_CURRENT_SETTINGS, &dm);
    char det[240] = ""; if (bad) sprintf(det, "failed blits=%d first rect=(%ld,%ld)-(%ld,%ld) primary=%lux%lu screen=%dx%d currentmode=%lux%lu", bad, badr.left, badr.top, badr.right,
        badr.bottom, pd.dwWidth, pd.dwHeight, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN), dm.dmPelsWidth, dm.dmPelsHeight);
    result("ddraw", frames > 0, frames, t, det);
    return 0;
}
