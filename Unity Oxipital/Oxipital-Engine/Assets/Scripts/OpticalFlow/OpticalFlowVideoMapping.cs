namespace Oxipital
{
    // Inverse of OpticalFlowSource.compute Copy: the shader flips output UVs
    // before mapping into the cropped source rectangle.
    internal static class OpticalFlowVideoMapping
    {
        // Fit a rectangle of the requested display aspect inside the existing crop,
        // then zoom around a movable centre without sampling outside that crop.
        public static void Frame(float sourceAspect, float aspect, float zoom, float centerX, float centerY,
            ref float left, ref float right, ref float bottom, ref float top)
        {
            float width = 1 - left - right, height = 1 - bottom - top;
            if (width <= 0 || height <= 0 || sourceAspect <= 0 || aspect <= 0) return;
            float w = System.Math.Min(width, height * aspect / sourceAspect) / System.Math.Max(1, zoom);
            float h = w * sourceAspect / aspect;
            float x = left + width * centerX, y = bottom + height * centerY;
            x = System.Math.Max(left + w / 2, System.Math.Min(1 - right - w / 2, x));
            y = System.Math.Max(bottom + h / 2, System.Math.Min(1 - top - h / 2, y));
            left = x - w / 2; right = 1 - x - w / 2;
            bottom = y - h / 2; top = 1 - y - h / 2;
        }

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
