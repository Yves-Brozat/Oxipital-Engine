using System;
using System.Reflection;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using Klak.Spout;
using OSCQuery.UnityOSC;
using UnityEditor;
using UnityEngine;

namespace Oxipital.Editor
{
    // Focused regression checks without opening a webcam or registering Bonjour services.
    public static class InputIntegrationChecks
    {
        const BindingFlags PrivateInstance = BindingFlags.Instance | BindingFlags.NonPublic;

        [Serializable]
        sealed class NumberMessage
        {
            public string TYPE = "";
            public float[] VALUE = Array.Empty<float>();
        }

        [MenuItem("Tools/Oxipital/Validate Input Integration")]
        public static void Run()
        {
            CheckOSCNumbers();
            CheckOSCUDPInput();
            CheckSpoutSourceSwitching();
            CheckMissingSpoutSender();
            CheckSpoutRetry();
            Debug.Log("INPUT_INTEGRATION_PASS: OSC serialization and UDP writes, Spout source switching, absent sender and native retry backoff.");
        }

        public static void RunBatch()
        {
            try { Run(); EditorApplication.Exit(0); }
            catch (Exception e) { Debug.LogException(e); EditorApplication.Exit(1); }
        }

        static GameObject CreateInactive(string name)
        {
            var go = new GameObject(name) { hideFlags = HideFlags.HideAndDontSave };
            go.SetActive(false);
            return go;
        }

        static void CheckOSCNumbers()
        {
            var go = CreateInactive("OSC number regression");
            try
            {
                var query = go.AddComponent<OSCQuery.OSCQuery>();
                var serialize = typeof(OSCQuery.OSCQuery).GetMethod("getPropObject", PrivateInstance);
                foreach (object value in new object[] { 12.5d, -0.125d, 0d, 12.5f, -0.125f })
                {
                    object json = serialize.Invoke(query, new object[] { value.GetType(), value, null, false });
                    var message = JsonUtility.FromJson<NumberMessage>(json.ToString());
                    Require(message.TYPE == "f", "OSC floating-point type changed");
                    Require(Math.Abs(message.VALUE[0] - Convert.ToDouble(value)) < .00001,
                        "OSC floating-point value changed");
                }
                var video = go.AddComponent<UnityEngine.Video.VideoPlayer>();
                // This is the boxed native property that used to throw during tree creation.
                serialize.Invoke(query, new object[] { typeof(double), video.time, null, false });
            }
            finally { UnityEngine.Object.DestroyImmediate(go); }
        }

        static void CheckSpoutSourceSwitching()
        {
            var go = CreateInactive("Spout switching regression");
            try
            {
                var receiver = go.AddComponent<SpoutReceiver>();
                var source = go.AddComponent<OpticalFlowSource>();
                source.receiver = receiver;
                var setActive = typeof(OpticalFlowSource).GetMethod("SetSpoutActive", PrivateInstance);
                setActive.Invoke(source, new object[] { false });
                Require(!receiver.enabled, "Unused Spout receiver still enabled");
                setActive.Invoke(source, new object[] { true });
                Require(receiver.enabled, "Spout receiver did not resume");
                receiver.enabled = false;
                setActive.Invoke(source, new object[] { false });
                setActive.Invoke(source, new object[] { true });
                Require(!receiver.enabled, "Manually disabled Spout receiver was re-enabled");
            }
            finally { UnityEngine.Object.DestroyImmediate(go); }
        }

