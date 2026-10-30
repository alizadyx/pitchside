using System.Text.Json;
using BepInEx;
using BepInEx.Unity.IL2CPP;

namespace Pitchside;

/// <summary>
/// Pitchside — read-only scouting plugin for Football Manager on Apple Silicon Macs.
///
/// It does not touch Unity or the game's managed code at all: a background thread waits
/// for a request file from the viewer app, then reads FM's native database straight from
/// this process's memory and writes JSON next to it. Nothing is ever written to the game.
/// </summary>
[BepInPlugin(Id, Name, Version)]
public class Plugin : BasePlugin
{
    public const string Id = "local.pitchside.plugin";
    public const string Name = "Pitchside";
    public const string Version = "0.6.0";

    private static int _busy;

    public override void Load()
    {
        Pitchside.Log.Source = base.Log;
        Directory.CreateDirectory(Paths.Dir);
        Offsets.Load();   // writes default offsets.json on first run
        Status.Write("idle", -1, "Plugin loaded. Load your save, then press Scan in the app.");
        new Thread(PollLoop) { IsBackground = true, Name = "Pitchside-poll" }.Start();
        Pitchside.Log.Info($"{Name} {Version} loaded — waiting for requests in {Paths.Dir}");
    }

    private static void PollLoop()
    {
        for (;;)
        {
            Thread.Sleep(1000);
            try
            {
                Request req = null;
                if (File.Exists(Paths.Request))
                {
                    string raw = File.ReadAllText(Paths.Request);
                    try { req = JsonSerializer.Deserialize<Request>(raw, Json.Plain); }
                    catch
                    {
                        // Possibly caught mid-write; give it one more tick unless it's old.
                        if ((DateTime.UtcNow - File.GetLastWriteTimeUtc(Paths.Request)).TotalSeconds < 5) continue;
                    }
                    File.Delete(Paths.Request);
                    if (req != null && req.At > 0 &&
                        DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() - req.At > 10 * 60 * 1000)
                    {
                        Pitchside.Log.Warn("Ignoring a request older than 10 minutes.");
                        req = null;
                    }
                }
                else if (File.Exists(Paths.DumpFlag))
                {
                    File.Delete(Paths.DumpFlag);
                    req = new Request { Mode = "dump", Id = "flag" };
                }
                if (req != null) Start(req);
            }
            catch (Exception e) { Pitchside.Log.Warn("poll: " + e.Message); }
        }
    }

    private static void Start(Request req)
    {
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0)
        {
            Pitchside.Log.Warn("A scan is already running — request ignored.");
            return;
        }
        Status.RequestId = req.Id ?? "";
        Task.Run(() =>
        {
            try
            {
                Pitchside.Log.Info($"Starting {req.Mode} ({req.Targets?.Count ?? 0} targets)");
                if (string.Equals(req.Mode, "discover", StringComparison.OrdinalIgnoreCase)) Discovery.Run(req);
                else Dumper.Run(req);
            }
            catch (Exception e)
            {
                Pitchside.Log.Error($"{req.Mode} failed: {e}");
                Status.Write("error", -1, $"{req.Mode} failed: {e.Message}", mode: req.Mode);
            }
            finally
            {
                Interlocked.Exchange(ref _busy, 0);
                GC.Collect();
            }
        });
    }
}
