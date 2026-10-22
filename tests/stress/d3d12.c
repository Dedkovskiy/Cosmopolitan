// Direct3D 12: command queue, flip-model swap chain, per-frame command list that clears the back buffer, fence wait. x64 only.
#define COBJMACROS
#define INITGUID   // emit the D3D12 / DXGI 1.4 interface IDs here; mingw-w64's libuuid lacks them
#define WIDL_C_INLINE_WRAPPERS   // struct-returning methods (descriptor handle, LUID) need mingw's ABI-correct wrappers
#include "common.h"
#include <d3d12.h>
#include <dxgi1_4.h>

int main(void) {
    HWND w = make_window("Stress D3D12");
    IDXGIFactory4 *f; ID3D12Device *dev; HRESULT hr;
    if (FAILED(hr = CreateDXGIFactory1(&IID_IDXGIFactory4, (void **)&f))) { result("d3d12", 0, 0, 0, "CreateDXGIFactory1 failed"); return 1; }
    if (FAILED(hr = D3D12CreateDevice(0, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&dev))) {
        char e[64]; sprintf(e, "D3D12CreateDevice hr=0x%08lx", hr); result("d3d12", 0, 0, 0, e); return 1;
    }
    D3D12_COMMAND_QUEUE_DESC qd = {0}; ID3D12CommandQueue *q;
    ID3D12Device_CreateCommandQueue(dev, &qd, &IID_ID3D12CommandQueue, (void **)&q);
    DXGI_SWAP_CHAIN_DESC1 sd = {0};
    sd.Width = 800; sd.Height = 600; sd.Format = DXGI_FORMAT_R8G8B8A8_UNORM; sd.SampleDesc.Count = 1;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.BufferCount = 2; sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    IDXGISwapChain1 *sc1; IDXGISwapChain3 *sc;
    if (FAILED(hr = IDXGIFactory4_CreateSwapChainForHwnd(f, (IUnknown *)q, w, &sd, 0, 0, &sc1))) {
        char e[64]; sprintf(e, "CreateSwapChainForHwnd hr=0x%08lx", hr); result("d3d12", 0, 0, 0, e); return 1;
    }
    IDXGISwapChain1_QueryInterface(sc1, &IID_IDXGISwapChain3, (void **)&sc);
    D3D12_DESCRIPTOR_HEAP_DESC hd = { D3D12_DESCRIPTOR_HEAP_TYPE_RTV, 2, 0, 0 }; ID3D12DescriptorHeap *heap;
    ID3D12Device_CreateDescriptorHeap(dev, &hd, &IID_ID3D12DescriptorHeap, (void **)&heap);
    UINT inc = ID3D12Device_GetDescriptorHandleIncrementSize(dev, D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    D3D12_CPU_DESCRIPTOR_HANDLE base = ID3D12DescriptorHeap_GetCPUDescriptorHandleForHeapStart(heap);
    ID3D12Resource *bufs[2];
    for (int i = 0; i < 2; i++) {
        IDXGISwapChain3_GetBuffer(sc, i, &IID_ID3D12Resource, (void **)&bufs[i]);
        D3D12_CPU_DESCRIPTOR_HANDLE h = { base.ptr + i * inc }; ID3D12Device_CreateRenderTargetView(dev, bufs[i], 0, h);
    }
    ID3D12CommandAllocator *al; ID3D12GraphicsCommandList *cl; ID3D12Fence *fence; UINT64 fv = 0; HANDLE ev = CreateEventA(0, 0, 0, 0);
    ID3D12Device_CreateCommandAllocator(dev, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void **)&al);
    ID3D12Device_CreateCommandList(dev, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, al, 0, &IID_ID3D12GraphicsCommandList, (void **)&cl);
    ID3D12GraphicsCommandList_Close(cl);
    ID3D12Device_CreateFence(dev, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void **)&fence);
    LUID luid = ID3D12Device_GetAdapterLuid(dev);
    DXGI_ADAPTER_DESC1 desc = {0}; IDXGIAdapter1 *ad;
    for (UINT i = 0; IDXGIFactory4_EnumAdapters1(f, i, &ad) == S_OK; i++) { IDXGIAdapter1_GetDesc1(ad, &desc); if (!memcmp(&desc.AdapterLuid, &luid, sizeof luid)) break; }
    int frames = 0; double t0 = now(), t;
    while ((t = now() - t0) < SECONDS && pump()) {
        UINT bi = IDXGISwapChain3_GetCurrentBackBufferIndex(sc);
        ID3D12CommandAllocator_Reset(al); ID3D12GraphicsCommandList_Reset(cl, al, 0);
        D3D12_RESOURCE_BARRIER b = { D3D12_RESOURCE_BARRIER_TYPE_TRANSITION };
        b.Transition.pResource = bufs[bi]; b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        b.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT; b.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
        ID3D12GraphicsCommandList_ResourceBarrier(cl, 1, &b);
        float c[4] = { 0.2f, (frames & 255) / 255.f, 0.5f, 1 }; D3D12_CPU_DESCRIPTOR_HANDLE h = { base.ptr + bi * inc };
        ID3D12GraphicsCommandList_ClearRenderTargetView(cl, h, c, 0, 0);
        b.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET; b.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
        ID3D12GraphicsCommandList_ResourceBarrier(cl, 1, &b);
        ID3D12GraphicsCommandList_Close(cl);
        ID3D12CommandQueue_ExecuteCommandLists(q, 1, (ID3D12CommandList **)&cl);
        if (FAILED(IDXGISwapChain3_Present(sc, 0, 0))) break;
        ID3D12CommandQueue_Signal(q, fence, ++fv);   // ponytail: wait every frame, no frame pipelining; this measures "works", not peak GPU throughput
        if (ID3D12Fence_GetCompletedValue(fence) < fv) { ID3D12Fence_SetEventOnCompletion(fence, fv, ev); WaitForSingleObject(ev, 2000); }
        frames++;
    }
    char det[300]; sprintf(det, "adapter=\"%ls\"", desc.Description);
    result("d3d12", frames > 0, frames, t, det);
    return 0;
}
