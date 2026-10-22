// System queries done natively instead of spawning ps / pgrep / ioreg / pmset / sysctl shells (each spawn costs 20–60 ms, and the
// status refresh runs every 5 s). IOKit for HID controllers and power source, libproc + sysctl(KERN_PROCARGS2) for process search.
#include "cosmo_native.h"
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>
#include <CoreFoundation/CoreFoundation.h>
#include <libproc.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <string>
#include <vector>
#include <cstring>

namespace {
std::string cfstr(CFTypeRef v) {
    if (!v || CFGetTypeID(v) != CFStringGetTypeID()) return "";
    char buf[256]; return CFStringGetCString((CFStringRef)v, buf, sizeof buf, kCFStringEncodingUTF8) ? buf : "";
}
CFDictionaryRef usage_match(uint32_t page, uint32_t usage) {
    CFNumberRef p = CFNumberCreate(nullptr, kCFNumberSInt32Type, &page), u = CFNumberCreate(nullptr, kCFNumberSInt32Type, &usage);
    const void *keys[] = { CFSTR(kIOHIDDeviceUsagePageKey), CFSTR(kIOHIDDeviceUsageKey) }, *vals[] = { p, u };
    CFDictionaryRef d = CFDictionaryCreate(nullptr, keys, vals, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRelease(p); CFRelease(u); return d;
}
}

// Connected game controllers (gamepads, joysticks, multi-axis), comma-separated product names. Returns the count.
extern "C" int cosmo_controllers(char *out, size_t cap) {
    if (cap) out[0] = 0;
    IOHIDManagerRef m = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!m) return 0;
    CFDictionaryRef g = usage_match(kHIDPage_GenericDesktop, kHIDUsage_GD_GamePad), j = usage_match(kHIDPage_GenericDesktop, kHIDUsage_GD_Joystick), x = usage_match(kHIDPage_GenericDesktop, kHIDUsage_GD_MultiAxisController);
    const void *arr[] = { g, j, x }; CFArrayRef matches = CFArrayCreate(nullptr, arr, 3, &kCFTypeArrayCallBacks);
    IOHIDManagerSetDeviceMatchingMultiple(m, matches);
    CFSetRef set = IOHIDManagerCopyDevices(m);
    int n = 0; std::string names;
    if (set) {
        CFIndex c = CFSetGetCount(set); std::vector<const void *> devs(c); CFSetGetValues(set, devs.data());
        for (CFIndex i = 0; i < c; i++) {
            IOHIDDeviceRef d = (IOHIDDeviceRef)devs[i];
            std::string name = cfstr(IOHIDDeviceGetProperty(d, CFSTR(kIOHIDProductKey)));
            if (name.empty()) continue;
            if (names.find(name) == std::string::npos) { if (!names.empty()) names += ", "; names += name; n++; }
        }
        CFRelease(set);
    }
    CFRelease(matches); CFRelease(g); CFRelease(j); CFRelease(x); CFRelease(m);
    if (cap) { strncpy(out, names.c_str(), cap - 1); out[cap - 1] = 0; }
    return n;
}

// 1 when running on battery, 0 on AC/UPS, -1 unknown.
extern "C" int cosmo_on_battery(void) {
    CFTypeRef info = IOPSCopyPowerSourcesInfo(); if (!info) return -1;
    CFStringRef t = IOPSGetProvidingPowerSourceType(info);
    int r = t ? (CFStringCompare(t, CFSTR(kIOPMBatteryPowerKey), 0) == kCFCompareEqualTo ? 1 : 0) : -1;
    CFRelease(info); return r;
}

// PIDs of processes whose executable path or any argument contains `needle` (case-sensitive), excluding the caller. Returns count.
extern "C" int cosmo_proc_find(const char *needle, int32_t *pids, int cap) {
    int n = proc_listallpids(nullptr, 0); if (n <= 0) return 0;
    std::vector<pid_t> all(n * 2); n = proc_listallpids(all.data(), (int)(all.size() * sizeof(pid_t))); if (n <= 0) return 0;
    pid_t me = getpid(); int found = 0;
    size_t argmax = 0; { int mib[2] = { CTL_KERN, KERN_ARGMAX }; int am = 0; size_t sz = sizeof am; if (sysctl(mib, 2, &am, &sz, nullptr, 0) == 0) argmax = (size_t)am; }
    std::vector<char> buf(argmax ? argmax : 65536);
    for (int i = 0; i < n && found < cap; i++) {
        pid_t pid = all[i]; if (pid <= 0 || pid == me) continue;
        int mib[3] = { CTL_KERN, KERN_PROCARGS2, pid }; size_t sz = buf.size();
        if (sysctl(mib, 3, buf.data(), &sz, nullptr, 0) != 0 || sz < sizeof(int)) continue;
        // layout: argc, exec path, NULs, argv[0..], env… — search the whole block up to the arguments' end (stop at first env-looking entry is overkill; the exe path + args are first).
        int argc = *(int *)buf.data(); const char *p = buf.data() + sizeof(int), *end = buf.data() + sz;
        const char *exe = p; p += strlen(p) + 1; while (p < end && *p == 0) p++;
        bool hit = strstr(exe, needle) != nullptr;
        for (int a = 0; a < argc && p < end && !hit; a++) { if (strstr(p, needle)) hit = true; p += strlen(p) + 1; }
        if (hit) pids[found++] = pid;
    }
    return found;
}
