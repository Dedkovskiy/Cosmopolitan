// Direct3D 9: 20 000 untextured triangles per frame through the fixed-function pipeline (no shaders needed).
#define COBJMACROS
#include "common.h"
#include <d3d9.h>
#include <math.h>

typedef struct { float x, y, z, rhw; DWORD c; } V;
#define TRIS 20000

int main(void) {
    HWND w = make_window("Stress D3D9");
    IDirect3D9 *d = Direct3DCreate9(D3D_SDK_VERSION);
    if (!d) { result("d3d9", 0, 0, 0, "Direct3DCreate9 failed"); return 1; }
    D3DADAPTER_IDENTIFIER9 id; IDirect3D9_GetAdapterIdentifier(d, 0, 0, &id);
    D3DPRESENT_PARAMETERS pp = {0}; pp.Windowed = TRUE; pp.SwapEffect = D3DSWAPEFFECT_DISCARD; pp.PresentationInterval = D3DPRESENT_INTERVAL_IMMEDIATE;
    IDirect3DDevice9 *dev;
    HRESULT hr = IDirect3D9_CreateDevice(d, 0, D3DDEVTYPE_HAL, w, D3DCREATE_HARDWARE_VERTEXPROCESSING, &pp, &dev);
    if (FAILED(hr)) { char e[64]; sprintf(e, "CreateDevice hr=0x%08lx", hr); result("d3d9", 0, 0, 0, e); return 1; }
    static V v[TRIS * 3];
    IDirect3DDevice9_SetFVF(dev, D3DFVF_XYZRHW | D3DFVF_DIFFUSE);
    int frames = 0; double t0 = now(), t;
    while ((t = now() - t0) < SECONDS && pump()) {
        for (int i = 0; i < TRIS * 3; i++) {
            float a = i * 0.37f + (float)t, r = 50 + (i % 300);
            v[i] = (V){ 400 + r * cosf(a), 300 + r * sinf(a), 0.5f, 1, 0xff000000 | (i * 2654435761u >> 8) };
        }
        IDirect3DDevice9_Clear(dev, 0, 0, D3DCLEAR_TARGET, D3DCOLOR_XRGB(frames & 255, 40, 90), 1, 0);
        IDirect3DDevice9_BeginScene(dev);
        IDirect3DDevice9_DrawPrimitiveUP(dev, D3DPT_TRIANGLELIST, TRIS, v, sizeof(V));
        IDirect3DDevice9_EndScene(dev);
        if (FAILED(IDirect3DDevice9_Present(dev, 0, 0, 0, 0))) break;
        frames++;
    }
    char det[600]; sprintf(det, "adapter=\"%s\" driver=\"%s\"", id.Description, id.Driver);
    result("d3d9", frames > 0, frames, t, det);
    return 0;
}
