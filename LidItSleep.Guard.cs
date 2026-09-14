using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace LidItSleep
{
    internal static class GuardNative
    {
        [StructLayout(LayoutKind.Sequential)]
        internal struct PowerStatus
        {
            public byte ACLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag;
            public uint BatteryLifeTime, BatteryFullLifeTime;
        }
        [DllImport("kernel32.dll")]
        internal static extern bool GetSystemPowerStatus(out PowerStatus status);
        [DllImport("user32.dll", SetLastError = true)]
        internal static extern IntPtr RegisterPowerSettingNotification(IntPtr recipient, ref Guid setting, uint flags);
        [DllImport("user32.dll")]
        internal static extern bool UnregisterPowerSettingNotification(IntPtr handle);
        [DllImport("powrprof.dll")]
        [return: MarshalAs(UnmanagedType.U1)]
        internal static extern bool IsPwrHibernateAllowed();
    }

    internal sealed class GuardWindow : Form
    {
        private Guid lidGuid = new Guid("BA3E0F4D-B817-4094-A2D1-D56379E6A0F3");
        private Guid sourceGuid = new Guid("5D3E9A59-E9D5-4B00-A6BD-FF34FF516548");
        private IntPtr lidRegistration, sourceRegistration;
        private readonly GuardPolicy policy;
        private readonly bool observeOnly;
        private readonly double runSeconds;
        private readonly string stateDirectory;
        private readonly Stopwatch clock = Stopwatch.StartNew();
        private readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
        private bool? closed, ac;
        private double lastTick, lastStatus;
        private Process request;

        public GuardWindow(bool observe, double seconds, int delay, string directory)
        {
            observeOnly = observe;
            runSeconds = seconds;
            policy = new GuardPolicy(delay);
            stateDirectory = directory;
            Directory.CreateDirectory(directory);
            ShowInTaskbar = false;
            RegisterLid();
            sourceRegistration = GuardNative.RegisterPowerSettingNotification(Handle, ref sourceGuid, 0);
            if (sourceRegistration == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
            Log("Started mode=" + (observeOnly ? "observe" : "protect") + "; delay=" + delay + "s");
            timer.Interval = 1000;
            timer.Tick += Tick;
            timer.Start();
            WriteStatus();
        }

        protected override void SetVisibleCore(bool value) { base.SetVisibleCore(false); }

        private void RegisterLid()
        {
            if (lidRegistration != IntPtr.Zero) GuardNative.UnregisterPowerSettingNotification(lidRegistration);
            lidRegistration = GuardNative.RegisterPowerSettingNotification(Handle, ref lidGuid, 0);
            if (lidRegistration == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
        }

        private void RefreshAfterResume()
        {
            // Do not reuse a pre-suspend lid value or an expired countdown after resume.
            closed = null;
            policy.Invalidate();
            RegisterLid();
            Log("Resume/message-loop gap: waiting for a fresh lid notification");
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == 0x218) // WM_POWERBROADCAST
            {
                int code = message.WParam.ToInt32();
                if (code == 0x8013 && message.LParam != IntPtr.Zero)
                {
                    Guid setting = (Guid)Marshal.PtrToStructure(message.LParam, typeof(Guid));
                    if (Marshal.ReadInt32(message.LParam, 16) == 4)
                    {
                        int value = Marshal.ReadInt32(message.LParam, 20);
                        if (setting == lidGuid)
                        {
                            closed = value == 0 ? (bool?)true : value == 1 ? (bool?)false : null;
                            // Invalidate here so open/reclose between timer ticks cannot retain a countdown.
                            if (closed != true) policy.Observe(ac, closed, clock.Elapsed.TotalSeconds);
                            Log("Lid=" + State(closed));
                            WriteStatus();
                        }
                        else if (setting == sourceGuid)
                        {
                            // Notifications cancel immediately; authorization always uses a fresh native read.
                            if (value != 1) policy.Observe(value == 0 ? (bool?)true : null, closed, clock.Elapsed.TotalSeconds);
                            Log("Power notification=" + value);
                        }
                    }
                }
                else if (code == 4) policy.Invalidate(); // PBT_APMSUSPEND
                else if (code == 18 || code == 7) RefreshAfterResume();
            }
            base.WndProc(ref message);
        }

        private bool? ReadAc()
        {
            GuardNative.PowerStatus status;
            if (!GuardNative.GetSystemPowerStatus(out status) || status.BatteryFlag == 128 || status.BatteryFlag == 255)
                return null;
            return status.ACLineStatus == 0 ? (bool?)false : status.ACLineStatus == 1 ? (bool?)true : null;
        }

        private void Tick(object sender, EventArgs args)
        {
            double now = clock.Elapsed.TotalSeconds;
            if (runSeconds > 0 && now >= runSeconds) { Close(); return; }
            if (lastTick > 0 && now - lastTick > 5) RefreshAfterResume();
            lastTick = now;
            bool? currentAc = ReadAc();
            if (currentAc != ac) { ac = currentAc; Log("AC=" + State(ac)); WriteStatus(); }
            if (request != null)
            {
                if (!request.HasExited) return;
                int exitCode = request.ExitCode;
                request.Dispose();
                request = null;
                Log("Hibernate command exit=" + exitCode + " (acceptance is not proof of S4 entry)");
                if (exitCode != 0) policy.RequestFailed(now);
                WriteStatus();
            }
            double previousPending = policy.PendingSince;
            if (policy.Observe(ac, closed, now))
            {
                // Last power read immediately before dispatch. Lid messages run on this same UI thread.
                bool? dispatchAc = ReadAc();
                if (dispatchAc != false || closed != true)
                {
                    policy.CancelDispatch();
                    policy.Observe(dispatchAc, closed, now);
                    return;
                }
                if (observeOnly) Log("WOULD HIBERNATE: stable battery + closed lid (observe mode)");
                else
                {
                    try
                    {
                        if (!GuardNative.IsPwrHibernateAllowed()) throw new InvalidOperationException("S4 hibernation is unavailable");
                        Log("REQUEST HIBERNATE: stable battery + closed lid; attempt=" + policy.Attempts);
                        request = Process.Start(new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "shutdown.exe"), "/h")
                        {
                            UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden
                        });
                    }
                    catch (Exception error) { Log("Hibernate request failed: " + error.Message); policy.RequestFailed(now); }
                }
                WriteStatus();
            }
            if (previousPending != policy.PendingSince)
            {
                Log(policy.PendingSince >= 0 ? "Countdown started: battery + closed lid" : "Countdown ended/cancelled");
                WriteStatus();
            }
            if (now - lastStatus >= 30) WriteStatus();
        }

        private static string State(bool? value) { return value.HasValue ? value.Value.ToString() : "Unknown"; }
        private void Log(string message)
        {
            string path = Path.Combine(stateDirectory, "guard.log");
            if (File.Exists(path) && new FileInfo(path).Length > 1048576)
            {
                File.Copy(path, path + ".previous", true);
                File.WriteAllText(path, "");
            }
            File.AppendAllText(path, DateTimeOffset.Now.ToString("o") + " " + message + Environment.NewLine);
        }
        private void WriteStatus()
        {
            lastStatus = clock.Elapsed.TotalSeconds;
            File.WriteAllText(Path.Combine(stateDirectory, "status.txt"),
                "Version=0.2.0\r\nUpdated=" + DateTimeOffset.Now.ToString("o") +
                "\r\nPID=" + Process.GetCurrentProcess().Id + "\r\nMode=" + (observeOnly ? "observe" : "protect") +
                "\r\nAC=" + State(ac) + "\r\nLidClosed=" + State(closed) +
                "\r\nCountdown=" + (policy.PendingSince >= 0) + "\r\nLatched=" + policy.Latched +
                "\r\nAttempts=" + policy.Attempts + "\r\n");
        }
        protected override void OnFormClosed(FormClosedEventArgs args)
        {
            timer.Stop();
            GuardNative.UnregisterPowerSettingNotification(lidRegistration);
            GuardNative.UnregisterPowerSettingNotification(sourceRegistration);
            Log("Stopped");
            base.OnFormClosed(args);
        }
    }

    internal static class GuardProgram
    {
        [STAThread]
        private static int Main(string[] args)
        {
            bool observe = false;
            int delay = 10, seconds = 0;
            string directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LidItSleep", "state");
            try
            {
                for (int i = 0; i < args.Length; i++)
                {
                    if (args[i] == "--observe") observe = true;
                    else if (args[i] == "--seconds") seconds = int.Parse(args[++i]);
                    else if (args[i] == "--delay") delay = int.Parse(args[++i]);
                    else if (args[i] == "--state-dir") directory = args[++i];
                    else throw new ArgumentException("Unknown argument " + args[i]);
                }
                if (seconds < 0 || (seconds > 0 && !observe)) throw new ArgumentException("--seconds requires --observe");
                bool created;
                using (Mutex mutex = new Mutex(true, @"Local\LidItSleep.Guard" + (observe ? ".Observe" : ""), out created))
                {
                    if (!created) return 0;
                    Directory.CreateDirectory(directory);
                    Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
                    Application.Run(new GuardWindow(observe, seconds, delay, directory));
                }
                return 0;
            }
            catch (Exception error)
            {
                try { Directory.CreateDirectory(directory); File.AppendAllText(Path.Combine(directory, "guard.log"), DateTimeOffset.Now.ToString("o") + " FATAL " + error + Environment.NewLine); }
                catch { }
                return 1;
            }
        }
    }
}
