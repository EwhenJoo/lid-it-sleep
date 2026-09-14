using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace LidItSleep
{
    public static class SleepRequest
    {
        public delegate bool SuspendApi(bool hibernate, bool force, bool disableWakeEvents);

        // This boundary is tested with a fake API. Sleep only; never fall back to hibernation.
        public static bool Invoke(SuspendApi api)
        {
            if (api == null) throw new ArgumentNullException("api");
            return api(false, false, false);
        }

        public static bool Request()
        {
            return WithPrivilege(delegate {
                if (!Invoke(SetSuspendState)) throw new Win32Exception(Marshal.GetLastWin32Error());
                return true;
            });
        }
        // Checks privilege availability without issuing any power-state request.
        public static bool CheckAccess() { return WithPrivilege(delegate { return true; }); }

        [StructLayout(LayoutKind.Sequential)]
        private struct Luid { public uint Low; public int High; }
        [StructLayout(LayoutKind.Sequential)]
        private struct TokenPrivileges { public uint Count; public Luid Luid; public uint Attributes; }
        [DllImport("powrprof.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.U1)]
        private static extern bool SetSuspendState([MarshalAs(UnmanagedType.U1)] bool hibernate,
            [MarshalAs(UnmanagedType.U1)] bool force, [MarshalAs(UnmanagedType.U1)] bool disableWakeEvents);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool LookupPrivilegeValue(string system, string name, out Luid luid);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokenPrivileges state,
            uint length, out TokenPrivileges previous, out uint required);
        [DllImport("advapi32.dll", EntryPoint = "AdjustTokenPrivileges", SetLastError = true)]
        private static extern bool RestoreTokenPrivileges(IntPtr token, bool disableAll, ref TokenPrivileges state,
            uint length, IntPtr previous, IntPtr required);
        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        private static bool WithPrivilege(Func<bool> operation)
        {
            IntPtr token;
            if (!OpenProcessToken(Process.GetCurrentProcess().Handle, 0x28, out token)) throw new Win32Exception();
            TokenPrivileges previous = new TokenPrivileges();
            bool adjusted = false;
            try
            {
                Luid luid;
                if (!LookupPrivilegeValue(null, "SeShutdownPrivilege", out luid)) throw new Win32Exception();
                TokenPrivileges enable = new TokenPrivileges { Count = 1, Luid = luid, Attributes = 2 };
                uint required;
                bool success = AdjustTokenPrivileges(token, false, ref enable,
                    (uint)Marshal.SizeOf(typeof(TokenPrivileges)), out previous, out required);
                int error = Marshal.GetLastWin32Error();
                if (!success || error != 0) throw new Win32Exception(error);
                adjusted = true;
                return operation();
            }
            finally
            {
                if (adjusted) RestoreTokenPrivileges(token, false, ref previous, 0, IntPtr.Zero, IntPtr.Zero);
                CloseHandle(token);
            }
        }
    }
}
