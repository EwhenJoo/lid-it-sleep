using System;

namespace LidItSleep
{
    // Pure decision logic. Unknown values cancel the countdown, never authorize sleep.
    public sealed class GuardPolicy
    {
        public readonly double DelaySeconds;
        public double PendingSince = -1;
        public bool Latched;
        public int Attempts;
        public double RetryAfter;

        public GuardPolicy(double delaySeconds)
        {
            if (delaySeconds < 5 || delaySeconds > 120) throw new ArgumentOutOfRangeException("delaySeconds");
            DelaySeconds = delaySeconds;
        }

        public void Invalidate() { PendingSince = -1; }

        public void CancelDispatch()
        {
            Latched = false;
            Attempts = Math.Max(0, Attempts - 1);
            Invalidate();
        }

        public bool Observe(bool? ac, bool? closed, double now)
        {
            if (ac == true || closed == false)
            {
                PendingSince = -1;
                Latched = false;
                Attempts = 0;
                RetryAfter = 0;
                return false;
            }
            if (!ac.HasValue || !closed.HasValue)
            {
                Invalidate();
                return false;
            }
            if (Latched || now < RetryAfter) return false;
            if (PendingSince < 0) PendingSince = now;
            if (now - PendingSince < DelaySeconds) return false;
            Latched = true;
            PendingSince = -1;
            Attempts++;
            return true;
        }

        public void RequestFailed(double now)
        {
            Invalidate();
            // At most three attempts per closed-lid battery interval, not a tight retry loop.
            Latched = Attempts >= 3;
            RetryAfter = now + 60;
        }
    }
}
