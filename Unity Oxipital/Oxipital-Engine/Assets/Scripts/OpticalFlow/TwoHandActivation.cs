namespace Oxipital
{
    // Shared selection keeps split orbs and split forces on the same hand.
    internal static class TwoHandActivation
    {
        // Tracking controls the lifetime only of a source attached to hands.
        internal static bool ForceActive(bool enabled, bool followsHands, bool positionValid)
            => enabled && (!followsHands || positionValid);

        internal static void Resolve(bool single, bool left, bool right, ref int selected,
            out bool activeLeft, out bool activeRight)
        {
            if (!single)
            {
                selected = -1;
                activeLeft = left;
                activeRight = right;
                return;
            }
            if ((selected == 0 && !left) || (selected == 1 && !right)) selected = -1;
            if (selected < 0) selected = left ? 0 : right ? 1 : -1;
            activeLeft = left && selected == 0;
            activeRight = right && selected == 1;
        }
    }
}
