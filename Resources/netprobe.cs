// .NET runtime probe, run once in each bottle: Cosmopolitan marks a bottle's .NET runtime as working only after this prints its line.
// Build: tests/stress/build-netprobe.sh (Wine Mono's own C# compiler inside a throwaway prefix).
using System;
class NetProbe {
    static int Main() {
        Console.WriteLine("netprobe ok clr=" + Environment.Version + " os=" + Environment.OSVersion.Platform + " " + Environment.OSVersion.Version);
        return 0;
    }
}
