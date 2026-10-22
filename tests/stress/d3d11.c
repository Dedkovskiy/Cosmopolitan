// Direct3D 11 (or 10 with -DD3D10): swap chain + clear/present loop as fast as possible; reports the DXGI adapter.
#define COBJMACROS
#include "common.h"
#ifdef D3D10
#include <d3d10.h>
#define API "d3d10"
#else
#include <d3d11.h>
#define API "d3d11"
#endif

int main(void) {
    HWND w = make_window("Stress " API);
    DXGI_SWAP_CHAIN_DESC sd = {0};
    sd.BufferCount = 2; sd.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM; sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow = w; sd.SampleDesc.Count = 1; sd.Windowed = TRUE; sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
    IDXGISwapChain *sc; HRESULT hr;
#ifdef D3D10
    ID3D10Device *dev;
    hr = D3D10CreateDeviceAndSwapChain(0, D3D10_DRIVER_TYPE_HARDWARE, 0, 0, D3D10_SDK_VERSION, &sd, &sc, &dev);
#else
    ID3D11Device *dev; ID3D11DeviceContext *ctx; D3D_FEATURE_LEVEL fl;
    hr = D3D11CreateDeviceAndSwapChain(0, D3D_DRIVER_TYPE_HARDWARE, 0, 0, 0, 0, D3D11_SDK_VERSION, &sd, &sc, &dev, &fl, &ctx);
#endif
    if (FAILED(hr)) { char e[64]; sprintf(e, "create device hr=0x%08lx", hr); result(API, 0, 0, 0, e); return 1; }
    void *bb, *rtv;
#ifdef D3D10
    IDXGISwapChain_GetBuffer(sc, 0, &IID_ID3D10Texture2D, &bb);
    ID3D10Device_CreateRenderTargetView(dev, bb, 0, (ID3D10RenderTargetView **)&rtv);
#else
    IDXGISwapChain_GetBuffer(sc, 0, &IID_ID3D11Texture2D, &bb);
    ID3D11Device_CreateRenderTargetView(dev, bb, 0, (ID3D11RenderTargetView **)&rtv);
#endif
    IDXGIDevice *xd; IDXGIAdapter *ad; DXGI_ADAPTER_DESC desc = {0};
    if (SUCCEEDED(IUnknown_QueryInterface((IUnknown *)dev, &IID_IDXGIDevice, (void **)&xd))) { IDXGIDevice_GetAdapter(xd, &ad); IDXGIAdapter_GetDesc(ad, &desc); }
    int frames = 0; double t0 = now(), t;
    while ((t = now() - t0) < SECONDS && pump()) {
        float c[4] = { (frames & 255) / 255.f, 0.3f, 0.6f, 1 };
#ifdef D3D10
        ID3D10Device_ClearRenderTargetView(dev, rtv, c);
#else
        ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, c);
#endif
        if (FAILED(IDXGISwapChain_Present(sc, 0, 0))) break;
        frames++;
    }
    char det[300];
#ifdef D3D10
    sprintf(det, "adapter=\"%ls\"", desc.Description);
#else
    sprintf(det, "adapter=\"%ls\" featurelevel=%x", desc.Description, fl);
#endif
    result(API, frames > 0, frames, t, det);
    return 0;
}
