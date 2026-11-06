// Compile alongside the production JSONObject.cs; parse its output with the
// independent System.Text.Json reader, including both serialization paths.
using System;
using System.Text.Json;
using OSCQuery;

static class OSCQueryJsonChecks
{
    static void Main()
    {
        string key = "path\\\"\n";
        string value = "D:\\Gamgie\\Projets\\Oxipital\\Unity\\Screen Capture\n\t\r\b\f\"\u0001 é";
        var root = new JSONObject(JSONObject.Type.OBJECT);
        root.AddField(key, value);
        Check(root.Print(), key, value);
        Check(root.Print(true), key, value);
        string asyncResult = null;
        foreach (var part in root.PrintAsync()) if (part != null) asyncResult = part;
        Check(asyncResult, key, value);
        Console.WriteLine("OSCQUERY_JSON_PASS: Windows paths, quoted keys, controls, Unicode, synchronous and asynchronous output.");
    }

    static void Check(string json, string key, string value)
    {
        using (var document = JsonDocument.Parse(json))
            if (document.RootElement.GetProperty(key).GetString() != value)
                throw new Exception("OSCQuery JSON changed a string value");
    }
}
