using System;
using System.Collections.Generic;
using System.Reflection;
using UnityEngine;

namespace Oxipital
{
    [CreateAssetMenu(menuName = "Oxipital/Force Brush Preset")]
    public sealed class ForceBrushPreset : ScriptableObject
    {
        [Serializable]
        public struct Value
        {
            public string field;
            public float number;
            public Vector3 vector;
        }
        public List<Value> parameters = new List<Value>();
        static readonly FieldInfo[] fields = typeof(StandardForceGroup).GetFields(BindingFlags.Public | BindingFlags.Instance);

        public void Capture(StandardForceGroup group)
        {
            parameters.Clear();
            foreach (var field in fields)
            {
                if (field.FieldType == typeof(float)) parameters.Add(new Value { field = field.Name, number = (float)field.GetValue(group) });
                else if (field.FieldType == typeof(Vector3)) parameters.Add(new Value { field = field.Name, vector = (Vector3)field.GetValue(group) });
            }
        }

        public void Apply(StandardForceGroup group)
        {
            foreach (var value in parameters)
            {
                var field = typeof(StandardForceGroup).GetField(value.field, BindingFlags.Public | BindingFlags.Instance);
                if (field?.FieldType == typeof(float)) field.SetValue(group, value.number);
                else if (field?.FieldType == typeof(Vector3)) field.SetValue(group, value.vector);
            }
        }

        public void Set(string field, float number)
        {
            for (int i = 0; i < parameters.Count; i++)
                if (parameters[i].field == field) { var value = parameters[i]; value.number = number; parameters[i] = value; return; }
            parameters.Add(new Value { field = field, number = number });
        }
    }
}
