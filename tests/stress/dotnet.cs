// .NET Framework 4 WinForms + GDI+: animated drawing for 8 s, plus LINQ and Task-based work, then one result line.
using System; using System.Drawing; using System.IO; using System.Linq; using System.Threading.Tasks; using System.Windows.Forms;

class Stress : Form {
    int frames; DateTime t0 = DateTime.Now; long sum;
    Stress() {
        Text = "Stress .NET"; ClientSize = new Size(800, 600); DoubleBuffered = true;
        sum = Task.WhenAll(Enumerable.Range(0, 8).Select(i => Task.Run(() => Enumerable.Range(0, 2000000).Where(x => x % 7 == i).Sum(x => (long)x)))).Result.Sum();
        var timer = new Timer { Interval = 1 }; timer.Tick += (s, e) => { Invalidate(); if ((DateTime.Now - t0).TotalSeconds > 8) { Done(); } }; timer.Start();
    }
    protected override void OnPaint(PaintEventArgs e) {
        frames++; var r = new Random(frames);
        for (int i = 0; i < 500; i++) using (var b = new SolidBrush(Color.FromArgb(r.Next(256), r.Next(256), r.Next(256)))) e.Graphics.FillEllipse(b, r.Next(760), r.Next(560), 40, 40);
    }
    void Done() {
        var secs = (DateTime.Now - t0).TotalSeconds;
        File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "results.txt"),
            string.Format("{0,-10} {1,-4} {2} frames={3} fps={4:0} clr={5} linqsum={6}\r\n", "dotnet", Environment.Is64BitProcess ? "x64" : "x86", sum == 1999999000000L ? "OK  " : "FAIL", frames, frames / secs, Environment.Version, sum));
        Environment.Exit(0);
    }
    [STAThread] static void Main() { Application.Run(new Stress()); }
}
