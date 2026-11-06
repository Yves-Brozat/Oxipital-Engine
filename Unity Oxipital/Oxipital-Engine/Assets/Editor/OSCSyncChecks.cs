using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using OSCQuery.UnityOSC;
using UnityEditor;
using UnityEngine;

namespace Oxipital.Editor
{
    public static class OSCSyncChecks
    {
        const BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;

        [MenuItem("Tools/Oxipital/Validate OSC Synchronization")]
        public static void Run()
        {
            var go = new GameObject("OSC sync check");
            go.SetActive(false);
            try
            {
                var probe = go.AddComponent<OSCInputProbe>();
                var query = go.AddComponent<OSCQuery.OSCQuery>();
                query.rootObject = go;
                query.componentFilterMode = OSCQuery.OSCQuery.FilterMode.Include;
                query.filteredComponentNames = new List<string> { nameof(OSCInputProbe) };
                Call(query, "OnEnable");
                var receiver = new OSCReceiver();
                typeof(OSCQuery.OSCQuery).GetField("receiver", Private).SetValue(query, receiver);

                // A bad vector must not prevent the next control from arriving.
                receiver.EnqueuePacket(Message("position", 1f));
                receiver.EnqueuePacket(Message("scalar", .75f));
                Call(query, "ProcessIncomingMessages");
                Require(probe.scalar == .75f, "Invalid packet interrupted the sync");

                // WebSocket OSC must follow exactly the same path as UDP,
                // including nested bundles and double precision vector values.
                // OSCBundle.Pack is not implemented in UnityOSC, so construct
                // the wire format independently of the production decoder.
                byte[] bundle = Bundle(Bundle(Message("position", 1d, 2d, 3d).BinaryData),
                    Message("scalar", .5f).BinaryData);
                Call(query, "wsDataReceived", new WSQuery(), bundle);
                Call(query, "ProcessIncomingMessages");
                Require(probe.position == new Vector3(1, 2, 3) && probe.scalar == .5f,
                    "WebSocket bundle did not update controls");

                int port;
                using (var reservation = new UdpClient(new IPEndPoint(IPAddress.Loopback, 0)))
                    port = ((IPEndPoint)reservation.Client.LocalEndPoint).Port;
                receiver.Open(port);
                try
                {
                    using (var sender = new UdpClient())
                    {
                        byte[] bytes = Message("scalar", .625f).BinaryData;
                        sender.Send(bytes, bytes.Length, new IPEndPoint(IPAddress.Loopback, port));
                    }
                    var timeout = System.Diagnostics.Stopwatch.StartNew();
                    while (!receiver.hasWaitingMessages() && timeout.ElapsedMilliseconds < 2000) Thread.Sleep(5);
                    Require(receiver.hasWaitingMessages(), "UDP receiver stopped responding");
                    Call(query, "ProcessIncomingMessages");
                    Require(probe.scalar == .625f, "UDP control did not apply after WebSocket control");

                    // Recall-sized bursts must survive the OS socket queue,
                    // even while the Unity main thread has not drained OSC yet.
                    const int burstSize = 1200;
                    var datagrams = new byte[burstSize][];
                    for (int i = 0; i < burstSize; i++) datagrams[i] = Message("scalar", (float)i).BinaryData;
                    using (var sender = new UdpClient())
                        foreach (byte[] bytes in datagrams)
                            sender.Send(bytes, bytes.Length, new IPEndPoint(IPAddress.Loopback, port));
                    int received = 0;
                    timeout.Restart();
                    while (received < burstSize && timeout.ElapsedMilliseconds < 3000)
                    {
                        while (receiver.hasWaitingMessages())
                        {
                            var packet = receiver.getNextMessage();
                            Require((float)packet.Data[0] == received, "OSC preset burst lost or reordered a value");
                            received++;
                        }
                        if (received < burstSize) Thread.Sleep(1);
                    }
                    Require(received == burstSize, "OSC preset burst was only partially received: " + received + "/" + burstSize);
                }
                finally { receiver.Close(); }

                var clients = new WSQuery[8];
                for (int i = 0; i < clients.Length; i++) clients[i] = new WSQuery();
                Parallel.ForEach(clients, client =>
                {
                    for (int i = 0; i < 100; i++)
                    {
                        Call(query, "wsSocketOpened", client);
                        Call(query, "wsMessageReceived", client, "{\"COMMAND\":\"LISTEN\",\"DATA\":\"/OSCInputProbe/scalar\"}");
                        Call(query, "wsSocketClosed", client);
                    }
                });
                Call(query, "ProcessSocketEvents");
                var subscriptions = (Dictionary<WSQuery, List<string>>)typeof(OSCQuery.OSCQuery)
                    .GetField("propQueryMap", Private).GetValue(query);
                Require(subscriptions.Count == 0, "Reconnects left stale subscriptions");

                var connected = clients[0];
                Call(query, "wsSocketOpened", connected);
                for (int i = 0; i < 2; i++)
                    Call(query, "wsMessageReceived", connected, "{\"COMMAND\":\"LISTEN\",\"DATA\":\"/OSCInputProbe/scalar\"}");
                Call(query, "ProcessSocketEvents");
                Require(subscriptions[connected].Count == 1, "LISTEN duplicates accumulated");
                Call(query, "wsMessageReceived", connected, "{\"COMMAND\":\"IGNORE\",\"DATA\":\"/OSCInputProbe/scalar\"}");
                Call(query, "ProcessSocketEvents");
                Require(subscriptions[connected].Count == 0, "IGNORE left duplicate feedback");
                Call(query, "wsSocketClosed", connected);
                Call(query, "ProcessSocketEvents");
                Call(query, "OnDisable");
                Debug.Log("OSC_SYNC_PASS: invalid packet recovery, WebSocket nested bundles, double vectors, UDP reception, 800 concurrent reconnects, duplicate subscriptions and IGNORE.");
            }
            finally { UnityEngine.Object.DestroyImmediate(go); }
        }

        public static void RunBatch()
        {
            try { Run(); EditorApplication.Exit(0); }
            catch (Exception e) { Debug.LogException(e); EditorApplication.Exit(1); }
        }

        static OSCMessage Message(string field, params object[] values)
        {
            var message = new OSCMessage("/OSCInputProbe/" + field);
            foreach (object value in values) message.Append(value);
            return message;
        }

        static byte[] Bundle(params byte[][] packets)
        {
            using (var stream = new MemoryStream())
            {
                byte[] header = System.Text.Encoding.ASCII.GetBytes("#bundle\0");
                stream.Write(header, 0, header.Length);
                stream.Write(new byte[8], 0, 8);
                foreach (byte[] packet in packets)
                {
                    byte[] length = BitConverter.GetBytes(System.Net.IPAddress.HostToNetworkOrder(packet.Length));
                    stream.Write(length, 0, length.Length);
                    stream.Write(packet, 0, packet.Length);
                }
                return stream.ToArray();
            }
        }

        static void Call(object target, string method, params object[] args)
        {
            target.GetType().GetMethod(method, Private).Invoke(target, args);
        }

        static void Require(bool condition, string message)
        {
            if (!condition) throw new Exception(message);
        }
    }
}
