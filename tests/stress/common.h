// Shared bits for the driver stress tests: a window, a timed render loop, one result line appended to results.txt next to the exe.
#include <windows.h>
#include <stdio.h>

static HWND make_window(const char *title) {
    WNDCLASSA wc = {0}; wc.lpfnWndProc = DefWindowProcA; wc.hInstance = GetModuleHandleA(0); wc.lpszClassName = "stress";
    RegisterClassA(&wc);
    HWND h = CreateWindowA("stress", title, WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, 800, 600, 0, 0, wc.hInstance, 0);
    return h;
}
static int pump(void) { MSG m; while (PeekMessageA(&m, 0, 0, 0, PM_REMOVE)) { if (m.message == WM_QUIT) return 0; DispatchMessageA(&m); } return 1; }

static void result(const char *api, int ok, int frames, double secs, const char *detail) {
    char path[MAX_PATH]; GetModuleFileNameA(0, path, MAX_PATH); *strrchr(path, '\\') = 0; strcat(path, "\\results.txt");
    FILE *f = fopen(path, "a"); if (!f) return;
    fprintf(f, "%-10s %-4s %s frames=%d fps=%.0f %s\n", api, sizeof(void*) == 8 ? "x64" : "x86", ok ? "OK  " : "FAIL", frames, secs > 0 ? frames / secs : 0, detail);
    fclose(f);
}
#define SECONDS 8.0
static double now(void) { LARGE_INTEGER f, c; QueryPerformanceFrequency(&f); QueryPerformanceCounter(&c); return (double)c.QuadPart / f.QuadPart; }