        static void CheckOSCUDPInput()
        {
            var go = CreateInactive("OSC UDP regression");
            var receiver = new OSCReceiver();
            try
            {
                var probe = go.AddComponent<OSCInputProbe>();
                var query = go.AddComponent<OSCQuery.OSCQuery>();
                query.rootObject = go;
                query.componentFilterMode = OSCQuery.OSCQuery.FilterMode.Include;
                query.filteredComponentNames = new List<string> { nameof(OSCInputProbe) };
                typeof(OSCQuery.OSCQuery).GetMethod("rebuildDataTree", PrivateInstance).Invoke(query, null);
                int port;
                using (var reservation = new UdpClient(new IPEndPoint(IPAddress.Loopback, 0)))
                    port = ((IPEndPoint)reservation.Client.LocalEndPoint).Port;
                receiver.Open(port);
                typeof(OSCQuery.OSCQuery).GetField("receiver", PrivateInstance).SetValue(query, receiver);
                SendOSC(query, receiver, port, "scalar", 1.25f);
                SendOSC(query, receiver, port, "count", 3f);
                SendOSC(query, receiver, port, "precise", 12.125d);
                SendOSC(query, receiver, port, "active", 1);
                SendOSC(query, receiver, port, "position", .1f, .2f, .3f);
                SendOSC(query, receiver, port, "color", .1f, .2f, .3f, .8f);
                Require(Mathf.Abs(probe.scalar - 1.25f) < .0001f, "OSC scalar write failed");
                Require(probe.count == 3, "OSC float to integer write failed");
                Require(Math.Abs(probe.precise - 12.125d) < .00001, "OSC double write failed");
                Require(probe.active, "OSC boolean write failed");
                Require(Vector3.Distance(probe.position, new Vector3(.1f, .2f, .3f)) < .0001f, "OSC vector write failed");
                Require(Mathf.Abs(probe.color.a - .8f) < .0001f, "OSC RGBA alpha write failed");
            }
            finally { receiver.Close(); UnityEngine.Object.DestroyImmediate(go); }
        }

        static void SendOSC(OSCQuery.OSCQuery query, OSCReceiver receiver, int port, string field, params object[] values)
        {
            var message = new OSCMessage("/" + nameof(OSCInputProbe) + "/" + field);
            foreach (object value in values) message.Append(value);
            using (var sender = new UdpClient())
            {
                byte[] bytes = message.BinaryData;
                sender.Send(bytes, bytes.Length, new IPEndPoint(IPAddress.Loopback, port));
            }
            var wait = System.Diagnostics.Stopwatch.StartNew();
            while (!receiver.hasWaitingMessages() && wait.ElapsedMilliseconds < 2000) Thread.Sleep(5);
            Require(receiver.hasWaitingMessages(), "OSC UDP packet was not received");
            typeof(OSCQuery.OSCQuery).GetMethod("ProcessIncomingMessages", PrivateInstance).Invoke(query, null);
        }

        static void CheckMissingSpoutSender()
        {
            var go = CreateInactive("Missing Spout sender regression");
            try
            {
                var receiver = go.AddComponent<SpoutReceiver>();
                receiver.sourceName = "Oxipital-Missing-Test-" + Guid.NewGuid().ToString("N");
                var update = typeof(SpoutReceiver).GetMethod("Update", PrivateInstance);
                for (int i = 0; i < 1000; i++) update.Invoke(receiver, null);
                Require(typeof(SpoutReceiver).GetField("_receiver", PrivateInstance).GetValue(receiver) == null,
                    "Native receiver allocated for an absent sender");
            }
            finally { UnityEngine.Object.DestroyImmediate(go); }
        }

        static void CheckSpoutRetry()
        {
            Type type = typeof(SpoutReceiver).Assembly.GetType("Klak.Spout.Receiver", true);
            var receiver = (IDisposable)Activator.CreateInstance(type, new object[] { "Oxipital-Retry-Test-" + Guid.NewGuid().ToString("N") });
            try
            {
                var next = type.GetField("_nextConnectionAttempt", PrivateInstance);
                var delay = type.GetField("_connectionRetryDelay", PrivateInstance);
                var update = type.GetMethod("Update");
                double scheduled = (double)next.GetValue(receiver);
                for (int i = 0; i < 100; i++) update.Invoke(receiver, null);
                Require((double)next.GetValue(receiver) == scheduled, "Disconnected receiver retries every frame");
                foreach (double expected in new[] { .5, 1, 2, 2 })
                {
                    next.SetValue(receiver, 0d);
                    update.Invoke(receiver, null);
                    Require((double)delay.GetValue(receiver) == expected, "Spout retry backoff is incorrect");
                    Require((double)next.GetValue(receiver) > Time.realtimeSinceStartupAsDouble, "Spout retry was not delayed");
                }
            }
            finally { receiver.Dispose(); }
        }

        static void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
    }
}
