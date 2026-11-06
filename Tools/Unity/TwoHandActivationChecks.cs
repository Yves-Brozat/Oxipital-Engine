using System;
using Oxipital;

static class TwoHandActivationChecks
{
    static void Check(bool ok, string message) { if (!ok) throw new Exception(message); }
    static void Main()
    {
        bool[] expectedActivation = { false, true, false, false, false, true, false, true };
        for (int mask = 0; mask < 8; mask++)
        {
            bool enabled = (mask & 1) != 0, follows = (mask & 2) != 0, tracked = (mask & 4) != 0;
            bool active = TwoHandActivation.ForceActive(enabled, follows, tracked);
            Check(active == expectedActivation[mask], "Force activation matrix mismatch at " + mask);
        }
        Check(TwoHandActivation.ForceActive(true, false, false), "Fixed source muted without hands");
        Check(!TwoHandActivation.ForceActive(true, true, false), "Hand-attached source survived tracking loss");
        int selected = -1;
        TwoHandActivation.Resolve(true, false, true, ref selected, out bool left, out bool right);
        Check(!left && right && selected == 1, "First detected right hand was not selected");
        TwoHandActivation.Resolve(true, true, true, ref selected, out left, out right);
        Check(!left && right, "Second detected hand stole activation");
        TwoHandActivation.Resolve(true, true, false, ref selected, out left, out right);
        Check(left && !right && selected == 0, "Lost right hand did not hand over to left");
        TwoHandActivation.Resolve(true, false, false, ref selected, out left, out right);
        Check(!left && !right && selected == -1, "Lost tracking did not release activation");
        TwoHandActivation.Resolve(false, true, true, ref selected, out left, out right);
        Check(left && right, "Two-hand mode muted a valid hand");
        for (int mask = 0; mask < 4; mask++)
        {
            TwoHandActivation.Resolve(true, (mask & 1) != 0, (mask & 2) != 0, ref selected, out left, out right);
            Check(!(left && right), "Exclusive mode activated both hands");
        }
        Console.WriteLine("TWO_HAND_ACTIVATION_PASS: independent tracking, stable selection, handover, tracking loss, simultaneous mode and exclusivity.");
    }
}
