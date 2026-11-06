// Compile with the production OSCServer/OSCMessage/OSCPacket/OSCBundle files.
// UnityEngine.Debug is the only engine dependency; network and decoding code
// run unchanged against a real loopback UDP socket.
using System;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Threading;
using OSCQuery.UnityOSC;

namespace UnityEngine
{
    public static class Debug
    {
        public static void LogWarning(object value) { Console.Error.WriteLine(value); }
        public static void LogError(object value) { Console.Error.WriteLine(value); }
    }
}

static class OSCReceiveBurstChecks
{
    static int Main(string[] args)
    {
        const int count = 1200;
        var packets = new byte[count][];
        for (int i = 0; i < count; i++)
            packets[i] = new OSCMessage("/Ballet/Orb_Groups/Orb_Group_1/OrbGroup/presetParameter_" + i.ToString("D4"), i).BinaryData;
        var seen = new bool[count];
        int received = 0;
        var server = new OSCServer(0);
        ((Thread)typeof(OSCServer).GetField("_receiverThread", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(server)).IsBackground = true;
        server.SleepMilliseconds = 1;
        server.PacketReceivedEvent += (sender, packet) =>
        {
            int index = (int)packet.Data[0];
            if (!seen[index]) { seen[index] = true; Interlocked.Increment(ref received); }
        };
        int port = ((IPEndPoint)server.UDPClient.Client.LocalEndPoint).Port;
        using (var sender = new UdpClient())
            for (int i = 0; i < count; i++) sender.Send(packets[i], packets[i].Length, "127.0.0.1", port);
        SpinWait.SpinUntil(() => Volatile.Read(ref received) == count, 2000);
        Console.WriteLine("OSC_RECEIVE_BURST: buffer=" + server.ReceiveBufferSize + ", received=" + received + "/" + count);
        if (args.Length > 0 && args[0] == "--measure") return 0;
        return received == count ? 0 : 1;
    }
}
