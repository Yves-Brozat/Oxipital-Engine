#if UNITY_EDITOR
using UnityEngine;

namespace Oxipital
{
    [AddComponentMenu("")]
    public sealed class OSCInputProbe : MonoBehaviour
    {
        public float scalar = 0;
        public int count = 0;
        public double precise = 0;
        public bool active = false;
        public Vector3 position = Vector3.zero;
        public Color color = Color.clear;
    }
}
#endif
