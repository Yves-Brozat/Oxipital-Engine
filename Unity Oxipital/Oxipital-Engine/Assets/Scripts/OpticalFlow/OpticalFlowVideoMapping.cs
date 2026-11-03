namespace Oxipital
{
    // Inverse of OpticalFlowSource.compute Copy: the shader flips output UVs
    // before mapping into the cropped source rectangle.
    internal static class OpticalFlowVideoMapping
    {
        public static bool SourceToOutput(ref float u, ref float v, float left, float right, float bottom, float top, bool mirror, bool flipY)
        {
            float width = 1 - left - right, height = 1 - bottom - top;
            if (width <= 0 || height <= 0) return false;
            u = (u - left) / width;
            v = (v - bottom) / height;
            if (mirror) u = 1 - u;
            if (flipY) v = 1 - v;
            return u >= 0 && u <= 1 && v >= 0 && v <= 1;
        }

        public static bool ScreenToViewport(float x, float y, float screenWidth, float screenHeight,
            float viewportX, float viewportY, float viewportWidth, float viewportHeight, out float u, out float v)
        {
            u = v = 0;
            if (screenWidth <= 0 || screenHeight <= 0 || viewportWidth <= 0 || viewportHeight <= 0) return false;
            u = (x / screenWidth - viewportX) / viewportWidth;
            v = (y / screenHeight - viewportY) / viewportHeight;
            return true;
        }
    }
}
