using System.Globalization;
using System.Text;

namespace Ebt.Tests;

public sealed record DbfField(string Name, char Type, int Length, int Decimals = 0);

public static class DbfWriter
{
    static DbfWriter() => Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);

    public static void Write(string path, IReadOnlyList<DbfField> fields, IEnumerable<object?[]> rows, IEnumerable<object?[]>? deleted = null)
    {
        var enc = Encoding.GetEncoding(850);
        var all = rows.Select(r => (false, r)).Concat((deleted ?? []).Select(r => (true, r))).ToList();
        var recordLength = 1 + fields.Sum(f => f.Length);
        using var w = new BinaryWriter(File.Create(path));
        w.Write((byte)0x03);
        w.Write((byte)(DateTime.Today.Year - 1900));
        w.Write((byte)DateTime.Today.Month);
        w.Write((byte)DateTime.Today.Day);
        w.Write(all.Count);
        w.Write((short)(32 + 32 * fields.Count + 1));
        w.Write((short)recordLength);
        w.Write(new byte[20]);
        foreach (var f in fields)
        {
            var name = new byte[11];
            Encoding.ASCII.GetBytes(f.Name).CopyTo(name, 0);
            w.Write(name);
            w.Write((byte)f.Type);
            w.Write(new byte[4]);
            w.Write((byte)f.Length);
            w.Write((byte)f.Decimals);
            w.Write(new byte[14]);
        }
        w.Write((byte)0x0D);
        foreach (var (isDeleted, row) in all)
        {
            w.Write((byte)(isDeleted ? '*' : ' '));
            for (var i = 0; i < fields.Count; i++)
            {
                var f = fields[i];
                var text = row[i] switch
                {
                    null => "",
                    decimal d => d.ToString("F" + f.Decimals, CultureInfo.InvariantCulture),
                    int n => n.ToString(CultureInfo.InvariantCulture),
                    var v => Convert.ToString(v, CultureInfo.InvariantCulture)!
                };
                text = f.Type == 'N' ? text.PadLeft(f.Length) : text.PadRight(f.Length);
                w.Write(enc.GetBytes(text[..f.Length]));
            }
        }
        w.Write((byte)0x1A);
    }

    public static DbfField C(string name, int length) => new(name, 'C', length);
    public static DbfField N(string name, int length, int decimals = 0) => new(name, 'N', length, decimals);
}
